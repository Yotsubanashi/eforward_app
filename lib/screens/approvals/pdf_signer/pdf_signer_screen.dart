import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Factory, compute;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:eforward_app/config/app_env.dart';
import 'package:eforward_app/services/session_expiry_service.dart';
import 'package:eforward_app/utils/manila_time.dart';
import 'package:eforward_app/screens/approvals/approvals_screen.dart';
import 'package:eforward_app/widgets/app_snackbar.dart';
import 'package:eforward_app/widgets/loading_overlay.dart';

/// Runs on a background isolate via [compute] — parses the PDF just to read
/// each page's intrinsic size. Must be a top-level function (isolates can't
/// close over instance state) and only pass/return simple, isolate-safe
/// data (raw bytes in, plain `[width, height]` pairs out).
List<List<double>> _parsePdfPageSizes(Uint8List bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  final sizes = <List<double>>[];
  for (int i = 0; i < doc.pages.count; i++) {
    final page = doc.pages[i];
    final s = page.size;
    // Syncfusion's page.size reports the UN-rotated MediaBox, but every PDF
    // viewer displays the page with its /Rotate applied. For 90°/270° the
    // visible page has width/height swapped (portrait scan shown landscape).
    // Return the VISUAL size so the on-screen overlay rect matches what the
    // user sees — the rotation-aware stamping (see _drawImageOnPage) maps the
    // same visual fractions back onto the un-rotated page.
    final rot = page.rotation;
    if (rot == PdfPageRotateAngle.rotateAngle90 ||
        rot == PdfPageRotateAngle.rotateAngle270) {
      sizes.add([s.height, s.width]);
    } else {
      sizes.add([s.width, s.height]);
    }
  }
  doc.dispose();
  return sizes;
}

// ─────────────────────────────────────────────────────────────────────────────
// PDF SIGNER PAGE
//
// KEY FIXES (v2):
//  1. Fraction-based overlay positioning — _sigFracX/Y/W/H store position as
//     a fraction of the viewport (0.0–1.0).  Screen pixels = frac × viewport.
//     This is zoom-independent because we never touch PDFView's internal
//     transform.
//  2. Pan / scale blocker GestureDetector sits between PDFView and the
//     draggable overlays while in signing mode, so the PDF cannot pan or zoom
//     while the user is placing the signature.
//  3. PDF stamping uses the same fractions mapped directly to PDF point space:
//     pdfX = fracX × pdfWidth — no viewport-to-PDF ratio math needed.
//  4. TransformationController removed entirely (was connected to nothing).
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Constants for the off-screen capture widget.
// The signature RepaintBoundary is always rendered at these pixel dimensions.
// The aspect ratio is derived from these — never from the live image size.
// ─────────────────────────────────────────────────────────────────────────────
const double _kCaptureWidth = 380.0;
// Tighter height → the content (signature + 4 metadata lines) fills the box
// instead of floating with big top/bottom gaps. Lower height = less whitespace
// and visually larger text/signature for the same width.
const double _kCaptureHeight = 66.0;
// True aspect ratio of the signature composite widget (image + metadata Row)
const double _kSigAspectRatio = _kCaptureWidth / _kCaptureHeight; // ≈ 4.52

// The comment capture width is fixed; its height is measured from the actual
// content at render time (see _cmtCaptureHeight) so the box hugs the text
// instead of using a fixed aspect ratio that leaves gaps for short remarks.
const double _kCmtCaptureWidth = 400.0;

// ─────────────────────────────────────────────────────────────────────────────
// Minimum overlay width as a fraction of the PDF page width.
// The signature block (image + name / employee id / date metadata) must stay
// large enough to remain legible when the PDF is PRINTED, but small enough that
// it can tuck into a signature line without overlapping existing content.
// 0.24 of an A4 page (595 pt) ≈ 143 pt ≈ 2 inches wide — still readable on
// paper. Users can shrink down to this, no further.
// ─────────────────────────────────────────────────────────────────────────────
const double _kMinSigFracW = 0.15;
const double _kMinCmtFracW = 0.24;

class PdfSignerPage extends StatefulWidget {
  final String pdfPath;
  final Map<String, dynamic> item;
  final bool enableSigning;
  final bool initialSigningMode;

  const PdfSignerPage({
    super.key,
    required this.pdfPath,
    required this.item,
    this.enableSigning = false,
    this.initialSigningMode = false,
  });

  @override
  State<PdfSignerPage> createState() => _PdfSignerPageState();
}

class _PdfSignerPageState extends State<PdfSignerPage> {
  // ── State flags ───────────────────────────────────────────────────────────
  bool _isSigningMode = false;
  bool _isSubmitting = false;
  bool _isLoadingSignature = true;
  bool _showSignatureLoadingOverlay = false;
  bool _pendingEnterSigningMode = false;
  DateTime? _signedAt;
  Uint8List? _watermarkBytes;
  // Original PDF bytes, cached in memory the first time we read the file.
  // The source is a temp/cache file that Android can purge at any time, so we
  // must NOT rely on it still existing when the signed PDF is generated.
  Uint8List? _pdfBytes;

  // ── Capture keys ──────────────────────────────────────────────────────────
  final GlobalKey _signatureKey = GlobalKey();
  final GlobalKey _commentKey = GlobalKey();

  // ── Signature data ────────────────────────────────────────────────────────
  Uint8List? _signatureBytes;
  String? _signatureText;

  // ── Signer info ───────────────────────────────────────────────────────────
  String _signerName = '';
  // Used to find THIS user's row in routing `details`, which is where a
  // pre-configured signature placement (sign_x/y/width/height/page) lives.
  String _signerEmployeeId = '';

  // ── PDF controller ────────────────────────────────────────────────────────
  PDFViewController? _pdfController;
  int _signaturePage = 0;
  int _currentPage = 0;
  int _totalPages = 1;

  // ── VIEWPORT size (full LayoutBuilder area in pixels) ─────────────────────
  double _viewportWidth = 0;
  double _viewportHeight = 0;

  // ── PDF RENDERED RECT inside the viewport ─────────────────────────────────
  // PDFView with FitPolicy.WIDTH fills the viewport width; the rendered PDF
  // height follows the page aspect ratio (gray bars top/bottom when the page is
  // shorter than the viewport). We compute this rect from the PDF's intrinsic
  // page size and the viewport dims.
  //
  // All fraction math (position, size) is relative to this rect, NOT viewport.
  Rect _pdfRect = Rect.zero; // in viewport-local pixel coordinates

  // PDF page intrinsic size in points (the size used for the CURRENT page).
  // These MUST match the real Syncfusion page.size used during stamping,
  // otherwise the on-screen overlay rect and the stamped rect have different
  // aspect ratios and the signature lands in the wrong place / wrong size.
  double _pdfPageWidth = 0; // points
  double _pdfPageHeight = 0; // points

  // Real intrinsic size (in points) of every page, read once from the PDF via
  // Syncfusion. Used so _pdfRect is computed from the TRUE page geometry
  // instead of a hardcoded A4 guess.
  List<Size>? _pdfPageSizes;

  // ── Fraction-based overlay positions (0.0–1.0 of _pdfRect) ───────────────
  // Using PDF-relative fractions means stamping at (fracX * pdfWidth) in
  // PDF point space is exactly where the user placed the overlay on screen.
  double _sigFracX = 0.25;
  double _sigFracY = 0.78;
  double _sigFracW = 0.30; // fraction of PDF width
  double _sigFracH = 0.0; // computed from aspect ratio below

  double _cmtFracX = 0.05;
  double _cmtFracY = 0.58;
  double _cmtFracW = 0.45;
  double _cmtFracH = 0.0; // computed from aspect ratio below

  // ── Drag/resize session anchors ──────────────────────────────────────────
  // A drag is tracked against the position the overlay had when the gesture
  // STARTED plus the cursor's TOTAL travel since then — not by accumulating
  // per-event deltas. Per-event deltas silently drop movement when several
  // pointer events land in the same frame (they all read the same stale
  // build-time fraction), so the overlay lags the finger and doesn't end up
  // where it's dropped. Anchoring to the start makes placement 1:1 and exact.
  double _dragBaseFracX = 0.0;
  double _dragBaseFracY = 0.0;
  double _dragBaseFracW = 0.0;
  Offset _dragStartGlobal = Offset.zero;

  // ── Computed pixel sizes from fractions × PDF rect ───────────────────────
  double get _pdfRectW => _pdfRect.width.clamp(1, double.infinity);
  double get _pdfRectH => _pdfRect.height.clamp(1, double.infinity);

  // True once we have a real, page-aspect contain-fit rect to render the
  // signing page into (i.e. the viewport has been measured AND the true PDF
  // page dimensions have been read). Until this is true, _updatePdfRect()
  // falls back to the full viewport — and in signing mode the page is locked
  // (IgnorePointer, no scroll), so a portrait page rendered into a short/wide
  // landscape viewport would have its bottom CLIPPED. We must not render the
  // locked PDF until the letterboxed contain box is ready.
  bool get _signRectReady =>
      _viewportWidth > 0 &&
      _viewportHeight > 0 &&
      _pdfPageWidth > 0 &&
      _pdfPageHeight > 0;

  // On-screen width = exact fraction of the rendered PDF rect (WYSIWYG): the
  // preview is the same size as what gets stamped. The minimum size is enforced
  // by _kMinSigFracW during resize, so no display-side inflation is needed.
  double get _sigPixelW => (_sigFracW * _pdfRectW).clamp(1, double.infinity);
  // Height ALWAYS follows the fixed capture aspect ratio — no independent clamp,
  // so the on-screen overlay is never stretched relative to what gets stamped.
  double get _sigPixelH => _sigPixelW / _kSigAspectRatio;

  double get _cmtPixelW => (_cmtFracW * _pdfRectW).clamp(1, double.infinity);
  double get _cmtPixelH => _cmtPixelW / _cmtAspectRatio;

  // Height fraction (of the PDF page) derived directly from the width fraction
  // and the fixed aspect ratio. Because _pdfRect is a uniform scale of the real
  // page, this preserves the signature's aspect ratio exactly when stamped —
  // independent of any display-side min-size clamps.
  double get _sigFracHComputed =>
      (_sigFracW * _pdfRectW) / (_kSigAspectRatio * _pdfRectH);
  double get _cmtFracHComputed =>
      (_cmtFracW * _pdfRectW) / (_cmtAspectRatio * _pdfRectH);

  // Display name shown in the comment header ("Remarks by : <Name>"), title-cased
  // from the signer's name. Kept as one source of truth so the measured capture
  // height and the rendered widget always agree.
  String get _commentDisplayName => _signerName.isNotEmpty
      ? _signerName
          .split(' ')
          .map((w) => w.isEmpty
              ? ''
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
          .join(' ')
      : 'User';

  // The comment box hugs its content instead of using a fixed aspect ratio, so a
  // short remark no longer leaves a large empty gap inside the frame. We measure
  // the header + wrapped remarks at the capture width and derive the height (and
  // therefore the aspect ratio) from that. Kept in sync with _buildCommentWidget:
  // same font sizes, padding (12), header/remarks gap (6), and 5-line cap.
  static const double _kCmtPadding = 12.0;
  static const double _kCmtHeaderGap = 6.0;
  static const int _kCmtMaxLines = 5;

  double get _cmtCaptureHeight {
    final textWidth = _kCmtCaptureWidth - _kCmtPadding * 2;
    final header = TextPainter(
      text: TextSpan(
        text: 'Remarks by : $_commentDisplayName',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      ellipsis: '…',
    )..layout(maxWidth: textWidth);
    final remarks = TextPainter(
      text: TextSpan(
        text: _remarks,
        style: const TextStyle(
          fontSize: 12.0,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
      ),
      maxLines: _kCmtMaxLines,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      ellipsis: '…',
    )..layout(maxWidth: textWidth);
    return _kCmtPadding * 2 + header.height + _kCmtHeaderGap + remarks.height;
  }

  double get _cmtAspectRatio => _kCmtCaptureWidth / _cmtCaptureHeight;

  // ── Remarks ───────────────────────────────────────────────────────────────
  String _remarks = '';
  final TextEditingController _remarksController = TextEditingController();

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _remarksController.text = _remarks;
    _loadSignatureFromApi();
    _loadUserInfo();
    _loadWatermark();
    _loadPdfPageSizes(); // read TRUE page dimensions for accurate placement

    if (widget.initialSigningMode) {
      _isSigningMode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _signedAt = DateTime.now();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  // ── PDF rect computation ──────────────────────────────────────────────────
  //
  // PDFView (FitPolicy.WIDTH) scales the page to fill the viewport width while
  // maintaining the page's aspect ratio. The rendered page rect in
  // viewport-local coordinates:
  //
  //   scaleW    = viewportW / pageW
  //   renderedW = viewportW                 <- fills the width
  //   renderedH = pageH * scaleW
  //   offsetX   = 0
  //   offsetY   = centered when shorter than viewport, else 0 (top-pinned)
  //
  // We call this whenever the viewport or page dimensions change.
  // Read the TRUE intrinsic size (in points) of every page directly from the
  // PDF using Syncfusion — the same engine used for stamping. This guarantees
  // the on-screen overlay rect (_pdfRect) and the stamped rect share the exact
  // same page geometry, so what the user places is what gets stamped.
  Future<void> _loadPdfPageSizes() async {
    try {
      final bytes = await File(widget.pdfPath).readAsBytes();
      _pdfBytes = bytes; // keep bytes so signing never depends on the temp file
      // Parsing runs on a background isolate via compute() — Syncfusion's
      // PdfDocument parse is CPU-heavy and was previously blocking the UI
      // thread right as this screen opened, which is exactly when the user
      // wants to see the PDF render.
      final rawSizes = await compute(_parsePdfPageSizes, bytes);
      final sizes = rawSizes.map((s) => Size(s[0], s[1])).toList();
      if (!mounted) return;
      setState(() {
        _pdfPageSizes = sizes;
        _applyCurrentPageSize();
        _updatePdfRect();
      });
    } catch (e) {
      debugPrint('Failed to read PDF page sizes: $e');
    }
  }

  // Point _pdfPageWidth/_pdfPageHeight at the size of the page currently shown,
  // so multi-page PDFs with mixed page sizes still place the signature exactly.
  void _applyCurrentPageSize() {
    final sizes = _pdfPageSizes;
    if (sizes == null || sizes.isEmpty) return;
    final idx = _currentPage.clamp(0, sizes.length - 1);
    _pdfPageWidth = sizes[idx].width;
    _pdfPageHeight = sizes[idx].height;
  }

  void _updatePdfRect() {
    if (_viewportWidth <= 0 ||
        _viewportHeight <= 0 ||
        _pdfPageWidth <= 0 ||
        _pdfPageHeight <= 0) {
      // Fallback: assume no letterboxing (full viewport = PDF area)
      _pdfRect = Rect.fromLTWH(0, 0, _viewportWidth, _viewportHeight);
      return;
    }

    if (_isSigningMode) {
      // SIGNING MODE — CONTAIN fit: scale the page so the WHOLE page fits
      // inside the viewport (letterboxed, centered). The PDF is rendered into
      // a box of exactly this size (see build), so there is no scrolling and
      // the overlay maps 1:1 to the stamped position — placement is exact even
      // for tall pages that would otherwise overflow a width-fit viewport.
      final scaleW = _viewportWidth / _pdfPageWidth;
      final scaleH = _viewportHeight / _pdfPageHeight;
      final scale = scaleW < scaleH ? scaleW : scaleH;
      final renderedW = _pdfPageWidth * scale;
      final renderedH = _pdfPageHeight * scale;
      final offsetX = (_viewportWidth - renderedW) / 2;
      final offsetY = (_viewportHeight - renderedH) / 2;
      _pdfRect = Rect.fromLTWH(offsetX, offsetY, renderedW, renderedH);
      return;
    }

    // VIEW MODE — Matches PDFView's FitPolicy.WIDTH: the page is scaled to fill
    // the viewport width, so the document renders as large as possible. Height
    // follows the page aspect ratio. Zooming/scrolling is allowed here, so the
    // rect is only used to seed the overlay before signing begins.
    final scaleW = _viewportWidth / _pdfPageWidth;

    final renderedW = _viewportWidth;
    final renderedH = _pdfPageHeight * scaleW;
    const offsetX = 0.0;
    // Center vertically only when the page is shorter than the viewport;
    // otherwise pin to the top (PDFView scrolls down from the top edge).
    final offsetY = renderedH < _viewportHeight
        ? (_viewportHeight - renderedH) / 2
        : 0.0;

    _pdfRect = Rect.fromLTWH(offsetX, offsetY, renderedW, renderedH);
  }

  // ── Asset loaders ─────────────────────────────────────────────────────────

  Future<void> _loadWatermark() async {
    try {
      final bd = await rootBundle.load(AppEnv.watermarkAsset);
      if (mounted) setState(() => _watermarkBytes = bd.buffer.asUint8List());
    } catch (e) {
      debugPrint('Watermark load error: $e');
    }
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString('user_data');
    if (userDataStr == null) return;
    try {
      final full = jsonDecode(userDataStr) as Map<String, dynamic>;
      Map<String, dynamic>? userData;
      if (full['user'] is Map)
        userData = full['user'] as Map<String, dynamic>;
      else if (full['data'] is Map)
        userData = full['data'] as Map<String, dynamic>;
      else
        userData = full;

      final first =
          userData['fname'] ??
          userData['first_name'] ??
          userData['firstName'] ??
          '';
      final last =
          userData['lname'] ??
          userData['last_name'] ??
          userData['lastName'] ??
          '';
      final empId =
          userData['employee_id'] ??
          userData['employeeId'] ??
          userData['emp_id'] ??
          '';
      if (mounted) {
        setState(() {
          _signerName = [first, last]
              .map((p) => p.toString().trim())
              .where((p) => p.isNotEmpty)
              .join(' ')
              .trim();
          _signerEmployeeId = empId.toString().trim();
        });
      }
    } catch (e) {
      debugPrint('Error loading user info: $e');
    }
  }

  Future<Uint8List> _removeWhiteBackground(Uint8List imageBytes) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return imageBytes;
    final pixels = byteData.buffer.asUint8List();
    for (int i = 0; i < pixels.length; i += 4) {
      if (pixels[i] > 240 && pixels[i + 1] > 240 && pixels[i + 2] > 240) {
        pixels[i + 3] = 0;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      image.width,
      image.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final processed = await completer.future;
    final processedBD = await processed.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return processedBD?.buffer.asUint8List() ?? imageBytes;
  }

  Future<void> _loadSignatureFromApi() async {
    setState(() => _isLoadingSignature = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      if (token.isEmpty) {
        await _loadSignatureLocal(prefs);
        return;
      }

      final response = await http.get(
        Uri.parse('${AppEnv.apiBaseUrl}/upload/signature/image'),
        headers: {'Authorization': 'Bearer $token', 'Accept': '*/*'},
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final ct = response.headers['content-type'] ?? '';
        if (ct.contains('image/') || ct.contains('octet-stream')) {
          final processed = await _removeWhiteBackground(response.bodyBytes);
          if (mounted) {
            setState(() {
              _signatureBytes = processed;
              _isLoadingSignature = false;
              // FIX: Do NOT recompute _sigAspectRatio from the raw image dims.
              // The composite widget (image + metadata) always has the fixed
              // capture ratio _kSigAspectRatio. Using the image's own ratio
              // caused stretching because the image only occupies ~45–48% of
              // the widget width.
            });
            _onSignatureLoadingCompleted();
          }
          return;
        }
        try {
          final decoded = jsonDecode(response.body);
          final inner = decoded['data'];
          if (inner is Map) {
            final b64 = inner['base64'] as String?;
            if (b64 != null && b64.isNotEmpty) {
              final pure = b64.contains(',') ? b64.split(',').last : b64;
              final processed = await _removeWhiteBackground(
                base64Decode(pure),
              );
              if (mounted) {
                setState(() {
                  _signatureBytes = processed;
                  _isLoadingSignature = false;
                });
                _onSignatureLoadingCompleted();
              }
              return;
            }
          }
        } catch (_) {}
      }
      await _loadSignatureLocal(prefs);
    } catch (e) {
      debugPrint('Signature fetch error: $e');
      final prefs = await SharedPreferences.getInstance();
      await _loadSignatureLocal(prefs);
    }
  }

  Future<void> _loadSignatureLocal(SharedPreferences prefs) async {
    final type = prefs.getString('signature_type') ?? '';
    if (type == 'draw' || type == 'capture') {
      final b64 = prefs.getString('signature_draw_data');
      if (b64 != null && b64.isNotEmpty) {
        if (mounted) setState(() => _signatureBytes = base64Decode(b64));
      }
    } else if (type == 'type') {
      if (mounted) {
        setState(
          () => _signatureText = prefs.getString('signature_text') ?? '',
        );
      }
    }
    if (mounted) {
      setState(() => _isLoadingSignature = false);
      _onSignatureLoadingCompleted();
    }
  }

  void _onSignatureLoadingCompleted() {
    if (!mounted) return;
    if (_pendingEnterSigningMode) {
      setState(() {
        _pendingEnterSigningMode = false;
        _showSignatureLoadingOverlay = false;
      });
      _enterSigningMode();
      return;
    }
    if (_showSignatureLoadingOverlay) {
      setState(() => _showSignatureLoadingOverlay = false);
    }
  }

  // ── Pre-configured signature placement ────────────────────────────────────
  //
  // A routing can carry a placement chosen by whoever set the document up. The
  // approver's row in `details` exposes it three ways, in priority order:
  //   1. `effective_sign` {x, y, width, height, page} — the backend's already
  //      resolved placement (it applies the template fallback server-side), so
  //      this is what we trust first.
  //   2. the row's own `sign_x/y/width/height/page`, and
  //   3. the template's `default_sign_*` values.
  // Any of these may be null — that's the common case — in which case we fall
  // back to the compact hardcoded default seeded in _enterSigningMode().
  //
  // All values are fractions of the page (0.0–1.0), the same space this screen
  // POSTs back on approve.
  //
  // The box is sized by WIDTH: the overlay height always follows the fixed
  // capture aspect ratio (_sigFracHComputed) so the preview is never stretched
  // relative to what gets stamped. A configured height is still used — when a
  // placement defines height but no width, the width is derived back out of it
  // (see _enterSigningMode) so the signature ends up the intended size.

  /// Reads `key` off `map` as a placement fraction (0.0–1.0).
  ///
  /// Values greater than 1 are assumed to be absolute PDF points and are
  /// converted using `pageExtent`, so the resolver works whether the backend
  /// stores fractions (what this app POSTs on approve) or raw points.
  double? _placementFraction(Map map, String key, double pageExtent) {
    final raw = map[key];
    if (raw == null) return null;
    final value = raw is num ? raw.toDouble() : double.tryParse(raw.toString());
    if (value == null || value <= 0) return null;
    final frac = value > 1.0 ? (pageExtent > 0 ? value / pageExtent : 0) : value;
    if (frac <= 0 || frac > 1) return null;
    return frac.toDouble();
  }

  /// This approver's row in the routing `details` list, if present.
  Map? get _ownDetailRow {
    final details = widget.item['details'];
    if (details is! List || _signerEmployeeId.isEmpty) return null;
    for (final row in details) {
      if (row is Map &&
          row['employee_id']?.toString().trim() == _signerEmployeeId) {
        return row;
      }
    }
    return null;
  }

  /// Placement to seed the overlay with, or null to use the hardcoded default.
  /// Sources are consulted in priority order and each field resolves
  /// independently, so a partially-configured placement still contributes
  /// whatever it does define.
  ({double? x, double? y, double? w, double? h, int? page})?
  _resolvePlacementPreset() {
    final row = _ownDetailRow;
    final effective = row?['effective_sign'];
    final template = widget.item['template'];
    // Each entry is (map, keyPrefix): `effective_sign` uses bare names
    // (x/y/width/page), the detail row prefixes them with `sign_`, and the
    // template with `default_sign_`.
    final sources = <(Map, String)>[
      if (effective is Map) (effective, ''),
      if (row != null) (row, 'sign_'),
      if (template is Map) (template, 'default_sign_'),
    ];
    if (sources.isEmpty) return null;

    // Page extents are only needed to convert point-based values; fall back to
    // the first page's size when the current page hasn't been measured yet.
    final sizes = _pdfPageSizes;
    final pageW = _pdfPageWidth > 0
        ? _pdfPageWidth
        : (sizes != null && sizes.isNotEmpty ? sizes.first.width : 0.0);
    final pageH = _pdfPageHeight > 0
        ? _pdfPageHeight
        : (sizes != null && sizes.isNotEmpty ? sizes.first.height : 0.0);

    double? x, y, w, h;
    int? page;
    for (final (map, prefix) in sources) {
      x ??= _placementFraction(map, '${prefix}x', pageW);
      y ??= _placementFraction(map, '${prefix}y', pageH);
      w ??= _placementFraction(map, '${prefix}width', pageW);
      h ??= _placementFraction(map, '${prefix}height', pageH);
      if (page == null) {
        final rawPage = map['${prefix}page'];
        final parsed = rawPage is num
            ? rawPage.toInt()
            : int.tryParse(rawPage?.toString() ?? '');
        // Stored page numbers are 1-BASED (the web placement UI labels this
        // signature "PAGE 1"), while _signaturePage / PDFViewController are
        // 0-based. Convert here so a configured page 1 lands on page 1.
        if (parsed != null && parsed >= 1) page = parsed - 1;
      }
    }
    if (x == null && y == null && w == null && h == null && page == null) {
      return null;
    }
    return (x: x, y: y, w: w, h: h, page: page);
  }

  void _enterSigningMode() {
    if (_isLoadingSignature) {
      setState(() {
        _showSignatureLoadingOverlay = true;
        _pendingEnterSigningMode = true;
      });
      return;
    }
    if (_signatureBytes == null &&
        (_signatureText == null || _signatureText!.isEmpty)) {
      AppSnackbar.error(
        context,
        'No signature found. Please create one in the Sign tab first.',
      );
      return;
    }
    final preset = _resolvePlacementPreset();
    // A configured sign_page pins signing to that page; otherwise signing locks
    // onto the page the reviewer is currently viewing.
    final targetPage = (preset?.page ?? _currentPage).clamp(0, _totalPages - 1);
    setState(() {
      _isSigningMode = true;
      _signedAt = DateTime.now();
      _signaturePage = targetPage;
      _currentPage = targetPage;
      // Recompute the PDF rect for CONTAIN fit now that we're signing, so the
      // overlay is seeded against the same geometry that gets stamped.
      _applyCurrentPageSize();
      _updatePdfRect();
      // Seed from the routing's configured placement when it has one, else fall
      // back to a compact default so the signature sits on a signature line
      // without overlapping existing text; the reviewer can drag/enlarge either
      // way with the corner handle.
      _sigFracX = preset?.x ?? 0.05;
      _sigFracY = preset?.y ?? 0.80;
      // Width drives the box. If the placement only defines a height, invert
      // _sigFracHComputed to get the width that yields that height at the
      // signature's fixed aspect ratio.
      final presetH = preset?.h;
      final derivedW = (presetH != null && _pdfRectW > 0)
          ? (presetH * _kSigAspectRatio * _pdfRectH) / _pdfRectW
          : null;
      _sigFracW = (preset?.w ?? derivedW ?? 0.30).clamp(_kMinSigFracW, 1.0);
      _cmtFracX = 0.05;
      _cmtFracY = 0.60;
      _cmtFracW = 0.45;
    });
    // The PDF view is re-laid-out into the contain-fit box when entering
    // signing mode; make sure it stays on the page the reviewer chose.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pdfController?.setPage(targetPage);
    });
  }

  // ── Date helpers ──────────────────────────────────────────────────────────

  DateTime? _parseApiDate(String? raw) => ManilaTime.parse(raw);

  DateTime? _resolveSigningApiTime() {
    final routing = widget.item['routing'];
    final routingMap = routing is Map ? routing : <String, dynamic>{};
    for (final raw in [
      widget.item['date_sent']?.toString(),
      routingMap['date_sent']?.toString(),
      widget.item['date_updated']?.toString(),
      routingMap['date_updated']?.toString(),
      widget.item['created_at']?.toString(),
    ]) {
      final parsed = _parseApiDate(raw);
      if (parsed != null) return parsed;
    }
    return null;
  }

  // ── Widget capture ────────────────────────────────────────────────────────

  Future<Uint8List?> _captureWidget(GlobalKey key) async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('Capture: boundary is null for key $key');
        return null;
      }
      final dpr = WidgetsBinding.instance.window.devicePixelRatio;
      final ratio = (dpr * 3).clamp(6.0, 12.0);
      final image = await boundary.toImage(pixelRatio: ratio);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      );
      canvas.drawColor(Colors.transparent, ui.BlendMode.clear);
      final paint = ui.Paint()..blendMode = ui.BlendMode.src;
      canvas.drawImage(image, ui.Offset.zero, paint);
      final pic = recorder.endRecording();
      final transparent = await pic.toImage(image.width, image.height);
      final bd = await transparent.toByteData(format: ui.ImageByteFormat.png);
      return bd?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Capture error: $e');
      return null;
    }
  }

  // ── PDF stamping — fraction → PDF point space ─────────────────────────────
  //
  // Because fractions are relative to the rendered PDF rect (not the viewport),
  // mapping to PDF point space is exact:
  //   pdfX = fracX * pdfPageWidth
  //   pdfY = fracY * pdfPageHeight
  //
  // No viewport-to-PDF ratio math is needed.

  // Stamp [bitmap] onto [page] at a rectangle given in VISUAL (rotation-applied)
  // fractions of the page — 0..1 of the page as the user sees it on screen.
  //
  // Syncfusion draws in the page's UN-rotated coordinate space and page.size is
  // the un-rotated MediaBox, while viewers apply the page's /Rotate. To make the
  // stamp appear exactly where it was placed AND upright, we translate+rotate the
  // graphics state by the page rotation before drawing, and express the target
  // rect in visual space (width/height swapped for 90°/270°). Derivation, y-down
  // top-left origin (matches Syncfusion's drawImage/translateTransform space):
  //   R=0   : identity
  //   R=90  : translate(0, ph),  rotate(-90)
  //   R=180 : translate(pw, ph), rotate(180)
  //   R=270 : translate(pw, 0),  rotate(90)
  // where pw/ph are the un-rotated page dimensions.
  void _drawImageOnPage(
    PdfPage page,
    PdfBitmap bitmap, {
    required double fracX,
    required double fracY,
    required double fracW,
    required double fracH,
  }) {
    final pw = page.size.width; // un-rotated
    final ph = page.size.height; // un-rotated
    final rot = page.rotation;
    final swap =
        rot == PdfPageRotateAngle.rotateAngle90 ||
        rot == PdfPageRotateAngle.rotateAngle270;
    final vw = swap ? ph : pw; // visual (displayed) width
    final vh = swap ? pw : ph; // visual (displayed) height

    final rect = Rect.fromLTWH(
      fracX * vw,
      fracY * vh,
      fracW * vw,
      fracH * vh,
    );

    final g = page.graphics;
    final state = g.save();
    switch (rot) {
      case PdfPageRotateAngle.rotateAngle90:
        g.translateTransform(0, ph);
        g.rotateTransform(-90);
        break;
      case PdfPageRotateAngle.rotateAngle180:
        g.translateTransform(pw, ph);
        g.rotateTransform(180);
        break;
      case PdfPageRotateAngle.rotateAngle270:
        g.translateTransform(pw, 0);
        g.rotateTransform(90);
        break;
      case PdfPageRotateAngle.rotateAngle0:
        break;
    }
    g.drawImage(bitmap, rect);
    g.restore(state);
  }

  Future<File?> _generateSignedPdf() async {
    final capturedSignature = await _captureWidget(_signatureKey);
    if (capturedSignature == null) {
      debugPrint('_generateSignedPdf: signature capture returned null');
      return null;
    }

    try {
      // Prefer the in-memory copy; the temp/cache file may have been purged by
      // Android since the page opened. Fall back to (re-)reading the file, and
      // cache it for any later attempt.
      Uint8List? pdfBytes = _pdfBytes;
      if (pdfBytes == null) {
        final file = File(widget.pdfPath);
        if (await file.exists()) {
          pdfBytes = await file.readAsBytes();
          _pdfBytes = pdfBytes;
        }
      }
      if (pdfBytes == null) {
        debugPrint(
          '_generateSignedPdf: PDF bytes unavailable (temp file purged: '
          '${widget.pdfPath})',
        );
        return null;
      }

      final document = PdfDocument(inputBytes: pdfBytes);
      final page = document.pages[_currentPage];

      // The overlay fractions are stored in VISUAL (rotation-applied) page
      // space — the same space _pdfRect uses on screen — so stamping must map
      // them back onto the un-rotated page and counter-rotate the image, or a
      // /Rotate'd page renders the signature sideways/upside-down in every
      // viewer. _drawImageOnPage handles all four rotations (0/90/180/270).
      _drawImageOnPage(
        page,
        PdfBitmap(capturedSignature),
        // FIX: use fracH computed from the fixed aspect ratio, not a stored value
        fracX: _sigFracX,
        fracY: _sigFracY,
        fracW: _sigFracW,
        fracH: _sigFracHComputed,
      );

      if (_remarks.trim().isNotEmpty) {
        final capturedComment = await _captureWidget(_commentKey);
        if (capturedComment != null) {
          _drawImageOnPage(
            page,
            PdfBitmap(capturedComment),
            fracX: _cmtFracX,
            fracY: _cmtFracY,
            fracW: _cmtFracW,
            fracH: _cmtFracHComputed,
          );
        }
      }

      final dir = await getTemporaryDirectory();
      final signedFile = File(
        '${dir.path}/signed_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await signedFile.writeAsBytes(await document.save());
      document.dispose();
      return signedFile;
    } catch (e) {
      debugPrint('PDF signing error: $e');
      return null;
    }
  }

  // ── Submission ────────────────────────────────────────────────────────────

  Future<void> _submitApproval() async {
    HapticFeedback.mediumImpact();
    setState(() => _isSubmitting = true);
    try {
      final signedPdfFile = await _generateSignedPdf();
      if (signedPdfFile == null) {
        if (mounted) {
          AppSnackbar.error(context, 'Failed to generate signed PDF.');
          setState(() => _isSubmitting = false);
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final id =
          widget.item['routing_id']?.toString() ??
          widget.item['id']?.toString() ??
          '';

      if (token.isEmpty || id.isEmpty || _signatureBytes == null) {
        if (mounted) {
          AppSnackbar.error(context, 'Missing required data. Cannot approve.');
          setState(() => _isSubmitting = false);
        }
        return;
      }

      final signaturePage = _currentPage + 1;
      final uri = Uri.parse('${AppEnv.apiBaseUrl}/approvals/$id/approve');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'application/json'
        ..fields['remarks'] = _remarks
        ..fields['signaturePlacement'] = jsonEncode({
          'sign_page': signaturePage,
          'sign_x': double.parse(_sigFracX.toStringAsFixed(4)),
          'sign_y': double.parse(_sigFracY.toStringAsFixed(4)),
          'sign_width': double.parse(_sigFracW.toStringAsFixed(4)),
          'sign_height': double.parse(_sigFracHComputed.toStringAsFixed(4)),
        });

      request.files.add(
        http.MultipartFile.fromBytes(
          'signatureImage',
          _signatureBytes!,
          filename: 'signature.png',
          contentType: MediaType('image', 'png'),
        ),
      );
      request.files.add(
        await http.MultipartFile.fromPath(
          'signedPdf',
          signedPdfFile.path,
          filename: 'signed_document.pdf',
          contentType: MediaType('application', 'pdf'),
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      debugPrint('Approve status: ${response.statusCode}');
      debugPrint('Approve body:   ${response.body}');

      if (!mounted) return;
      if (SessionExpiryService().isUnauthorized(response.statusCode)) {
        setState(() => _isSubmitting = false);
        await SessionExpiryService().handleUnauthorized();
        return;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() => _isSubmitting = false);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => const ApprovalsPage(initialTabIndex: 1),
          ),
          (route) => false,
        );
      } else {
        String message = 'Approval failed. Please try again.';
        try {
          message = jsonDecode(response.body)['message'] ?? message;
        } catch (_) {}
        setState(() => _isSubmitting = false);
        AppSnackbar.error(context, message);
      }
    } catch (e) {
      debugPrint('Submit error: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppSnackbar.error(context, 'Network error. Please try again.');
      }
    }
  }

  // ── Comment dialog ────────────────────────────────────────────────────────

  Future<void> _showInsertCommentDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.mode_comment_outlined,
                    color: Color(0xFFCC0000),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Internal Remarks',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _remarksController,
                minLines: 4,
                maxLines: 6,
                style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
                decoration: InputDecoration(
                  hintText: 'Type your optional remarks here...',
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: Colors.black38,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF6F7F9),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFD9DCE1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFD9DCE1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFCC0000)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD9DCE1)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(
                          () => _remarks = _remarksController.text.trim(),
                        );
                        Navigator.of(dialogContext).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFCC0000),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Insert Comment',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Signature content widget ──────────────────────────────────────────────

  Widget _buildSignatureContent({double? width, double? height}) {
    final w = width ?? _sigPixelW;
    final h = height ?? _sigPixelH;

    // Force Philippine time (UTC+8) so the stamp matches the view-sign page
    // regardless of the device's local timezone.
    final now = (_signedAt ?? DateTime.now()).toUtc().add(
      const Duration(hours: 8),
    );
    final hour = now.hour > 12
        ? now.hour - 12
        : (now.hour == 0 ? 12 : now.hour);
    final amPm = now.hour >= 12 ? 'PM' : 'AM';
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')} $amPm';
    final refNo =
        widget.item['referenceNo']?.toString() ??
        widget.item['routing']?['reference_no']?.toString() ??
        '';

    return SizedBox(
      width: w,
      height: h,
      child: Row(
        mainAxisSize: MainAxisSize.max, // ← was min, caused overflow
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Signature image — 36% of total width
          Flexible(
            flex: 36,
            child: SizedBox(
              height: h,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_signatureBytes != null)
                    Image.memory(
                      _signatureBytes!,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      width: double.infinity,
                      height: h,
                    )
                  else if (_signatureText != null && _signatureText!.isNotEmpty)
                    FittedBox(
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      child: Text(
                        _signatureText!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                  if (_watermarkBytes != null)
                    Opacity(
                      opacity: 0.15,
                      child: Image.memory(
                        _watermarkBytes!,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Metadata — 64% of total width
          Flexible(
            flex: 64,
            child: SizedBox(
              height: h,
              child: Container(
                padding: EdgeInsets.zero,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _metaRow('Digitally signed by:', _signerName),
                      _metaRow('Date:', dateStr),
                      _metaRow('Ref:', refNo),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return RichText(
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      text: TextSpan(
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1A1A1A),
          height: 1.4,
        ),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.normal),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentWidget({double? width, double? height}) {
    final w = width ?? _cmtPixelW;
    final h = height ?? _cmtPixelH;
    // Author the content at the capture width and the CONTENT-DERIVED height
    // (_cmtCaptureHeight) so the frame hugs the text — a short remark no longer
    // leaves a large empty gap. The display box shares that same aspect ratio
    // (_cmtAspectRatio), so BoxFit.fill maps it uniformly with no distortion and
    // no empty letterbox space, and it scales 1:1 with the drag-to-resize handle.
    return SizedBox(
      width: w,
      height: h,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: _kCmtCaptureWidth,
          height: _cmtCaptureHeight,
          child: Padding(
            padding: const EdgeInsets.all(_kCmtPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              children: [
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Remarks by : ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      TextSpan(
                        text: _commentDisplayName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: _kCmtHeaderGap),
                // The remarks fill the rest of the frame (which is sized to fit
                // them), wrapping up to _kCmtMaxLines and trailing off with an
                // ellipsis if longer — so it never overflows past the border.
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      _remarks,
                      overflow: TextOverflow.ellipsis,
                      maxLines: _kCmtMaxLines,
                      style: const TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1A1A1A),
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Draggable overlay — PDF-rect-relative fractions ───────────────────────
  //
  // All positions/sizes stored as fractions of _pdfRect (0.0–1.0).
  // Screen pixel position = pdfRect.left + fracX * pdfRect.width
  //                       = pdfRect.top  + fracY * pdfRect.height
  //
  // This is EXACTLY what gets stamped to the PDF because:
  //   stampX (pt) = fracX * pdfPageWidth (pt)
  //
  Widget _buildDraggableOverlay({
    required double fracX,
    required double fracY,
    required double fracW,
    required double fracH,
    required double pixelW,
    required double pixelH,
    required Widget child,
    required void Function(double fx, double fy) onMove,
    required void Function(double fw) onResizeW,
    Color accentColor = const Color(0xFFCC0000),
    double minFracW = 0.08,
  }) {
    // Convert PDF-rect fractions → screen pixels for Positioned widget
    final left = _pdfRect.left + fracX * _pdfRect.width;
    final top = _pdfRect.top + fracY * _pdfRect.height;
    final w = pixelW;
    final h = pixelH;

    const handleSize = 24.0;
    const pad = 12.0; // padding so the handle isn't clipped

    return Positioned(
      left: left - pad,
      top: top - pad,
      child: SizedBox(
        width: w + pad * 2,
        height: h + pad * 2,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // ── Draggable body ──────────────────────────────────────────
            Positioned(
              left: pad,
              top: pad,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) {
                  // Anchor the drag: remember where the overlay was and where
                  // the finger started. Every update is computed from these,
                  // so the overlay tracks the finger 1:1 and stays exactly
                  // where it's released — no drift from dropped per-frame deltas.
                  _dragBaseFracX = fracX;
                  _dragBaseFracY = fracY;
                  _dragStartGlobal = d.globalPosition;
                },
                onPanUpdate: (d) {
                  // Total finger travel since the drag started → fraction delta.
                  final totalDx = d.globalPosition.dx - _dragStartGlobal.dx;
                  final totalDy = d.globalPosition.dy - _dragStartGlobal.dy;

                  // Keep the overlay fully inside the current page. Signing is
                  // locked to one page (chosen in view mode), so dragging never
                  // changes pages — it only repositions within this page.
                  final newFx = (_dragBaseFracX + totalDx / _pdfRect.width)
                      .clamp(0.0, (1.0 - fracW).clamp(0.0, 1.0));
                  final newFy = (_dragBaseFracY + totalDy / _pdfRect.height)
                      .clamp(0.0, (1.0 - fracH).clamp(0.0, 1.0));
                  onMove(newFx, newFy);
                },
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: accentColor.withOpacity(0.6),
                      width: 1.5,
                    ),
                  ),
                  child: child,
                ),
              ),
            ),

            // ── Bottom-right resize handle (adjusts width only; height follows aspect ratio) ──
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) {
                  _dragBaseFracW = fracW;
                  _dragStartGlobal = d.globalPosition;
                },
                onPanUpdate: (d) {
                  // Total finger travel since the resize started → width delta.
                  final totalDx = d.globalPosition.dx - _dragStartGlobal.dx;
                  // Resizing only changes width; height follows the fixed
                  // aspect ratio (aspect = width / height of the live box).
                  // Cap the width so the box — at its aspect-derived height —
                  // never extends past the right or bottom edge of the page.
                  // This guarantees the stamped result stays fully on-page and
                  // matches the on-screen preview at ANY size.
                  final aspect = pixelW / pixelH;
                  final maxByRight = 1.0 - fracX;
                  final maxByBottom =
                      ((1.0 - fracY) * aspect * _pdfRect.height) /
                      _pdfRect.width;
                  var maxFw = maxByRight < maxByBottom
                      ? maxByRight
                      : maxByBottom;
                  if (maxFw > 0.98) maxFw = 0.98;
                  if (maxFw < minFracW) maxFw = minFracW;
                  final newFw = (_dragBaseFracW + totalDx / _pdfRect.width)
                      .clamp(minFracW, maxFw);
                  onResizeW(newFw);
                },
                child: Container(
                  width: handleSize,
                  height: handleSize,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.open_in_full,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isBlocking = _isSubmitting || _showSignatureLoadingOverlay;

    return PopScope(
      canPop: !isBlocking,
      child: Stack(
        children: [
          Scaffold(
            // Light background so the bands around the page (in signing mode)
            // and below the document read as white paper, not a black void.
            backgroundColor: const Color(0xFFEDEFF2),
            appBar: AppBar(
              backgroundColor: const Color(0xFF1A1A1A),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: isBlocking ? null : () => Navigator.pop(context),
              ),
              title: Text(
                _isSigningMode ? "PLACE SIGNATURE" : "VIEW DOCUMENT",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: Colors.white,
                ),
              ),
              actions: [
                if (_isSigningMode) ...[
                  TextButton.icon(
                    onPressed: isBlocking ? null : _showInsertCommentDialog,
                    icon: const Icon(
                      Icons.add_comment_outlined,
                      color: Colors.white,
                      size: 16,
                    ),
                    label: Text(
                      _remarks.isEmpty ? "INSERT COMMENT" : "EDIT COMMENT",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
                if (!_isSigningMode && widget.enableSigning)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: TextButton.icon(
                      onPressed: isBlocking ? null : _enterSigningMode,
                      icon: const Icon(
                        Icons.draw_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                      label: const Text(
                        "SIGN",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            body: Column(
              children: [
                // ── Instruction banner ──────────────────────────────────
                if (_isSigningMode)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFCC0000),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.drag_indicator,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Signing page ${_signaturePage + 1} · drag to move, "
                            "drag the corner to resize",
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── PDF + overlays ──────────────────────────────────────
                Expanded(
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      // Update viewport size and recompute PDF rect on every frame.
                      // Using addPostFrameCallback avoids setState-during-build.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        final changed =
                            _viewportWidth != constraints.maxWidth ||
                            _viewportHeight != constraints.maxHeight;
                        if (changed) {
                          setState(() {
                            _viewportWidth = constraints.maxWidth;
                            _viewportHeight = constraints.maxHeight;
                            _updatePdfRect();
                          });
                        }
                      });

                      final pdfView = PDFView(
                        filePath: widget.pdfPath,
                        // iOS: a plain UiKitView withholds touches until
                        // Flutter's gesture arena resolves, which starves
                        // PDFKit's native pinch-zoom recognizer — so the
                        // PDF can't be zoomed. Claiming the gesture eagerly
                        // lets PDFKit handle pinch/pan directly.
                        //
                        // Only do this in VIEW mode. In signing mode the
                        // signature overlay is positioned relative to the
                        // (un-zoomed) fit-to-width page, so the PDF must
                        // stay locked — leave gestures to Flutter there.
                        gestureRecognizers: _isSigningMode
                            ? null
                            : <Factory<OneSequenceGestureRecognizer>>{
                                Factory<OneSequenceGestureRecognizer>(
                                  () => EagerGestureRecognizer(),
                                ),
                              },
                        // Lock page navigation while signing — the
                        // reviewer already chose the page in view mode.
                        enableSwipe: !_isSigningMode,
                        swipeHorizontal: false,
                        // View mode: add spacing between pages so the
                        // page boundaries are obvious (the grey gutter
                        // shows where one page ends and the next begins,
                        // making it clear which page you'll sign on).
                        // Signing mode keeps the iOS-specific behavior
                        // (autoScales is tied to this flag on iOS) and is
                        // a single locked page anyway.
                        autoSpacing: _isSigningMode ? Platform.isIOS : true,
                        pageFling: false,
                        // Signing mode: fit the WHOLE page (both
                        // dimensions) so it's always fully visible inside
                        // its letterboxed box — never cropped. With
                        // width-only fit, a portrait page in a short/wide
                        // landscape viewport (e.g. a tablet lying flat)
                        // renders far taller than the box and the bottom
                        // gets clipped, because the locked PDF can't be
                        // scrolled (IgnorePointer). View mode keeps
                        // width-fit so the page stays large and zoomable.
                        fitPolicy: _isSigningMode
                            ? FitPolicy.BOTH
                            : FitPolicy.WIDTH,
                        // Grey gutter: in view mode it separates pages; in
                        // signing mode the page exactly fills its box so
                        // this isn't visible.
                        backgroundColor: const Color(0xFFCED2D8),
                        onViewCreated: (controller) {
                          _pdfController = controller;
                          // Switching into signing mode recreates the
                          // native view, which resets it to page 1. Snap
                          // it back to the page the reviewer chose so
                          // signing stays locked to that page.
                          if (_isSigningMode) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _pdfController?.setPage(_signaturePage);
                            });
                          }
                        },
                        onPageChanged: (page, total) {
                          if (!mounted) return;
                          final p = page ?? 0;
                          final t = total ?? _totalPages;
                          // ── Signing mode: page is LOCKED ──────────
                          // Ignore/undo any page drift (e.g. the reset
                          // that happens when the view is recreated on
                          // entering signing mode).
                          if (_isSigningMode) {
                            if (p != _signaturePage) {
                              _pdfController?.setPage(_signaturePage);
                              return;
                            }
                            setState(() {
                              _currentPage = _signaturePage;
                              _totalPages = t;
                              _applyCurrentPageSize();
                              _updatePdfRect();
                            });
                            return;
                          }
                          // ── View mode: free navigation ───────────
                          setState(() {
                            _currentPage = p;
                            _totalPages = t;
                            // Re-point page dims at the new page so the
                            // overlay rect matches what gets stamped.
                            _applyCurrentPageSize();
                            _updatePdfRect();
                          });
                        },
                        // Use the TRUE page dimensions (read via Syncfusion)
                        // so _updatePdfRect() knows the real page aspect
                        // ratio. This is what makes the placed signature
                        // land exactly where the user dropped it.
                        onRender: (pages) {
                          if (!mounted) return;
                          if (_pdfPageSizes == null) {
                            // Real sizes not read yet — kick it off.
                            _loadPdfPageSizes();
                          } else if (_pdfPageWidth <= 0) {
                            setState(() {
                              _applyCurrentPageSize();
                              _updatePdfRect();
                            });
                          }
                        },
                        onError: (e) => debugPrint('PDF error: $e'),
                      );

                      // Signing mode: fully lock the PDF — no zoom, no pan, no
                      // page change. IgnorePointer swallows every touch on the
                      // document so neither Flutter nor the native PDF view can
                      // zoom it. The draggable signature/comment overlays are
                      // separate siblings in the Stack, so they stay
                      // interactive. View mode leaves the PDF fully gesture-able.
                      final lockedPdf = _isSigningMode
                          ? IgnorePointer(child: pdfView)
                          : pdfView;

                      return Stack(
                        children: [
                          // ── PDF viewer ────────────────────────────────
                          // Signing mode: render the page inside a centered,
                          // page-aspect box (contain fit) so the WHOLE page is
                          // visible with no scrolling and the overlay maps 1:1
                          // to the stamped position. The page is locked
                          // (IgnorePointer) so it can't be scrolled — rendering
                          // it before the real contain box is known would let a
                          // portrait page overflow a short/wide landscape
                          // viewport and clip its bottom. So while the box isn't
                          // ready yet, show a loader instead of the raw page.
                          // View mode: fill the viewport so it stays zoomable.
                          if (_isSigningMode)
                            _signRectReady
                                ? Positioned(
                                    left: _pdfRect.left,
                                    top: _pdfRect.top,
                                    width: _pdfRect.width,
                                    height: _pdfRect.height,
                                    child: lockedPdf,
                                  )
                                : const Positioned.fill(
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFFCC0000),
                                      ),
                                    ),
                                  )
                          else
                            Positioned.fill(child: lockedPdf),

                          // ── Page counter ──────────────────────────────
                          if (_totalPages > 1)
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.55),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  "${_currentPage + 1} / $_totalPages",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),

                          // ── Draggable overlays (PDF-rect-relative) ────
                          // Gate on _signRectReady (not just _pdfRect != zero)
                          // so the overlays only appear once the page is laid
                          // out in its real contain box — never floating over
                          // the loader or a clipped fallback render.
                          if (_isSigningMode &&
                              _currentPage == _signaturePage &&
                              _signRectReady) ...[
                            // Comment overlay
                            if (_remarks.trim().isNotEmpty)
                              _buildDraggableOverlay(
                                fracX: _cmtFracX,
                                fracY: _cmtFracY,
                                fracW: _cmtFracW,
                                fracH: _cmtFracHComputed,
                                pixelW: _cmtPixelW,
                                pixelH: _cmtPixelH,
                                accentColor: const Color(0xFFFFC107),
                                minFracW: _kMinCmtFracW,
                                child: _buildCommentWidget(
                                  width: _cmtPixelW,
                                  height: _cmtPixelH,
                                ),
                                onMove: (fx, fy) => setState(() {
                                  _cmtFracX = fx;
                                  _cmtFracY = fy;
                                }),
                                onResizeW: (fw) =>
                                    setState(() => _cmtFracW = fw),
                              ),

                            // Signature overlay
                            _buildDraggableOverlay(
                              fracX: _sigFracX,
                              fracY: _sigFracY,
                              fracW: _sigFracW,
                              fracH: _sigFracHComputed,
                              pixelW: _sigPixelW,
                              pixelH: _sigPixelH,
                              accentColor: const Color(0xFFCC0000),
                              minFracW: _kMinSigFracW,
                              child: _buildSignatureContent(
                                width: _sigPixelW,
                                height: _sigPixelH,
                              ),
                              onMove: (fx, fy) => setState(() {
                                _sigFracX = fx;
                                _sigFracY = fy;
                              }),
                              onResizeW: (fw) => setState(() => _sigFracW = fw),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),

                // ── Action bar ────────────────────────────────────────────
                // Compact, side-by-side buttons inside a SafeArea so the bar
                // always clears the device's bottom gesture/navigation inset
                // (this is what was clipping CONFIRM & APPROVE) and leaves more
                // height for the document above.
                if (_isSigningMode)
                  Material(
                    color: Colors.white,
                    elevation: 8,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: OutlinedButton(
                                  onPressed: isBlocking
                                      ? null
                                      : () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: Color(0xFFCC0000),
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  child: const Text(
                                    "CANCEL",
                                    style: TextStyle(
                                      color: Color(0xFFCC0000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _isSubmitting
                                      ? null
                                      : _submitApproval,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF059669),
                                    disabledBackgroundColor: Colors.green
                                        .withOpacity(0.6),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          "CONFIRM & APPROVE",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Off-screen RepaintBoundary (fixed size = true capture size) ──
          // The fixed dimensions MUST match _kCaptureWidth / _kCaptureHeight.
          // This guarantees the stamped image has the correct aspect ratio.
          Positioned(
            left: -10000,
            top: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  key: _signatureKey,
                  child: Container(
                    width: _kCaptureWidth,
                    height: _kCaptureHeight,
                    color: Colors.transparent,
                    child: _buildSignatureContent(
                      width: _kCaptureWidth,
                      height: _kCaptureHeight,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_remarks.trim().isNotEmpty)
                  RepaintBoundary(
                    key: _commentKey,
                    child: SizedBox(
                      width: _kCmtCaptureWidth,
                      height: _cmtCaptureHeight,
                      child: _buildCommentWidget(
                        width: _kCmtCaptureWidth,
                        height: _cmtCaptureHeight,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Blocking overlay ──────────────────────────────────────────
          if (isBlocking) const LoadingOverlay(),
        ],
      ),
    );
  }
}
