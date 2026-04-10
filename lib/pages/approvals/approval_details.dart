import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
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

  // Detail data from API
  Map<String, dynamic>? _detail;

  static const String _baseUrl = 'https://eforward-api.ardentnetworks.com.ph/api';

  @override
  void initState() {
    super.initState();
    setState(() => _isLoadingPdf = true); // show loader immediately
    _fetchApprovalDetail();               // PDF loads inside this after detail
  }

  // ─── GET /approvals/:id/routing ──────────────────────────────────────────
  Future<void> _fetchApprovalDetail() async {
    setState(() => _isLoadingDetail = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final id = widget.item['routing_id']?.toString() ?? widget.item['id']?.toString() ?? '';

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

          // 👇 After getting detail, fetch the document file
          await _loadPdfFromApi(decoded);
        }
      } else {
        if (mounted) {
          setState(() => _isLoadingDetail = false);
          await _loadPdfLocal(); // fallback
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

  // ─── Fetch document from API using file_id ────────────────────────────────
  Future<void> _loadPdfFromApi(dynamic detailData) async {
    setState(() => _isLoadingPdf = true);

    debugPrint('=== FULL DETAIL RESPONSE ===');
    _printNested(detailData, 0);
    debugPrint('============================');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';

      String? fileId = _extractFileId(detailData);
      debugPrint('Extracted file_id: $fileId');

      if (fileId == null || fileId.isEmpty) {
        debugPrint('No file_id found — using local PDF fallback');
        await _loadPdfLocal();
        return;
      }

      final uri = Uri.parse('$_baseUrl/upload/document/$fileId');
      debugPrint('Fetching fresh document: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Cache-Control': 'no-cache',  // 👈 force fresh fetch
          'Pragma': 'no-cache',
        },
      );

      debugPrint('Document status: ${response.statusCode}');
      debugPrint('Document bytes: ${response.bodyBytes.length}');

      if (response.statusCode >= 200 && response.statusCode < 300 &&
          response.bodyBytes.isNotEmpty) {
        final dir = await getTemporaryDirectory();

        // 👇 Use timestamp to always create a new file — never use cached version
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${dir.path}/doc_${fileId}_$timestamp.pdf');

        // Delete any old cached versions of this document
        try {
          final oldFiles = dir.listSync()
              .whereType<File>()
              .where((f) => f.path.contains('doc_${fileId}_'));
          for (final old in oldFiles) {
            if (old.path != file.path) await old.delete();
          }
        } catch (_) {}

        await file.writeAsBytes(response.bodyBytes);
        if (mounted) {
          setState(() {
            _localPdfPath = file.path;
            _isLoadingPdf = false;
          });
          debugPrint('✅ Fresh document loaded: ${file.path}');
        }
      } else {
        await _loadPdfLocal();
      }
    } catch (e) {
      debugPrint('Document fetch error: $e');
      await _loadPdfLocal();
    }
  }

  // ─── Recursively print all nested keys ────────────────────────────────────
  void _printNested(dynamic data, int depth) {
    final indent = '  ' * depth;
    if (data is Map) {
      data.forEach((key, value) {
        debugPrint('$indent$key: ${value is Map || value is List ? '' : value}');
        if (value is Map || value is List) _printNested(value, depth + 1);
      });
    } else if (data is List) {
      for (int i = 0; i < data.length; i++) {
        debugPrint('${indent}[$i]:');
        _printNested(data[i], depth + 1);
      }
    }
  }

  // ─── Extract file_id from data.files[0].file_id ──────────────────────────
  String? _extractFileId(dynamic data) {
    if (data == null) return null;

    // data.files[0].file_id  ← exact structure from API
    final inner = data is Map ? (data['data'] ?? data) : null;
    if (inner is Map) {
      final files = inner['files'];
      if (files is List && files.isNotEmpty) {
        final first = files.first;
        if (first is Map) {
          final id = first['file_id'] ?? first['fileId'] ?? first['id'];
          if (id != null) {
            debugPrint('file_id from files[0]: $id');
            return id.toString();
          }
        }
      }
    }

    // Fallback — recursive search
    if (data is Map) {
      for (final key in ['file_id', 'fileId', 'document_id', 'documentId']) {
        final val = data[key];
        if (val != null && val.toString().isNotEmpty && val.toString() != 'null') {
          return val.toString();
        }
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

  // ─── Fallback: load from local assets ────────────────────────────────────
  Future<void> _loadPdfLocal() async {
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
      debugPrint('Local PDF load error: $e');
      if (mounted) setState(() => _isLoadingPdf = false);
    }
  }

  Future<void> _loadPdf() async {
    // This is now called only if detail fetch hasn't started yet
    // Actual PDF loading happens in _loadPdfFromApi after detail is fetched
  }

  // Helper — get value from API detail or fallback to widget.item
  // data structure: { data: { routing_id, reference_no, particulars, files[], ... } }
  String _getValue(String apiKey, String fallbackKey) {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final val = data[apiKey];
      if (val != null && val.toString().isNotEmpty && val.toString() != 'null')
        return val.toString();
    }
    return widget.item[fallbackKey]?.toString() ?? '—';
  }

  // Format ISO date to readable
  // Get requester from data.owner.fname + mname + lname
  String _getRequesterName() {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final owner = data['owner'];
      if (owner is Map) {
        final first = owner['fname']?.toString().trim() ?? '';
        final middle = owner['mname']?.toString().trim() ?? '';
        final last = owner['lname']?.toString().trim() ?? '';
        final name = [first, middle, last]
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
      final months = ['JAN','FEB','MAR','APR','MAY','JUN',
                      'JUL','AUG','SEP','OCT','NOV','DEC'];
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} | '
          '${hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')} $ampm';
    } catch (_) {
      return raw;
    }
  }

  // Get filename — data.files[0].original_name
  String _getFileName() {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final files = data['files'];
      if (files is List && files.isNotEmpty) {
        final first = files.first;
        if (first is Map) {
          final name = first['original_name'] ?? first['originalName']
              ?? first['file_name'] ?? first['fileName'];
          if (name != null && name.toString().isNotEmpty) {
            return name.toString();
          }
        }
      }
    }
    return widget.item['original_name']?.toString()
        ?? '${widget.item['particulars'] ?? 'Document'}.pdf';
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
                        _getRequesterName()),
                    const Divider(height: 24, color: Color(0xFFF0F0F0)),
                    _buildInfoRow(Icons.calendar_today_outlined, "DATE SENT",
                        _formatDate(_getValue('date_sent', 'dateSent'))),
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

  // GlobalKey to capture signature widget as image
  final GlobalKey _signatureKey = GlobalKey();

  // Signature data
  Uint8List? _signatureBytes;
  String? _signatureText;

  // User info for signature metadata
  String _signerName = '';
  String _signerEmployeeId = '';

  // Draggable position (screen pixels)
  Offset _signaturePosition = const Offset(80, 200);
  double _signatureWidth = 280;   // wider to fit signature + metadata
  double _signatureHeight = 80;

  // PDF container dimensions (to convert screen px → PDF points)
  double _containerWidth = 0;
  double _containerHeight = 0;

  // Standard PDF page size in points (Letter: 612x792, A4: 595x842)
  static const double _pdfPageWidthPt = 595.0;
  static const double _pdfPageHeightPt = 842.0;

  // Convert screen position to PDF points
  double _toPdfX(double screenX) {
    if (_containerWidth == 0) return screenX;
    return (screenX / _containerWidth) * _pdfPageWidthPt;
  }

  double _toPdfY(double screenY) {
    if (_containerHeight == 0) return screenY;
    // PDF Y is from bottom, screen Y is from top — flip it
    return _pdfPageHeightPt - ((screenY / _containerHeight) * _pdfPageHeightPt);
  }

  double _toPdfWidth(double screenW) {
    if (_containerWidth == 0) return screenW;
    return (screenW / _containerWidth) * _pdfPageWidthPt;
  }

  double _toPdfHeight(double screenH) {
    if (_containerHeight == 0) return screenH;
    return (screenH / _containerHeight) * _pdfPageHeightPt;
  }

  final TextEditingController _remarksController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSignatureFromApi();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Debug: Check all keys in SharedPreferences
    debugPrint('=== SharedPreferences Debug ===');
    debugPrint('All keys: ${prefs.getKeys()}');
    
    // Try different possible keys for user data
    final possibleKeys = ['user_data', 'userData', 'user', 'profile', 'user_profile'];
    String? userDataStr;
    String? foundKey;
    
    for (final key in possibleKeys) {
      final val = prefs.getString(key);
      debugPrint('$key: ${val != null ? "found (${val.length} chars)" : "not found"}');
      if (val != null) {
        userDataStr = val;
        foundKey = key;
        break;
      }
    }
    
    debugPrint('Using key: $foundKey');
    debugPrint('================================');
    
    if (userDataStr != null) {
      try {
        final full = jsonDecode(userDataStr) as Map<String, dynamic>;
        debugPrint('Full decoded data: $full');
        
        // Try to find user data in different possible locations
        Map<String, dynamic>? userData;
        if (full['data'] is Map) {
          userData = full['data'] as Map<String, dynamic>;
          debugPrint('Found at full[data]');
        } else if (full['user'] is Map) {
          userData = full['user'] as Map<String, dynamic>;
          debugPrint('Found at full[user]');
        } else {
          userData = full;
          debugPrint('Using full object as userData');
        }
        
        debugPrint('userData keys: ${userData.keys}');
        
        // Try different possible keys for names
        final first = userData['fname'] ?? userData['first_name'] ?? userData['firstName'] ?? userData['first'] ?? '';
        final middle = userData['mname'] ?? userData['middle_name'] ?? userData['middleName'] ?? userData['middle'] ?? '';
        final last = userData['lname'] ?? userData['last_name'] ?? userData['lastName'] ?? userData['last'] ?? '';
        
        // Try different keys for employee ID
        final empId = userData['employee_id'] ?? userData['employeeId'] ?? userData['emp_id'] ?? userData['empId'] ?? userData['id'] ?? '';
        
        debugPrint('Extracted - first: $first, middle: $middle, last: $last, empId: $empId');
        
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
        
        debugPrint('Final - Name: $_signerName, EmpID: $_signerEmployeeId');
      } catch (e) {
        debugPrint('Error loading user info: $e');
      }
    } else {
      debugPrint('No user data found in SharedPreferences');
    }
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
    debugPrint('Entering signing mode — signatureBytes: ${_signatureBytes?.length ?? 0} bytes, signatureText: $_signatureText, isLoading: $_isLoadingSignature');

    if (_isLoadingSignature) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signature still loading. Please wait a moment.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_signatureBytes == null && (_signatureText == null || _signatureText!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No signature found. Please create one in the Sign tab first.'),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }
    setState(() => _isSigningMode = true);
  }

  // Capture the rendered signature widget (with logo + date) as PNG bytes
  Future<Uint8List?> _captureSignatureImage() async {
    try {
      final boundary = _signatureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('RepaintBoundary not found — using raw bytes');
        return _signatureBytes;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final bytes = byteData.buffer.asUint8List();
        debugPrint('Captured signature widget: ${bytes.length} bytes');
        return bytes;
      }
    } catch (e) {
      debugPrint('Capture error: $e — using raw bytes');
    }
    return _signatureBytes; // fallback
  }

  Future<void> _submitApproval() async {
    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final id = widget.item['routing_id']?.toString() ?? widget.item['id']?.toString() ?? '';

      debugPrint('=== SUBMIT APPROVAL ===');
      debugPrint('routing_id (id): $id');
      debugPrint('token: ${token.isNotEmpty ? "present" : "MISSING"}');
      debugPrint('signatureBytes: ${_signatureBytes?.length ?? 0} bytes');
      debugPrint('position: ${_signaturePosition.dx}, ${_signaturePosition.dy}');
      debugPrint('size: ${_signatureWidth} x ${_signatureHeight}');
      debugPrint('======================');

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

      if (id.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document ID not found. Cannot approve.'),
            backgroundColor: Color(0xFFCC0000),
          ),
        );
        setState(() => _isSubmitting = false);
        return;
      }

      // ─── POST /approvals/:id/approve ──────────────────────────────────
      final uri = Uri.parse(
          'https://eforward-api.ardentnetworks.com.ph/api/approvals/$id/approve');

      debugPrint('Approving: POST $uri');

      // Use raw API signature bytes — server handles metadata embedding
      final sigBytes = _signatureBytes;

      if (sigBytes == null || sigBytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signature not loaded yet. Please wait and try again.'),
            backgroundColor: Color(0xFFCC0000),
          ),
        );
        setState(() => _isSubmitting = false);
        return;
      }

      debugPrint('Signature bytes to send: ${sigBytes.length}');

      // PDF placement coordinates
      final pdfX = _toPdfX(_signaturePosition.dx);
      final pdfY = _toPdfY(_signaturePosition.dy);
      final pdfW = _toPdfWidth(_signatureWidth);
      final pdfH = _toPdfHeight(_signatureHeight);

      debugPrint('PDF coords: x=${pdfX.toStringAsFixed(2)}pt y=${pdfY.toStringAsFixed(2)}pt w=${pdfW.toStringAsFixed(2)}pt h=${pdfH.toStringAsFixed(2)}pt');

      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'application/json'
        ..fields['remarks'] = ''
        // Try all possible placement field formats the API might accept
        ..fields['page'] = '1'
        ..fields['x'] = pdfX.toStringAsFixed(2)
        ..fields['y'] = pdfY.toStringAsFixed(2)
        ..fields['width'] = pdfW.toStringAsFixed(2)
        ..fields['height'] = pdfH.toStringAsFixed(2)
        ..fields['signaturePlacement'] = jsonEncode({
          'x': pdfX.toStringAsFixed(2),
          'y': pdfY.toStringAsFixed(2),
          'width': pdfW.toStringAsFixed(2),
          'height': pdfH.toStringAsFixed(2),
          'page': 1,
        });

      // Attach as 'signatureImage' (primary field name)
      request.files.add(
        http.MultipartFile.fromBytes(
          'signatureImage',
          sigBytes,
          filename: 'signature.png',
          contentType: MediaType('image', 'png'),
        ),
      );

      debugPrint('Request fields: ${request.fields}');
      debugPrint('Request files: ${request.files.map((f) => "${f.field}:${f.length}bytes").toList()}');

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
          final decoded = jsonDecode(response.body);
          message = decoded['message'] ?? message;
        } catch (_) {
          message = response.body.isNotEmpty ? response.body : message;
        }
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

    final now = DateTime.now().toLocal();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')} '
        '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}';
    final refNo = widget.item['referenceNo']?.toString()
        ?? widget.item['routing']?['reference_no']?.toString()
        ?? '';

    return Container(
      width: _signatureWidth,
      height: _signatureHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCC0000), width: 1),
      ),
      child: Row(
        children: [
          // LEFT — signature image with watermark logo behind
          Expanded(
            flex: 5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Watermark logo behind
                Opacity(
                  opacity: 0.10,
                  child: Image.asset(
                    'assets/images/eforward_watermark.png',
                    fit: BoxFit.contain,
                  ),
                ),
                // Signature on top
                if (_signatureBytes != null)
                  Image.memory(
                    _signatureBytes!,
                    fit: BoxFit.contain,
                  )
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

          // Divider
          Container(width: 0.5, color: const Color(0xFFCC0000)),

          // RIGHT — metadata box
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
                  _metaRow('Employee ID:',  _signerEmployeeId),
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
          style: const TextStyle(fontSize: 6.5, color: Color(0xFF1A1A1A), height: 1.3),
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
                // Save container size for coordinate conversion
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
                                    RepaintBoundary(
                                      key: _signatureKey,
                                      child: Center(child: _buildSignatureWidget()),
                                    ),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Approve button
                  SizedBox(
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
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.check_circle_outline,
                                    color: Colors.white, size: 18),
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
                  // Cancel button
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
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close,
                              color: Color(0xFFCC0000), size: 18),
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