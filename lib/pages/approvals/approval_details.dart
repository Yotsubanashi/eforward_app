import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

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
  bool _isSubmittingRevision = false;
  String? _localPdfPath;

  Map<String, dynamic>? _detail;

  final TextEditingController _revisionRemarksController =
      TextEditingController();

  static const String _baseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';

  @override
  void initState() {
    super.initState();
    _loadPdf();
    _fetchApprovalDetail();
  }

  @override
  void dispose() {
    _revisionRemarksController.dispose();
    super.dispose();
  }

  // ─── GET /approvals/:id/routing ──────────────────────────────────────────
  Future<void> _fetchApprovalDetail() async {
    setState(() => _isLoadingDetail = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final id = widget.item['id'] ?? widget.item['referenceNo'] ?? '';

      if (token.isEmpty || id.isEmpty) {
        if (mounted) setState(() => _isLoadingDetail = false);
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

  // ─── POST /approvals/:id/revision ────────────────────────────────────────
  Future<void> _submitRequestRevision(BuildContext dialogContext) async {
    final remarks = _revisionRemarksController.text.trim();

    if (remarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter remarks.'),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }

    setState(() => _isSubmittingRevision = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final id = widget.item['id'] ?? widget.item['referenceNo'] ?? '';

      if (token.isEmpty || id.isEmpty) throw Exception('Missing token or ID');

      final response = await http.post(
        Uri.parse('$_baseUrl/approvals/$id/revision'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'remarks': remarks}),
      );

      debugPrint('Revision status: ${response.statusCode}');
      debugPrint('Revision body: ${response.body}');

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        Navigator.pop(dialogContext); // close dialog
        setState(() => _isSubmittingRevision = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Revision request sent successfully.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context); // go back to list
      } else {
        String message = 'Failed to send revision request.';
        try {
          message = jsonDecode(response.body)['message'] ?? message;
        } catch (_) {}
        setState(() => _isSubmittingRevision = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: const Color(0xFFCC0000),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSubmittingRevision = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: const Color(0xFFCC0000),
        ),
      );
    }
  }

  void _showRequestRevisionDialog() {
    _revisionRemarksController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "REQUEST REVISION",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 20),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                    ),
                    children: [
                      TextSpan(text: "Remarks "),
                      TextSpan(
                        text: "*",
                        style: TextStyle(
                          color: Color(0xFFCC0000),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _revisionRemarksController,
                  minLines: 4,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: "Enter your revision request remarks...",
                    hintStyle: const TextStyle(
                      fontSize: 12,
                      color: Colors.black38,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(
                        color: Color(0xFFCC0000),
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.black38),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          "CANCEL",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmittingRevision
                            ? null
                            : () => _submitRequestRevision(dialogContext),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFCC0000),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: _isSubmittingRevision
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                "SUBMIT",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
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
      ),
    );
  }

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
          icon: const Icon(
            Icons.arrow_back,
            color: Color(0xFF1A1A1A),
            size: 20,
          ),
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
                Icon(Icons.shield_outlined, color: Color(0xFFCC0000), size: 16),
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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

            // Document Info Card
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
                        child: CircularProgressIndicator(
                          color: Color(0xFFCC0000),
                        ),
                      ),
                    )
                  else ...[
                    _buildInfoRow(
                      Icons.person_outline,
                      "REQUESTER",
                      _getValue('requester', 'requester'),
                    ),
                    const Divider(height: 24, color: Color(0xFFF0F0F0)),
                    _buildInfoRow(
                      Icons.calendar_today_outlined,
                      "DATE SENT",
                      _getValue('date_sent', 'dateSent'),
                    ),
                    const Divider(height: 24, color: Color(0xFFF0F0F0)),
                    _buildInfoRow(
                      Icons.label_outline,
                      "PARTICULARS",
                      _getValue('particulars', 'particulars'),
                    ),
                    const Divider(height: 24, color: Color(0xFFF0F0F0)),
                    _buildInfoRow(
                      Icons.tag,
                      "REFERENCE NO",
                      _getValue('reference_no', 'referenceNo'),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Attached Document Card
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
                      _isLoadingPdf
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFCC0000),
                              ),
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
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _localPdfPath != null
                                      ? const Color(0xFFCC0000)
                                      : Colors.black12,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  children: const [
                                    Icon(
                                      Icons.visibility_outlined,
                                      color: Colors.white,
                                      size: 14,
                                    ),
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

                  const SizedBox(height: 12),

                  // ✅ REQUEST REVISION button — connected to POST /approvals/:id/revision
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showRequestRevisionDialog,
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: Colors.black,
                        size: 16,
                      ),
                      label: const Text(
                        "REQUEST REVISION",
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        elevation: 0,
                        side: const BorderSide(
                          color: Color(0xFFE0E0E0),
                          width: 1,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
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
                  Icon(Icons.info_outline, color: Color(0xFFCC0000), size: 16),
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
// PDF SIGNER PAGE
// ─────────────────────────────────────────────────────────────────────────────

class PdfSignerPage extends StatefulWidget {
  final String pdfPath;
  final Map<String, dynamic> item;

  const PdfSignerPage({super.key, required this.pdfPath, required this.item});

  @override
  State<PdfSignerPage> createState() => _PdfSignerPageState();
}

class _PdfSignerPageState extends State<PdfSignerPage> {
  bool _isSigningMode = false;
  bool _isSubmitting = false;
  bool _isLoadingSignature = true;

  Uint8List? _signatureBytes;
  String? _signatureText;

  Offset _signaturePosition = const Offset(80, 200);
  double _signatureWidth = 200;
  double _signatureHeight = 100;

  double _containerWidth = 0;
  double _containerHeight = 0;

  int _currentPage = 0;
  int _totalPages = 1;

  static const String _baseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';

  @override
  void initState() {
    super.initState();
    _loadSignatureFromApi();
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
        Uri.parse('$_baseUrl/upload/signature/image'),
        headers: {'Authorization': 'Bearer $token', 'Accept': '*/*'},
      );

      debugPrint('Signature API status: ${response.statusCode}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final contentType = response.headers['content-type'] ?? '';

        if (contentType.contains('image/') ||
            contentType.contains('octet-stream')) {
          if (mounted)
            setState(() {
              _signatureBytes = response.bodyBytes;
              _isLoadingSignature = false;
            });
          return;
        }

        try {
          final decoded = jsonDecode(response.body);
          final inner = decoded['data'];
          if (inner is Map) {
            final base64Str = inner['base64'] as String?;
            if (base64Str != null && base64Str.isNotEmpty) {
              final pure = base64Str.contains(',')
                  ? base64Str.split(',').last
                  : base64Str;
              if (mounted)
                setState(() {
                  _signatureBytes = base64Decode(pure);
                  _isLoadingSignature = false;
                });
              return;
            }
          }
        } catch (e) {
          debugPrint('JSON parse error: $e');
        }
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
      final base64Str = prefs.getString('signature_draw_data');
      if (base64Str != null && base64Str.isNotEmpty)
        if (mounted) setState(() => _signatureBytes = base64Decode(base64Str));
    } else if (type == 'type') {
      if (mounted)
        setState(
          () => _signatureText = prefs.getString('signature_text') ?? '',
        );
    }
    if (mounted) setState(() => _isLoadingSignature = false);
  }

  void _enterSigningMode() {
    if (_isLoadingSignature) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signature still loading. Please wait.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_signatureBytes == null &&
        (_signatureText == null || _signatureText!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No signature found. Please create one in the Sign tab first.',
          ),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }
    setState(() {
      _isSigningMode = true;
      _signaturePosition = Offset(
        _containerWidth > 0 ? (_containerWidth - _signatureWidth) / 2 : 80,
        _containerHeight > 0 ? _containerHeight * 0.7 : 200,
      );
    });
  }

  // ─── POST /approvals/:id/approve ─────────────────────────────────────────
  Future<void> _submitApproval() async {
    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final id = widget.item['id'] ?? widget.item['referenceNo'] ?? '';

      if (token.isEmpty) {
        _showError('Session expired. Please login again.');
        setState(() => _isSubmitting = false);
        return;
      }

      if (_signatureBytes == null) {
        _showError('No signature found. Please set up your signature first.');
        setState(() => _isSubmitting = false);
        return;
      }

      final signaturePage = _currentPage + 1;

      final effectiveContainerWidth = _containerWidth > 0
          ? _containerWidth
          : 595.0;
      final effectiveContainerHeight = _containerHeight > 0
          ? _containerHeight
          : 842.0;

      final scaleX = 595.0 / effectiveContainerWidth;
      final scaleY = 842.0 / effectiveContainerHeight;
      final pdfX = (_signaturePosition.dx * scaleX).toStringAsFixed(2);
      final pdfY = (_signaturePosition.dy * scaleY).toStringAsFixed(2);
      final pdfW = (_signatureWidth * scaleX).toStringAsFixed(2);
      final pdfH = (_signatureHeight * scaleY).toStringAsFixed(2);

      debugPrint(
        '📤 Approve: page=$signaturePage x=$pdfX y=$pdfY w=$pdfW h=$pdfH',
      );

      final uri = Uri.parse('$_baseUrl/approvals/$id/approve');

      // ✅ multipart/form-data — signature image + coordinates
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'application/json'
        ..fields['remarks'] = ''
        ..fields['page'] = signaturePage.toString()
        ..fields['x'] = pdfX
        ..fields['y'] = pdfY
        ..fields['width'] = pdfW
        ..fields['height'] = pdfH
        ..fields['signaturePlacement'] = jsonEncode({
          'x': pdfX,
          'y': pdfY,
          'width': pdfW,
          'height': pdfH,
          'page': signaturePage,
        });

      // ✅ Signature image — server embeds into PDF at given coordinates
      request.files.add(
        http.MultipartFile.fromBytes(
          'signatureImage',
          _signatureBytes!,
          filename: 'signature.png',
          contentType: MediaType('image', 'png'),
        ),
      );

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
        String message = 'Approval failed. Please try again.';
        try {
          message = jsonDecode(response.body)['message'] ?? message;
        } catch (_) {}
        setState(() => _isSubmitting = false);
        _showError(message);
      }
    } catch (e) {
      debugPrint('Submit error: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showError('Network error. Please try again.');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFCC0000),
      ),
    );
  }

  String _getSignedDate() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  Widget _buildSignatureWidget() {
    if (_isLoadingSignature) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFFCC0000),
        ),
      );
    }

    return SizedBox(
      width: _signatureWidth,
      height: _signatureHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: 0.08,
                  child: Image.asset(
                    'assets/images/eforward_watermark.png',
                    width: 70,
                    height: 70,
                    fit: BoxFit.contain,
                  ),
                ),
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
          Container(height: 0.5, color: Colors.black26),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 8,
                  color: Colors.black38,
                ),
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
            if (_isSigningMode)
              setState(() => _isSigningMode = false);
            else
              Navigator.pop(context);
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
          if (_isSigningMode)
            Container(
              width: double.infinity,
              color: const Color(0xFFCC0000),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: const [
                  Icon(Icons.drag_indicator, size: 16, color: Colors.white),
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

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_containerWidth != constraints.maxWidth ||
                      _containerHeight != constraints.maxHeight) {
                    setState(() {
                      _containerWidth = constraints.maxWidth;
                      _containerHeight = constraints.maxHeight;
                    });
                  }
                });

                return Stack(
                  children: [
                    Positioned.fill(
                      child: PDFView(
                        filePath: widget.pdfPath,
                        enableSwipe: !_isSigningMode,
                        swipeHorizontal: false,
                        autoSpacing: true,
                        pageFling: false,
                        backgroundColor: Colors.grey.shade200,
                        onPageChanged: (page, total) {
                          if (mounted)
                            setState(() {
                              _currentPage = page ?? 0;
                              _totalPages = total ?? 1;
                            });
                        },
                        onError: (e) => debugPrint('PDF error: $e'),
                      ),
                    ),

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

                    if (_isSigningMode)
                      Positioned(
                        left: _signaturePosition.dx,
                        top: _signaturePosition.dy,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GestureDetector(
                              onPanUpdate: (details) {
                                setState(() {
                                  _signaturePosition = Offset(
                                    (_signaturePosition.dx + details.delta.dx)
                                        .clamp(
                                          0,
                                          constraints.maxWidth -
                                              _signatureWidth,
                                        ),
                                    (_signaturePosition.dy + details.delta.dy)
                                        .clamp(
                                          0,
                                          constraints.maxHeight -
                                              _signatureHeight,
                                        ),
                                  );
                                });
                              },
                              child: Container(
                                width: _signatureWidth,
                                height: _signatureHeight,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFCC0000),
                                    width: 1.5,
                                  ),
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
                                    const Positioned(
                                      top: 2,
                                      left: 4,
                                      child: Icon(
                                        Icons.open_with,
                                        size: 12,
                                        color: Color(0xFFCC0000),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            Positioned(
                              right: -12,
                              bottom: -12,
                              child: GestureDetector(
                                onPanUpdate: (details) {
                                  setState(() {
                                    _signatureWidth =
                                        (_signatureWidth + details.delta.dx)
                                            .clamp(
                                              100.0,
                                              constraints.maxWidth -
                                                  _signaturePosition.dx,
                                            );
                                    _signatureHeight =
                                        (_signatureHeight + details.delta.dy)
                                            .clamp(
                                              60.0,
                                              constraints.maxHeight -
                                                  _signaturePosition.dy,
                                            );
                                  });
                                },
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFCC0000),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.open_in_full,
                                    size: 13,
                                    color: Colors.white,
                                  ),
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

          if (_isSigningMode)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isSubmitting)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        "Submitting approval...",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black45,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitApproval,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        disabledBackgroundColor: Colors.green.withOpacity(0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.white,
                                  size: 18,
                                ),
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
