import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:eforward_app/pages/approvals/approvals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _isSubmittingRevision = false;

  Map<String, dynamic>? _detail;
  final TextEditingController _revisionRemarksController =
      TextEditingController();

  static const String _baseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';

  @override
  void initState() {
    super.initState();
    setState(() => _isLoadingPdf = true);
    _fetchApprovalDetail();
  }

  @override
  void dispose() {
    _revisionRemarksController.dispose();
    super.dispose();
  }

  void _showRequestRevisionDialog() {
    _revisionRemarksController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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
                          borderSide: const BorderSide(
                            color: Color(0xFFE8E8E8),
                            width: 1,
                          ),
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
                            onPressed: () => Navigator.pop(context),
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
                                letterSpacing: 1,
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
                                : () => _submitRequestRevision(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFCC0000),
                              disabledBackgroundColor: const Color(
                                0xFFCC0000,
                              ).withOpacity(0.6),
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
                                      letterSpacing: 1,
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
            );
          },
        );
      },
    );
  }

  Future<void> _submitRequestRevision(BuildContext dialogContext) async {
    final remarks = _revisionRemarksController.text.trim();
    if (remarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter remarks'),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }
    setState(() => _isSubmittingRevision = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final id =
          widget.item['routing_id']?.toString() ??
          widget.item['id']?.toString() ??
          '';
      if (token.isEmpty || id.isEmpty)
        throw Exception('Missing token or approval ID');

      final response = await http.post(
        Uri.parse('$_baseUrl/approvals/$id/request-revision'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'remarks': remarks}),
      );

      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        Navigator.pop(dialogContext);
        setState(() => _isSubmittingRevision = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Revision request sent successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
      } else {
        String message = 'Failed to submit revision request';
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

  Future<void> _fetchApprovalDetail() async {
    setState(() => _isLoadingDetail = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final id =
          widget.item['routing_id']?.toString() ??
          widget.item['id']?.toString() ??
          '';
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
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _detail = decoded is Map<String, dynamic> ? decoded : null;
            _isLoadingDetail = false;
          });
          await _loadPdfFromApi(decoded);
        }
      } else {
        if (mounted) {
          setState(() => _isLoadingDetail = false);
          await _loadPdfLocal();
        }
      }
    } catch (e) {
      debugPrint('Approval detail error: $e');
      if (mounted) {
        setState(() => _isLoadingDetail = false);
        await _loadPdfLocal();
      }
    }
  }

  Future<void> _loadPdfFromApi(dynamic detailData) async {
    setState(() => _isLoadingPdf = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final fileId = _extractFileId(detailData);
      if (fileId == null || fileId.isEmpty) {
        await _loadPdfLocal();
        return;
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/upload/document/$fileId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Cache-Control': 'no-cache',
        },
      );
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.bodyBytes.isNotEmpty) {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/doc_${fileId}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        );
        await file.writeAsBytes(response.bodyBytes);
        if (mounted)
          setState(() {
            _localPdfPath = file.path;
            _isLoadingPdf = false;
          });
      } else {
        await _loadPdfLocal();
      }
    } catch (e) {
      debugPrint('Document fetch error: $e');
      await _loadPdfLocal();
    }
  }

  String? _extractFileId(dynamic data) {
    if (data == null) return null;
    final inner = data is Map ? (data['data'] ?? data) : null;
    if (inner is Map) {
      final files = inner['files'];
      if (files is List && files.isNotEmpty) {
        final first = files.first;
        if (first is Map) {
          final id = first['file_id'] ?? first['fileId'] ?? first['id'];
          if (id != null) return id.toString();
        }
      }
    }
    if (data is Map) {
      for (final key in ['file_id', 'fileId', 'document_id', 'documentId']) {
        final val = data[key];
        if (val != null &&
            val.toString().isNotEmpty &&
            val.toString() != 'null')
          return val.toString();
      }
      for (final val in data.values) {
        final found = _extractFileId(val);
        if (found != null) return found;
      }
    }
    if (data is List) {
      for (final item in data) {
        final found = _extractFileId(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  Future<void> _loadPdfLocal() async {
    try {
      final byteData = await rootBundle.load('assets/documents/sample.pdf');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/sample.pdf');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      if (mounted)
        setState(() {
          _localPdfPath = file.path;
          _isLoadingPdf = false;
        });
    } catch (e) {
      if (mounted) setState(() => _isLoadingPdf = false);
    }
  }

  String _getValue(String apiKey, String fallbackKey) {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final val = data[apiKey];
      if (val != null && val.toString().isNotEmpty && val.toString() != 'null')
        return val.toString();
    }
    return widget.item[fallbackKey]?.toString() ?? '—';
  }

  String _getRequesterName() {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final owner = data['owner'];
      if (owner is Map) {
        final name = [owner['fname'], owner['mname'], owner['lname']]
            .map((p) => p?.toString().trim() ?? '')
            .where((p) => p.isNotEmpty)
            .join(' ')
            .trim();
        if (name.isNotEmpty) return name;
      }
    }
    return widget.item['requester']?.toString() ?? '—';
  }

  String _formatDate(String raw) {
    if (raw.isEmpty || raw == '—') return raw;
    try {
      final dt = DateTime.parse(raw).toLocal();
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
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} | ${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
    } catch (_) {
      return raw;
    }
  }

  String _getFileName() {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final files = data['files'];
      if (files is List && files.isNotEmpty) {
        final first = files.first;
        if (first is Map) {
          final name =
              first['original_name'] ??
              first['originalName'] ??
              first['file_name'] ??
              first['fileName'];
          if (name != null && name.toString().isNotEmpty)
            return name.toString();
        }
      }
    }
    return widget.item['original_name']?.toString() ??
        '${widget.item['particulars'] ?? 'Document'}.pdf';
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _getFileName();
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
                      _getRequesterName(),
                    ),
                    const Divider(height: 24, color: Color(0xFFF0F0F0)),
                    _buildInfoRow(
                      Icons.calendar_today_outlined,
                      "DATE SENT",
                      _formatDate(_getValue('date_sent', 'dateSent')),
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
                                  mainAxisSize: MainAxisSize.min,
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

  final GlobalKey _signatureKey = GlobalKey();

  Uint8List? _signatureBytes;
  String? _signatureText;

  String _signerName = '';
  String _signerEmployeeId = '';

  Offset _signaturePosition = const Offset(60, 300);
  double _signatureWidth = 280;
  double _signatureHeight = 80;

  double _containerWidth = 0;
  double _containerHeight = 0;

  // Track current page for submission
  int _currentPage = 0; // 0-indexed
  int _totalPages = 1;

  static const double _pdfPageWidthPt = 595.0;
  static const double _pdfPageHeightPt = 842.0;

  double _toPdfX(double screenX) => _containerWidth == 0
      ? screenX
      : (screenX / _containerWidth) * _pdfPageWidthPt;
  double _toPdfY(double screenY) => _containerHeight == 0
      ? screenY
      : _pdfPageHeightPt - ((screenY / _containerHeight) * _pdfPageHeightPt);
  double _toPdfWidth(double screenW) => _containerWidth == 0
      ? screenW
      : (screenW / _containerWidth) * _pdfPageWidthPt;
  double _toPdfHeight(double screenH) => _containerHeight == 0
      ? screenH
      : (screenH / _containerHeight) * _pdfPageHeightPt;

  @override
  void initState() {
    super.initState();
    _loadSignatureFromApi();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString('user_data');
    if (userDataStr != null) {
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
        if (mounted)
          setState(() {
            _signerName = [first, last]
                .map((p) => p.toString().trim())
                .where((p) => p.isNotEmpty)
                .join(' ')
                .trim();
            _signerEmployeeId = empId.toString().trim();
          });
      } catch (e) {
        debugPrint('Error loading user info: $e');
      }
    }
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
        Uri.parse(
          'https://eforward-api.ardentnetworks.com.ph/api/upload/signature/image',
        ),
        headers: {'Authorization': 'Bearer $token', 'Accept': '*/*'},
      );

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
      if (base64Str != null && base64Str.isNotEmpty) {
        if (mounted) setState(() => _signatureBytes = base64Decode(base64Str));
      }
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
      // Place signature at bottom-center of current view
      _signaturePosition = Offset(
        _containerWidth > 0 ? (_containerWidth - _signatureWidth) / 2 : 60,
        _containerHeight > 0 ? _containerHeight * 0.7 : 300,
      );
    });
  }

  Future<void> _submitApproval() async {
    setState(() => _isSubmitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final id =
          widget.item['routing_id']?.toString() ??
          widget.item['id']?.toString() ??
          '';

      if (token.isEmpty || id.isEmpty || _signatureBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Missing required data. Cannot approve.'),
            backgroundColor: Color(0xFFCC0000),
          ),
        );
        setState(() => _isSubmitting = false);
        return;
      }

      final pdfX = _toPdfX(_signaturePosition.dx);
      final pdfY = _toPdfY(_signaturePosition.dy);
      final pdfW = _toPdfWidth(_signatureWidth);
      final pdfH = _toPdfHeight(_signatureHeight);
      final signaturePage = _currentPage + 1; // convert to 1-indexed

      debugPrint(
        'Approving — page: $signaturePage, x:$pdfX y:$pdfY w:$pdfW h:$pdfH',
      );

      final uri = Uri.parse(
        'https://eforward-api.ardentnetworks.com.ph/api/approvals/$id/approve',
      );
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'application/json'
        ..fields['remarks'] = ''
        ..fields['page'] = signaturePage.toString()
        ..fields['x'] = pdfX.toStringAsFixed(2)
        ..fields['y'] = pdfY.toStringAsFixed(2)
        ..fields['width'] = pdfW.toStringAsFixed(2)
        ..fields['height'] = pdfH.toStringAsFixed(2)
        ..fields['signaturePlacement'] = jsonEncode({
          'x': pdfX.toStringAsFixed(2),
          'y': pdfY.toStringAsFixed(2),
          'width': pdfW.toStringAsFixed(2),
          'height': pdfH.toStringAsFixed(2),
          'page': signaturePage,
        });

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
      debugPrint('Approve response: ${response.body}');

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: const Color(0xFFCC0000),
          ),
        );
      }
    } catch (e) {
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

  Widget _buildSignatureWidget() {
    if (_isLoadingSignature)
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFFCC0000),
        ),
      );

    final now = DateTime.now().toLocal();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final refNo =
        widget.item['referenceNo']?.toString() ??
        widget.item['routing']?['reference_no']?.toString() ??
        '';

    return Container(
      width: _signatureWidth,
      height: _signatureHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCC0000), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: 0.10,
                  child: Image.asset(
                    'assets/images/eforward_watermark.png',
                    fit: BoxFit.contain,
                  ),
                ),
                if (_signatureBytes != null)
                  Image.memory(_signatureBytes!, fit: BoxFit.contain)
                else if (_signatureText != null && _signatureText!.isNotEmpty)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _signatureText!,
                      style: const TextStyle(
                        fontSize: 18,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(width: 0.5, color: const Color(0xFFCC0000)),
          Expanded(
            flex: 6,
            child: Container(
              color: const Color(0xFFFAFAFA),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _metaRow('Digitally signed by:', _signerName),
                  _metaRow('Employee ID:', _signerEmployeeId),
                  _metaRow('Date:', dateStr),
                  _metaRow('Ref:', refNo),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 6.5,
            color: Color(0xFF1A1A1A),
            height: 1.3,
          ),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
        overflow: TextOverflow.ellipsis,
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
          // Instruction banner (signing mode only)
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
                      "Scroll to the page you want, then drag your signature to position it.",
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

          // PDF + draggable signature
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
                    // ── PDF viewer — swipe always enabled ──
                    Positioned.fill(
                      child: PDFView(
                        filePath: widget.pdfPath,
                        enableSwipe: true, // ✅ always can swipe pages
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

                    // ── Page indicator (top right, subtle) ──
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

                    // ── Draggable + resizable signature ──
                    if (_isSigningMode)
                      Positioned(
                        left: _signaturePosition.dx,
                        top: _signaturePosition.dy,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Main box — drag to move
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
                                    RepaintBoundary(
                                      key: _signatureKey,
                                      child: Center(
                                        child: _buildSignatureWidget(),
                                      ),
                                    ),
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

                            // Resize handle — bottom right
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

          // Bottom buttons (signing mode only)
          if (_isSigningMode)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
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
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Color(0xFFCC0000),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.close, color: Color(0xFFCC0000), size: 18),
                          SizedBox(width: 8),
                          Text(
                            "CANCEL",
                            style: TextStyle(
                              color: Color(0xFFCC0000),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
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
