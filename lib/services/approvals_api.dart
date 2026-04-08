import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// APPROVAL DETAIL PAGE
// ─────────────────────────────────────────────────────────────────────────────

class ApprovalDetailPage extends StatefulWidget {
  final Map<String, dynamic> item;

  const ApprovalDetailPage({super.key, required this.item});

  @override
  State<ApprovalDetailPage> createState() => _ApprovalDetailPageState();
}

class _ApprovalDetailPageState extends State<ApprovalDetailPage> {
  bool _isLoadingPdf = false;
  bool _isLoadingDetail = true;
  String? _localPdfPath;

  // Detail data from API
  Map<String, dynamic>? _detail;

  static const String _baseUrl = 'https://eforward-api.ardentnetworks.com.ph/api';

  @override
  void initState() {
    super.initState();
    _loadPdf();
    _fetchApprovalDetail();
  }

  // ─── GET /approvals/:id/routing ──────────────────────────────────────────
  Future<void> _fetchApprovalDetail() async {
    setState(() => _isLoadingDetail = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final id = widget.item['id'] ?? widget.item['referenceNo'] ?? '';

      if (token.isEmpty || id.isEmpty) {
        debugPrint('No token or id — using dummy data');
        if (mounted) setState(() { _isLoadingDetail = false; });
        return;
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/approvals/$id/routing'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      debugPrint('Approval detail status: ${response.statusCode}');
      debugPrint('Approval detail body: ${response.body.length > 300 ? response.body.substring(0, 300) : response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _detail = decoded is Map<String, dynamic> ? decoded : null;
            _isLoadingDetail = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingDetail = false);
      }
    } catch (e) {
      debugPrint('Approval detail error: $e');
      if (mounted) setState(() => _isLoadingDetail = false);
    }
  }

  Future<void> _loadPdf() async {
    setState(() => _isLoadingPdf = true);
    try {
      final byteData = await rootBundle.load('assets/documents/sample.pdf');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/sample.pdf');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      if (mounted) {
        setState(() {
          _localPdfPath = file.path;
          _isLoadingPdf = false;
        });
      }
    } catch (e) {
      debugPrint('PDF load error: $e');
      if (mounted) setState(() => _isLoadingPdf = false);
    }
  }

  // Helper — get value from API detail or fallback to widget.item
  String _getValue(String apiKey, String fallbackKey) {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final val = data[apiKey];
      if (val != null && val.toString().isNotEmpty) return val.toString();
    }
    return widget.item[fallbackKey]?.toString() ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _getValue('file_name', 'fileName').endsWith('.pdf')
        ? _getValue('file_name', 'fileName')
        : '${_getValue('title', 'particulars')}.pdf';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back,
              color: Color(0xFF1A1A1A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "APPROVAL DETAILS",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: Color(0xFF1A1A1A),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: const [
                Icon(Icons.shield_outlined,
                    color: Color(0xFFCC0000), size: 16),
                SizedBox(width: 4),
                Text(
                  "E-FORWARD",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: Color(0xFFCC0000),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Status badge + Reference No
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCC0000).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    "PENDING",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Color(0xFFCC0000),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _getValue('reference_no', 'referenceNo'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFCC0000),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Title
            Text(
              _getValue('particulars', 'particulars'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: Color(0xFF1A1A1A),
                height: 1.2,
              ),
            ),

            const SizedBox(height: 20),

            // Info Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "DOCUMENT INFORMATION",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoadingDetail)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(color: Color(0xFFCC0000)),
                      ),
                    )
                  else ...[
                    _buildInfoRow(Icons.person_outline, "REQUESTER",
                        _getValue('requester', 'requester')),
                    const Divider(height: 24, color: Color(0xFFF0F0F0)),
                    _buildInfoRow(Icons.calendar_today_outlined, "DATE SENT",
                        _getValue('date_sent', 'dateSent')),
                    const Divider(height: 24, color: Color(0xFFF0F0F0)),
                    _buildInfoRow(Icons.label_outline, "PARTICULARS",
                        _getValue('particulars', 'particulars')),
                    const Divider(height: 24, color: Color(0xFFF0F0F0)),
                    _buildInfoRow(Icons.tag, "REFERENCE NO",
                        _getValue('reference_no', 'referenceNo')),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ─── ATTACHED DOCUMENT ───────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "ATTACHED DOCUMENT",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // File row
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCC0000).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.picture_as_pdf_outlined,
                          color: Color(0xFFCC0000),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fileName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A1A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              "PDF Document",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black38,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // VIEW FILE button
                      _isLoadingPdf
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFCC0000)),
                            )
                          : GestureDetector(
                              onTap: _localPdfPath != null
                                  ? () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PdfSignerPage(
                                            pdfPath: _localPdfPath!,
                                            item: widget.item,
                                          ),
                                        ),
                                      )
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _localPdfPath != null
                                      ? const Color(0xFFCC0000)
                                      : Colors.black12,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  children: const [
                                    Icon(Icons.visibility_outlined,
                                        color: Colors.white, size: 14),
                                    SizedBox(width: 6),
                                    Text(
                                      "VIEW FILE",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Legal notice
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  left: BorderSide(color: Color(0xFFCC0000), width: 3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.info_outline,
                      color: Color(0xFFCC0000), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "By signing this document, you confirm that you have reviewed all contents and authorize the action. This signature is legally binding.",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.black38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: Colors.black38,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PDF SIGNER PAGE — Full screen PDF + draggable signature + approve
// ─────────────────────────────────────────────────────────────────────────────

class PdfSignerPage extends StatefulWidget {
  final String pdfPath;
  final Map<String, dynamic> item;

  const PdfSignerPage({
    super.key,
    required this.pdfPath,
    required this.item,
  });

  @override
  State<PdfSignerPage> createState() => _PdfSignerPageState();
}

class _PdfSignerPageState extends State<PdfSignerPage> {
  bool _isSigningMode = false;
  bool _isSubmitting = false;
  bool _isLoadingSignature = true;

  // Signature data
  Uint8List? _signatureBytes;
  String? _signatureText;

  // Draggable position
  Offset _signaturePosition = const Offset(80, 200);
  double _signatureWidth = 200;
  double _signatureHeight = 100;

  final TextEditingController _remarksController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSignatureFromApi();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  // 👇 Fetch signature from API — { data: { base64: "data:image/png;base64,..." } }
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
        Uri.parse('https://eforward-api.ardentnetworks.com.ph/api/upload/signature/image'),
        headers: {'Authorization': 'Bearer $token', 'Accept': '*/*'},
      );

      debugPrint('Signature API status: ${response.statusCode}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final contentType = response.headers['content-type'] ?? '';

        // Case 1: Direct image blob
        if (contentType.contains('image/') || contentType.contains('octet-stream')) {
          if (mounted) setState(() { _signatureBytes = response.bodyBytes; _isLoadingSignature = false; });
          return;
        }

        // Case 2: JSON → { data: { base64: "data:image/png;base64,..." } }
        try {
          final decoded = jsonDecode(response.body);
          final inner = decoded['data'];
          if (inner is Map) {
            final base64Str = inner['base64'] as String?;
            if (base64Str != null && base64Str.isNotEmpty) {
              final pure = base64Str.contains(',') ? base64Str.split(',').last : base64Str;
              if (mounted) {
                setState(() { _signatureBytes = base64Decode(pure); _isLoadingSignature = false; });
              }
              debugPrint('Signature loaded from API base64');
              return;
            }
          }
        } catch (e) { debugPrint('JSON parse error: $e'); }
      }

      await _loadSignatureLocal(prefs);
    } catch (e) {
      debugPrint('Signature fetch error: $e');
      final prefs = await SharedPreferences.getInstance();
      await _loadSignatureLocal(prefs);
    }
  }

  // Fallback — local SharedPreferences
  Future<void> _loadSignatureLocal(SharedPreferences prefs) async {
    final type = prefs.getString('signature_type') ?? '';
    if (type == 'draw' || type == 'capture') {
      final base64Str = prefs.getString('signature_draw_data');
      if (base64Str != null && base64Str.isNotEmpty) {
        if (mounted) setState(() => _signatureBytes = base64Decode(base64Str));
      }
    } else if (type == 'type') {
      if (mounted) setState(() => _signatureText = prefs.getString('signature_text') ?? '');
    }
    if (mounted) setState(() => _isLoadingSignature = false);
  }

  void _enterSigningMode() {
    if (_signatureBytes == null &&
        (_signatureText == null || _signatureText!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No signature found. Please create one in the Sign tab first.'),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }
    setState(() => _isSigningMode = true);
  }

  Future<void> _submitApproval() async {
    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final id = widget.item['id'] ?? widget.item['referenceNo'] ?? '';

      if (token.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. Please login again.'),
            backgroundColor: Color(0xFFCC0000),
          ),
        );
        setState(() => _isSubmitting = false);
        return;
      }

      // ─── POST /approvals/:id/approve ─────────────────────────────────────
      // FormData: remarks, signatureImage, signaturePlacement
      final uri = Uri.parse(
          'https://eforward-api.ardentnetworks.com.ph/api/approvals/$id/approve');

      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'application/json'
        ..fields['remarks'] = ''
        ..fields['signaturePlacement'] =
            '${_signaturePosition.dx.toStringAsFixed(0)},${_signaturePosition.dy.toStringAsFixed(0)}';

      // Attach signature image bytes if available
      if (_signatureBytes != null && _signatureBytes!.isNotEmpty) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'signatureImage',
            _signatureBytes!,
            filename: 'signature.png',
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('Approve status: ${response.statusCode}');
      debugPrint('Approve body: ${response.body}');

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document approved and routed to next approver!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
        Navigator.pop(context);
      } else {
        final decoded = jsonDecode(response.body);
        final message = decoded['message'] ?? 'Approval failed. Please try again.';
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: const Color(0xFFCC0000),
          ),
        );
      }
    } catch (e) {
      debugPrint('Submit error: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Network error. Please try again.'),
            backgroundColor: Color(0xFFCC0000),
          ),
        );
      }
    }
  }

  String _getSignedDate() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final months = ['JAN','FEB','MAR','APR','MAY','JUN',
                    'JUL','AUG','SEP','OCT','NOV','DEC'];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  Widget _buildSignatureWidget() {
    if (_isLoadingSignature) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFCC0000)),
      );
    }

    return SizedBox(
      width: _signatureWidth,
      height: _signatureHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Signature area with watermark behind
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 👇 Logo watermark at the BACK
                Opacity(
                  opacity: 0.08,
                  child: Image.asset(
                    'assets/images/eforward_watermark.png',
                    width: 70,
                    height: 70,
                    fit: BoxFit.contain,
                  ),
                ),
                // Signature on top
                _signatureBytes != null
                    ? Image.memory(
                        _signatureBytes!,
                        width: _signatureWidth,
                        height: _signatureHeight - 20,
                        fit: BoxFit.contain,
                      )
                    : _signatureText != null && _signatureText!.isNotEmpty
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _signatureText!,
                              style: const TextStyle(
                                fontSize: 20,
                                fontStyle: FontStyle.italic,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
              ],
            ),
          ),
          // Divider
          Container(height: 0.5, color: Colors.black26),
          // Signed date
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 8, color: Colors.black38),
                const SizedBox(width: 3),
                Text(
                  'Signed: ${_getSignedDate()}',
                  style: const TextStyle(
                    fontSize: 7,
                    color: Colors.black45,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          onPressed: () {
            if (_isSigningMode) {
              setState(() => _isSigningMode = false);
            } else {
              Navigator.pop(context);
            }
          },
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
          if (!_isSigningMode)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _enterSigningMode,
                icon: const Icon(Icons.draw_outlined,
                    color: Colors.white, size: 16),
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

          // Instruction banner (signing mode only)
          if (_isSigningMode)
            Container(
              width: double.infinity,
              color: const Color(0xFFCC0000),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: const [
                  Icon(Icons.drag_indicator,
                      size: 16, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Drag your signature to position it on the document, then tap CONFIRM & APPROVE.",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // PDF + signature overlay
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [

                    // PDF viewer
                    Positioned.fill(
                      child: PDFView(
                        filePath: widget.pdfPath,
                        enableSwipe: !_isSigningMode,
                        swipeHorizontal: false,
                        autoSpacing: true,
                        pageFling: false,
                        backgroundColor: Colors.grey.shade200,
                        onError: (e) => debugPrint('PDF error: $e'),
                      ),
                    ),

                    // Draggable + resizable signature (signing mode only)
                    if (_isSigningMode)
                      Positioned(
                        left: _signaturePosition.dx,
                        top: _signaturePosition.dy,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Main signature box — drag to move
                            GestureDetector(
                              onPanUpdate: (details) {
                                setState(() {
                                  double newX = _signaturePosition.dx + details.delta.dx;
                                  double newY = _signaturePosition.dy + details.delta.dy;
                                  newX = newX.clamp(0, constraints.maxWidth - _signatureWidth);
                                  newY = newY.clamp(0, constraints.maxHeight - _signatureHeight);
                                  _signaturePosition = Offset(newX, newY);
                                });
                              },
                              child: Container(
                                width: _signatureWidth,
                                height: _signatureHeight,
                                decoration: BoxDecoration(
                                  border: Border.all(color: const Color(0xFFCC0000), width: 1.5),
                                  color: Colors.white.withOpacity(0.9),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 6,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  children: [
                                    Center(child: _buildSignatureWidget()),
                                    // Move icon — top left
                                    const Positioned(
                                      top: 2,
                                      left: 4,
                                      child: Icon(Icons.open_with, size: 12, color: Color(0xFFCC0000)),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // ─── RESIZE HANDLE — bottom right corner ───
                            Positioned(
                              right: -12,
                              bottom: -12,
                              child: GestureDetector(
                                onPanUpdate: (details) {
                                  setState(() {
                                    double newW = (_signatureWidth + details.delta.dx)
                                        .clamp(100.0, constraints.maxWidth - _signaturePosition.dx);
                                    double newH = (_signatureHeight + details.delta.dy)
                                        .clamp(60.0, constraints.maxHeight - _signaturePosition.dy);
                                    _signatureWidth = newW;
                                    _signatureHeight = newH;
                                  });
                                },
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFCC0000),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.open_in_full, size: 13, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          // Remarks + confirm button (signing mode only)
          if (_isSigningMode)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitApproval,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        disabledBackgroundColor:
                            Colors.green.withOpacity(0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.check_circle_outline,
                                    color: Colors.white, size: 18),
                                SizedBox(width: 10),
                                Text(
                                  "CONFIRM & APPROVE",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}