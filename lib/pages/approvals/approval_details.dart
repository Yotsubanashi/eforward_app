import 'dart:async';
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
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:excel/excel.dart' hide TextSpan, Border;
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:eforward_app/services/approvals_api.dart';

// ─────────────────────────────────────────────────────────────────────────────
// APPROVAL DETAIL PAGE
// ─────────────────────────────────────────────────────────────────────────────

class ApprovalDetailPage extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool isFromHistory;

  const ApprovalDetailPage({
    super.key,
    required this.item,
    this.isFromHistory = false,
  });

  @override
  State<ApprovalDetailPage> createState() => _ApprovalDetailPageState();
}

class _ApprovalDetailPageState extends State<ApprovalDetailPage> {
  bool _isLoadingPdf = false;
  bool _isLoadingDetail = true;
  bool _isLoadingDocumentLinks = false;
  String? _localPdfPath;
  String? _localExcelPath;
  bool _isSubmittingRevision = false;
  int _selectedAttachmentTab = 0;

  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _documentLinks = [];
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
      if (token.isEmpty || id.isEmpty) {
        throw Exception('Missing token or approval ID');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/approvals/$id/revision'),
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
        final data = decoded['data'];
        debugPrint('ALL KEYS: ${data.keys.toList()}');
        debugPrint('FILES: ${data['files']}');
        debugPrint('EXTRACTED FILE ID: ${_extractFileId(decoded)}');
        if (mounted) {
          setState(() {
            _detail = decoded is Map<String, dynamic> ? decoded : null;
            _isLoadingDetail = false;
          });
          await _loadPdfFromApi(decoded);
          await _fetchDocumentLinks();
        }
      } else {
        if (mounted) {
          setState(() => _isLoadingDetail = false);
          await _loadPdfLocal();
          await _fetchDocumentLinks();
        }
      }
    } catch (e) {
      debugPrint('Approval detail error: $e');
      if (mounted) {
        setState(() => _isLoadingDetail = false);
        await _loadPdfLocal();
        await _fetchDocumentLinks();
      }
    }
  }

  String _getRoutingId() {
    return widget.item['routing_id']?.toString() ??
        widget.item['id']?.toString() ??
        '';
  }

  Future<void> _fetchDocumentLinks() async {
    final routingId = _getRoutingId();
    if (routingId.isEmpty) return;

    setState(() => _isLoadingDocumentLinks = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';

      if (token.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoadingDocumentLinks = false;
            _documentLinks = [];
          });
        }
        return;
      }

      final links = await ApprovalsApi().getDocumentLinks(
        token: token,
        routingId: routingId,
      );

      if (!mounted) return;
      setState(() {
        _documentLinks = links;
        _isLoadingDocumentLinks = false;
      });
    } catch (e) {
      debugPrint('Document links fetch error: $e');
      if (!mounted) return;
      setState(() {
        _documentLinks = [];
        _isLoadingDocumentLinks = false;
      });
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
        final fileName = _getFileName();
        final fileExtension = _getFileExtension(fileName);
        final preservedFileName =
            'doc_${fileId}_${DateTime.now().millisecondsSinceEpoch}${fileExtension.isNotEmpty ? '.$fileExtension' : '.pdf'}';
        final file = File('${dir.path}/$preservedFileName');
        await file.writeAsBytes(response.bodyBytes);
        if (mounted) {
          setState(() {
            _localPdfPath = file.path;
            _isLoadingPdf = false;
          });
        }
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
        final signedFile = files.firstWhere(
          (f) => f is Map && f['file_type']?.toString() == 'SIGNED',
          orElse: () => null,
        );
        if (signedFile != null && signedFile is Map) {
          final id =
              signedFile['file_id'] ?? signedFile['fileId'] ?? signedFile['id'];
          if (id != null) return id.toString();
        }
        final headFile = files.firstWhere(
          (f) => f is Map && f['file_type']?.toString() == 'HEAD',
          orElse: () => null,
        );
        if (headFile != null && headFile is Map) {
          final id =
              headFile['file_id'] ?? headFile['fileId'] ?? headFile['id'];
          if (id != null) return id.toString();
        }
        final docFile = files.firstWhere(
          (f) => f is Map && f['file_type']?.toString() == 'DOC',
          orElse: () => null,
        );
        if (docFile != null && docFile is Map) {
          final id = docFile['file_id'] ?? docFile['fileId'] ?? docFile['id'];
          if (id != null) return id.toString();
        }
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
            val.toString() != 'null') {
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

  List<Map<String, dynamic>> _getAttachmentFiles() {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final files = data['files'];
      if (files is List) {
        return files
            .whereType<Map<String, dynamic>>()
            .where((f) => f['file_type']?.toString() == 'DOC')
            .toList();
      }
    }
    return [];
  }

  List<Map<String, dynamic>> _getDocumentLinkFiles(Map<String, dynamic> link) {
    final files = link['files'];
    if (files is List) {
      return files.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  Map<String, dynamic>? _getHeadFile() {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final files = data['files'];
      if (files is List) {
        return files.firstWhere(
              (f) => f is Map && f['file_type']?.toString() == 'HEAD',
              orElse: () => null,
            )
            as Map<String, dynamic>?;
      }
    }
    return null;
  }

  Map<dynamic, dynamic>? _getDownloadableFile() {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final files = data['files'];
      if (files is List && files.isNotEmpty) {
        final signedFile = files.firstWhere(
          (f) => f is Map && f['file_type']?.toString() == 'SIGNED',
          orElse: () => null,
        );
        if (signedFile != null && signedFile is Map) return signedFile;

        final headFile = files.firstWhere(
          (f) => f is Map && f['file_type']?.toString() == 'HEAD',
          orElse: () => null,
        );
        if (headFile != null && headFile is Map) return headFile;

        final docFile = files.firstWhere(
          (f) => f is Map && f['file_type']?.toString() == 'DOC',
          orElse: () => null,
        );
        if (docFile != null && docFile is Map) return docFile;
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
      if (mounted) {
        setState(() {
          _localPdfPath = file.path;
          _isLoadingPdf = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPdf = false);
    }
  }

  Future<Directory?> _getDownloadsDirectory() async {
    try {
      if (Platform.isAndroid) {
        final androidDownloads = Directory('/storage/emulated/0/Download');
        if (await androidDownloads.exists()) {
          return androidDownloads;
        }
        return await getExternalStorageDirectory();
      } else if (Platform.isIOS) {
        return await getApplicationDocumentsDirectory();
      }
      return await getTemporaryDirectory();
    } catch (e) {
      debugPrint('Get downloads directory error: $e');
      return await getTemporaryDirectory();
    }
  }

  Future<bool> _requestStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        return status.isGranted;
      }
      return true;
    } catch (e) {
      debugPrint('Permission request error: $e');
      return false;
    }
  }

  Future<void> _downloadFile(String fileId, String fileName) async {
    try {
      final hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission denied. Cannot save file.'),
              backgroundColor: Color(0xFFCC0000),
            ),
          );
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';

      if (token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session expired. Please login again.'),
              backgroundColor: Color(0xFFCC0000),
            ),
          );
        }
        return;
      }

      if (fileId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to download: File ID not found'),
              backgroundColor: Color(0xFFCC0000),
            ),
          );
        }
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
        final dir = await _getDownloadsDirectory();
        if (dir == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to determine save location'),
                backgroundColor: Color(0xFFCC0000),
              ),
            );
          }
          return;
        }

        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File downloaded to Downloads folder: $fileName'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );

          await Future.delayed(const Duration(milliseconds: 500));
          await OpenFile.open(file.path);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Download failed: ${response.statusCode}'),
              backgroundColor: const Color(0xFFCC0000),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading file: $e'),
            backgroundColor: const Color(0xFFCC0000),
          ),
        );
      }
    }
  }

  String _getFileExtension(String fileName) {
    if (fileName.contains('.')) {
      return fileName.split('.').last.toLowerCase();
    }
    return '';
  }

  bool _isPdfFile(String fileName) {
    final ext = _getFileExtension(fileName);
    return ext == 'pdf';
  }

  String _getFileTypeDisplayName(String fileName) {
    final ext = _getFileExtension(fileName).toUpperCase();
    switch (ext) {
      case 'PDF':
        return 'PDF File';
      case 'DOC':
        return 'Word Document';
      case 'DOCX':
        return 'Word Document';
      case 'XLS':
        return 'Excel Spreadsheet';
      case 'XLSX':
        return 'Excel Spreadsheet';
      case 'PPT':
        return 'PowerPoint';
      case 'PPTX':
        return 'PowerPoint';
      case 'JPG':
      case 'JPEG':
        return 'Image (JPG)';
      case 'PNG':
        return 'Image (PNG)';
      case 'GIF':
        return 'Image (GIF)';
      case 'ZIP':
        return 'Compressed File';
      default:
        return '${ext.isNotEmpty ? ext.toUpperCase() : 'Unknown'} File';
    }
  }

  String _getMimeType(String fileName, {String? fallbackMimeType}) {
    final fallback = fallbackMimeType?.trim() ?? '';
    if (fallback.isNotEmpty) return fallback;
    switch (_getFileExtension(fileName)) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _openFileExternally(
    String filePath,
    String fileName, {
    String? fallbackMimeType,
  }) async {
    try {
      final ext = _getFileExtension(fileName);
      if (ext == 'xlsx' || ext == 'xls') {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ExcelFileViewerPage(filePath: filePath, fileName: fileName),
          ),
        );
        return;
      }

      final explicitMimeType = _getMimeType(
        fileName,
        fallbackMimeType: fallbackMimeType,
      );
      OpenResult result = await OpenFile.open(filePath, type: explicitMimeType);

      if (result.type != ResultType.done) {
        result = await OpenFile.open(filePath);
      }

      if (!mounted || result.type == ResultType.done) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open ${_getFileTypeDisplayName(fileName)}. Please install a compatible viewer app.',
          ),
          backgroundColor: const Color(0xFFCC0000),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening file: $e'),
          backgroundColor: const Color(0xFFCC0000),
        ),
      );
    }
  }

  Future<void> _viewAttachment(Map<String, dynamic> attachment) async {
    try {
      final fileId = attachment['file_id']?.toString() ?? '';
      final fileName =
          attachment['original_name'] ?? attachment['file_name'] ?? 'document';
      final isPdf = _isPdfFile(fileName.toString());

      if (fileId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to view attachment: File ID not found'),
              backgroundColor: Color(0xFFCC0000),
            ),
          );
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';

      if (token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session expired. Please login again.'),
              backgroundColor: Color(0xFFCC0000),
            ),
          );
        }
        return;
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/upload/document/$fileId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Cache-Control': 'no-cache',
        },
      );

      if (!mounted) return;

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.bodyBytes.isNotEmpty) {
        final dir = await getTemporaryDirectory();

        final fileExtension = _getFileExtension(fileName.toString());
        final preservedFileName =
            'attachment_${fileId}_${DateTime.now().millisecondsSinceEpoch}${fileExtension.isNotEmpty ? '.$fileExtension' : '.pdf'}';

        final file = File('${dir.path}/$preservedFileName');
        await file.writeAsBytes(response.bodyBytes);

        if (mounted) {
          if (isPdf) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PdfSignerPage(
                  pdfPath: file.path,
                  item: _signerItemData(),
                  enableSigning: false,
                ),
              ),
            );
          } else {
            await _openFileExternally(
              file.path,
              fileName.toString(),
              fallbackMimeType: attachment['mime_type']?.toString(),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to load attachment: ${response.statusCode}',
              ),
              backgroundColor: const Color(0xFFCC0000),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Attachment view error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening attachment: $e'),
            backgroundColor: const Color(0xFFCC0000),
          ),
        );
      }
    }
  }

  String _getValue(String apiKey, String fallbackKey) {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final val = data[apiKey];
      if (val != null &&
          val.toString().isNotEmpty &&
          val.toString() != 'null') {
        return val.toString();
      }
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

  DateTime? _parseApiDate(String raw) {
    if (raw.trim().isEmpty || raw == 'null') return null;
    try {
      var normalized = raw.trim();
      normalized = normalized.replaceFirst(RegExp(r'(Z|[+-]\d{2}:\d{2})$'), '');
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _signerItemData() {
    final data = _detail?['data'];
    if (data is Map<String, dynamic>) {
      return {...widget.item, ...data};
    }
    return widget.item;
  }

  Future<bool> _hasUploadedOrSavedSignature() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';

    if (token.isNotEmpty) {
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/upload/signature/image'),
          headers: {'Authorization': 'Bearer $token', 'Accept': '*/*'},
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final contentType = response.headers['content-type'] ?? '';
          if ((contentType.contains('image/') ||
                  contentType.contains('octet-stream')) &&
              response.bodyBytes.isNotEmpty) {
            return true;
          }
          try {
            final decoded = jsonDecode(response.body);
            final data = decoded['data'];
            if (data is Map &&
                (data['base64']?.toString().trim().isNotEmpty ?? false)) {
              return true;
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    final type = prefs.getString('signature_type') ?? '';
    if (type == 'draw' || type == 'capture') {
      final signatureData = prefs.getString('signature_draw_data') ?? '';
      if (signatureData.trim().isNotEmpty) return true;
    } else if (type == 'type') {
      final signatureText = prefs.getString('signature_text') ?? '';
      if (signatureText.trim().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> _handleApproveTap() async {
    if (_isSubmittingRevision || _localPdfPath == null) return;

    final hasSignature = await _hasUploadedOrSavedSignature();
    if (!mounted) return;

    if (!hasSignature) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No signature uploaded. Please upload/create one first.',
          ),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfSignerPage(
          pdfPath: _localPdfPath!,
          item: _signerItemData(),
          enableSigning: true,
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    if (raw.isEmpty || raw == '—') return raw;
    final dt = _parseApiDate(raw);
    if (dt == null) return raw;

    const months = [
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} | '
        '${hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')} '
        '${dt.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> _openMainDocument() async {
    if (_localPdfPath == null) return;
    final fileName = _getFileName();
    if (_isPdfFile(fileName)) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfSignerPage(
            pdfPath: _localPdfPath!,
            item: _signerItemData(),
            enableSigning: false,
          ),
        ),
      );
      return;
    }
    await _openFileExternally(_localPdfPath!, fileName);
  }

  String _getFileName() {
    final headFile = _getHeadFile();
    if (headFile != null) {
      final name =
          headFile['original_name'] ??
          headFile['originalName'] ??
          headFile['file_name'] ??
          headFile['fileName'];
      if (name != null && name.toString().isNotEmpty) return name.toString();
    }
    return widget.item['original_name']?.toString() ??
        '${widget.item['particulars'] ?? 'Document'}.pdf';
  }

  String _getStatus() {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final s = data['status']?.toString().toUpperCase().trim() ?? '';
      if (s.isNotEmpty && s != 'NULL') {
        if (s.startsWith('PEND')) return 'PND';
        if (s.startsWith('APP')) return 'APV';
        if (s.startsWith('REJ')) return 'REJ';
        if (s == 'OPN' || s.startsWith('OPEN')) return 'OPN';
        return s;
      }
    }
    final itemStatus =
        widget.item['status']?.toString().toUpperCase().trim() ?? '';
    if (itemStatus.isNotEmpty && itemStatus != 'NULL') {
      if (itemStatus.startsWith('PEND')) return 'PND';
      if (itemStatus.startsWith('APP')) return 'APV';
      if (itemStatus.startsWith('REJ')) return 'REJ';
      if (itemStatus == 'OPN' || itemStatus.startsWith('OPEN')) return 'OPN';
      return itemStatus;
    }
    return 'PND';
  }

  bool _isPending() {
    if (widget.isFromHistory) return false;
    final s = _getStatus();
    return s == 'PND';
  }

  String _getStatusLabel() {
    final status = _getStatus();
    switch (status) {
      case 'PND':
        return 'PENDING';
      case 'APV':
        return 'APPROVED';
      case 'OPN':
        return 'OPEN';
      case 'CNL':
        return 'CANCELLED';
      default:
        return status;
    }
  }

  Color _getStatusBadgeColor() {
    final status = _getStatus();
    switch (status) {
      case 'CNL':
        return const Color(0xFFCC0000);
      case 'APV':
        return Colors.green;
      case 'OPN':
        return Colors.grey;
      case 'PND':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getDateSent() {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final details = data['details'];
      if (details is List && details.isNotEmpty) {
        DateTime? mostRecentDate;
        for (final d in details) {
          if (d is Map) {
            final ds = d['date_sent']?.toString() ?? '';
            if (ds.isNotEmpty && ds != 'null') {
              try {
                final parsedDate = _parseApiDate(ds);
                if (parsedDate == null) continue;
                if (mostRecentDate == null ||
                    parsedDate.isAfter(mostRecentDate)) {
                  mostRecentDate = parsedDate;
                }
              } catch (_) {}
            }
          }
        }
        if (mostRecentDate != null) {
          return _formatDate(mostRecentDate.toIso8601String());
        }
      }
      final topLevelDateSent = data['date_sent']?.toString() ?? '';
      if (topLevelDateSent.isNotEmpty && topLevelDateSent != 'null') {
        return _formatDate(topLevelDateSent);
      }
      final created = data['date_created']?.toString() ?? '';
      if (created.isNotEmpty && created != 'null') return _formatDate(created);
    }
    return widget.item['dateSent']?.toString() ?? '—';
  }

  String _getDateUpdated() {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final updated = data['date_updated']?.toString() ?? '';
      if (updated.isNotEmpty && updated != 'null') return _formatDate(updated);
      final actionDate = data['action_date']?.toString() ?? '';
      if (actionDate.isNotEmpty && actionDate != 'null') {
        return _formatDate(actionDate);
      }
    }
    final fromItem =
        widget.item['dateUpdated']?.toString() ??
        widget.item['date_updated']?.toString() ??
        '';
    if (fromItem.isNotEmpty && fromItem != 'null') return _formatDate(fromItem);
    return '—';
  }

  // ── Modern underline tab helper ─────────────────────────────────────────────
  Widget _buildTab({required String label, required int index, int count = 0}) {
    final isSelected = _selectedAttachmentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedAttachmentTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected
                    ? const Color(0xFFCC0000)
                    : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                index == 0 ? Icons.attach_file_rounded : Icons.link_rounded,
                size: 13,
                color: isSelected ? const Color(0xFFCC0000) : Colors.black38,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? const Color(0xFFCC0000) : Colors.black45,
                  letterSpacing: 0.3,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFCC0000)
                        : const Color(0xFFE8E8E8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : Colors.black45,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
                    color: _getStatusBadgeColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _getStatusLabel(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: _getStatusBadgeColor(),
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

            // ── Document Information ─────────────────────────────────────────
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
                      _getDateSent(),
                    ),
                    const Divider(height: 24, color: Color(0xFFF0F0F0)),
                    _buildInfoRow(
                      Icons.update_outlined,
                      "DATE UPDATED",
                      _getDateUpdated(),
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

            // ── Document to sign ─────────────────────────────────────────────
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
                    "DOCUMENT TO SIGN",
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
                            Text(
                              _getFileTypeDisplayName(fileName),
                              style: const TextStyle(
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
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: _localPdfPath != null
                                      ? _openMainDocument
                                      : null,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _localPdfPath != null
                                          ? const Color(0xFFCC0000)
                                          : Colors.black12,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.visibility_outlined,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Attachments + Document Links ─────────────────────────────────
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
                    "SUPPORTING DOCUMENTS",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Modern underline tabs ──────────────────────────────────
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Color(0xFFE8E8E8),
                          width: 1.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildTab(
                          label: "External Attachment",
                          index: 0,
                          count: _getAttachmentFiles().length,
                        ),
                        _buildTab(
                          label: "Document Link",
                          index: 1,
                          count: _documentLinks.length,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Tab content ────────────────────────────────────────────
                  if (_selectedAttachmentTab == 0) ...[
                    if (_getAttachmentFiles().isEmpty)
                      const Text(
                        'No attachments found.',
                        style: TextStyle(fontSize: 11, color: Colors.black45),
                      )
                    else
                      ..._getAttachmentFiles().map((attachment) {
                        final name =
                            attachment['original_name'] ??
                            attachment['file_name'] ??
                            'Document';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFCC0000,
                                  ).withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.picture_as_pdf_outlined,
                                  color: Color(0xFFCC0000),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1A1A1A),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _getFileTypeDisplayName(name.toString()),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.black38,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _viewAttachment(attachment),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFCC0000),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(
                                    Icons.visibility_outlined,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                  ] else ...[
                    if (_isLoadingDocumentLinks)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFCC0000),
                          ),
                        ),
                      )
                    else if (_documentLinks.isEmpty)
                      const Text(
                        'No document links found.',
                        style: TextStyle(fontSize: 11, color: Colors.black45),
                      )
                    else
                      ..._documentLinks.map((link) {
                        final referenceNo =
                            link['reference_no']
                                    ?.toString()
                                    .trim()
                                    .isNotEmpty ==
                                true
                            ? link['reference_no'].toString()
                            : 'No reference';
                        final linkFiles = _getDocumentLinkFiles(link);

                        // ── Bordered card per document link ────────────────
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFE8E8E8),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              color: const Color(0xFFFAFAFA),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Reference header
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF3F3F4),
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Color(0xFFE8E8E8),
                                        width: 1,
                                      ),
                                    ),
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(6),
                                      topRight: Radius.circular(6),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.link_rounded,
                                        size: 13,
                                        color: Color(0xFFCC0000),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        referenceNo,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1A1A1A),
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Files list
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Column(
                                    children: linkFiles.asMap().entries.map((
                                      entry,
                                    ) {
                                      final isLast =
                                          entry.key == linkFiles.length - 1;
                                      final file = entry.value;
                                      final fileName =
                                          file['original_name'] ??
                                          file['file_name'] ??
                                          'Document';
                                      return Column(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 32,
                                                  height: 32,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFCC0000,
                                                    ).withOpacity(0.08),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: const Icon(
                                                    Icons
                                                        .insert_drive_file_outlined,
                                                    color: Color(0xFFCC0000),
                                                    size: 16,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    fileName.toString(),
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Color(0xFF1A1A1A),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                GestureDetector(
                                                  onTap: () =>
                                                      _viewAttachment(file),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(7),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFCC0000,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                    child: const Icon(
                                                      Icons.visibility_outlined,
                                                      color: Colors.white,
                                                      size: 15,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (!isLast)
                                            const Divider(
                                              height: 1,
                                              color: Color(0xFFEEEEEE),
                                            ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Take Action (pending only) ────────────────────────────────────
            if (_isPending())
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
                      "TAKE ACTION",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Review the document above and take appropriate action.",
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                (_isSubmittingRevision || _localPdfPath == null)
                                ? null
                                : _handleApproveTap,
                            icon: const Icon(
                              Icons.check_circle_outlined,
                              color: Colors.white,
                              size: 16,
                            ),
                            label: _isLoadingPdf
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    "APPROVE",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF28A745),
                              disabledBackgroundColor: const Color(
                                0xFF28A745,
                              ).withOpacity(0.5),
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isSubmittingRevision
                                ? null
                                : _showRequestRevisionDialog,
                            icon: const Icon(
                              Icons.refresh_outlined,
                              color: Colors.black,
                              size: 16,
                            ),
                            label: const Text(
                              "REQUEST REVISION",
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
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

class ExcelFileViewerPage extends StatefulWidget {
  final String filePath;
  final String fileName;

  const ExcelFileViewerPage({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<ExcelFileViewerPage> createState() => _ExcelFileViewerPageState();
}

class _ExcelFileViewerPageState extends State<ExcelFileViewerPage> {
  bool _isLoading = true;
  String? _error;
  List<String> _sheetNames = [];
  final Map<String, List<List<String>>> _sheetRows = {};
  int _sheetIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadWorkbook();
  }

  Future<void> _loadWorkbook() async {
    try {
      late Uint8List bytes;

      if (widget.filePath.startsWith('http')) {
        final response = await http.get(Uri.parse(widget.filePath));
        if (response.statusCode != 200) throw Exception('Failed to fetch');
        bytes = response.bodyBytes;
      } else {
        final file = File(widget.filePath);
        if (!await file.exists()) {
          setState(() {
            _error = 'File not found.';
            _isLoading = false;
          });
          return;
        }
        bytes = await file.readAsBytes();
      }

      final decoder = SpreadsheetDecoder.decodeBytes(bytes);
      final names = decoder.tables.keys.toList();
      final parsed = <String, List<List<String>>>{};

      for (final name in names) {
        final table = decoder.tables[name]!;
        final rows = <List<String>>[];
        for (var r = 0; r < table.maxRows; r++) {
          final row = <String>[];
          for (var c = 0; c < table.maxCols; c++) {
            row.add(table.rows[r][c]?.toString() ?? '');
          }
          rows.add(row);
        }
        parsed[name] = rows;
      }

      if (!mounted) return;
      setState(() {
        _sheetNames = names;
        _sheetRows
          ..clear()
          ..addAll(parsed);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to read Excel file: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSheet = _sheetNames.isNotEmpty ? _sheetNames[_sheetIndex] : '';
    final rows = _sheetRows[currentSheet] ?? const <List<String>>[];
    final maxCols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _sheetNames.isEmpty
          ? const Center(child: Text('No sheets found.'))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: const Color(0xFFF8F8F8),
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _sheetIndex,
                    items: List.generate(
                      _sheetNames.length,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(_sheetNames[i]),
                      ),
                    ),
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() => _sheetIndex = val);
                    },
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: (maxCols * 140).toDouble().clamp(280, 5000),
                      child: ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, rowIndex) {
                          final row = rows[rowIndex];
                          return Container(
                            color: rowIndex == 0
                                ? const Color(0xFFF1F1F1)
                                : Colors.white,
                            child: Row(
                              children: List.generate(maxCols, (colIndex) {
                                final text = colIndex < row.length
                                    ? row[colIndex]
                                    : '';
                                return Container(
                                  width: 140,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: const Color(0xFFE3E3E3),
                                    ),
                                  ),
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: rowIndex == 0
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PDF SIGNER PAGE
// ─────────────────────────────────────────────────────────────────────────────

class PdfSignerPage extends StatefulWidget {
  final String pdfPath;
  final Map<String, dynamic> item;
  final bool enableSigning;

  const PdfSignerPage({
    super.key,
    required this.pdfPath,
    required this.item,
    this.enableSigning = false,
  });

  @override
  State<PdfSignerPage> createState() => _PdfSignerPageState();
}

class _PdfSignerPageState extends State<PdfSignerPage> {
  bool _isSigningMode = false;
  bool _isSubmitting = false;
  bool _isLoadingSignature = true;
  bool _showSignatureLoadingOverlay = false;
  bool _pendingEnterSigningMode = false;
  DateTime? _signedAt;
  Uint8List? _watermarkBytes;

  final GlobalKey _signatureKey = GlobalKey();

  Uint8List? _signatureBytes;
  String? _signatureText;

  String _signerName = '';
  String _signerEmployeeId = '';

  Offset _signaturePosition = const Offset(60, 300);
  double _signatureWidth = 200;
  double _signatureHeight = 55;

  double _containerWidth = 0;
  double _containerHeight = 0;

  int _currentPage = 0;
  int _totalPages = 1;

  static const double _pdfPageWidthPt = 595.0;
  static const double _pdfPageHeightPt = 842.0;

  DateTime? _parseApiDate(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty || value == 'null') return null;
    try {
      var normalized = value;
      normalized = normalized.replaceFirst(RegExp(r'(Z|[+-]\d{2}:\d{2})$'), '');
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  DateTime? _resolveSigningApiTime() {
    final routing = widget.item['routing'];
    final routingMap = routing is Map ? routing : <String, dynamic>{};
    final candidates = [
      widget.item['date_sent']?.toString(),
      routingMap['date_sent']?.toString(),
      widget.item['date_updated']?.toString(),
      routingMap['date_updated']?.toString(),
      widget.item['created_at']?.toString(),
    ];
    for (final raw in candidates) {
      final parsed = _parseApiDate(raw);
      if (parsed != null) return parsed;
    }
    return null;
  }

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
    _loadWatermark();
    if (widget.enableSigning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enterSigningMode();
      });
    }
  }

  Future<void> _loadWatermark() async {
    try {
      final byteData = await rootBundle.load(
        'assets/images/eforward_watermark.png',
      );
      if (mounted) {
        setState(() => _watermarkBytes = byteData.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint('Watermark load error: $e');
    }
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
  }

  Future<Uint8List> _removeWhiteBackground(Uint8List imageBytes) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return imageBytes;
    final pixels = byteData.buffer.asUint8List();
    for (int i = 0; i < pixels.length; i += 4) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      if (r > 200 && g > 200 && b > 200) pixels[i + 3] = 0;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      image.width,
      image.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final processedImage = await completer.future;
    final processedData = await processedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return processedData?.buffer.asUint8List() ?? imageBytes;
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
          final processed = await _removeWhiteBackground(response.bodyBytes);
          if (mounted) {
            setState(() {
              _signatureBytes = processed;
              _isLoadingSignature = false;
            });
            _onSignatureLoadingCompleted();
          }
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
      _signedAt = _resolveSigningApiTime() ?? DateTime.now();
      _signaturePosition = Offset(
        _containerWidth > 0 ? (_containerWidth - _signatureWidth) / 2 : 60,
        _containerHeight > 0 ? _containerHeight * 0.7 : 300,
      );
    });
  }

  Future<Uint8List?> _captureSignatureWidget() async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      final boundary =
          _signatureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Capture error: $e');
      return null;
    }
  }

  Future<File?> _generateSignedPdf() async {
    try {
      final capturedBytes = await _captureSignatureWidget();
      if (capturedBytes == null) return null;

      final pdfBytes = await File(widget.pdfPath).readAsBytes();
      final document = PdfDocument(inputBytes: pdfBytes);
      final page = document.pages[_currentPage];
      final pageSize = page.size;

      final pdfX = (_signaturePosition.dx / _containerWidth) * pageSize.width;
      final pdfY = (_signaturePosition.dy / _containerHeight) * pageSize.height;
      final pdfW = (_signatureWidth / _containerWidth) * pageSize.width;
      final pdfH = (_signatureHeight / _containerHeight) * pageSize.height;

      final signatureImage = PdfBitmap(capturedBytes);
      page.graphics.drawImage(
        signatureImage,
        Rect.fromLTWH(pdfX, pdfY, pdfW, pdfH),
      );

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

  Future<void> _submitApproval() async {
    setState(() => _isSubmitting = true);
    try {
      final signedPdfFile = await _generateSignedPdf();
      if (signedPdfFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to generate signed PDF.'),
            backgroundColor: Color(0xFFCC0000),
          ),
        );
        setState(() => _isSubmitting = false);
        return;
      }

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
      final signaturePage = _currentPage + 1;

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
      debugPrint('Approve response: ${response.body}');

      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() => _isSubmitting = false);
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

    final now = _signedAt ?? DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final refNo =
        widget.item['referenceNo']?.toString() ??
        widget.item['routing']?['reference_no']?.toString() ??
        '';

    final responsiveFontSize = (_signatureHeight * 0.14).clamp(4.0, 12.0);
    final responsiveLabelFontSize = (_signatureHeight * 0.12).clamp(3.5, 10.0);
    final responsivePadding = (_signatureHeight * 0.08).clamp(0.5, 2.0);
    final responsiveSpacing = (_signatureHeight * 0.06).clamp(2.0, 5.0);

    return Container(
      width: _signatureWidth,
      height: _signatureHeight,
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _signatureWidth * 0.45,
            height: _signatureHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_signatureBytes != null)
                  Image.memory(
                    _signatureBytes!,
                    fit: BoxFit.contain,
                    width: _signatureWidth * 0.45,
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
                if (_watermarkBytes != null)
                  Opacity(
                    opacity: 0.15,
                    child: Image.memory(_watermarkBytes!, fit: BoxFit.contain),
                  ),
              ],
            ),
          ),

          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF1B5E20).withOpacity(0.35),
                  width: 0.8,
                ),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: responsivePadding * 1.5,
                vertical: responsivePadding * 0.5,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _metaRow(
                      'Digitally signed by:',
                      _signerName,
                      responsiveFontSize,
                      responsiveLabelFontSize,
                      responsiveSpacing,
                    ),
                    SizedBox(height: responsiveSpacing * 0.5),
                    _metaRow(
                      'Employee ID:',
                      _signerEmployeeId,
                      responsiveFontSize,
                      responsiveLabelFontSize,
                      responsiveSpacing,
                    ),
                    SizedBox(height: responsiveSpacing * 0.5),
                    _metaRow(
                      'Date:',
                      dateStr,
                      responsiveFontSize,
                      responsiveLabelFontSize,
                      responsiveSpacing,
                    ),
                    SizedBox(height: responsiveSpacing * 0.5),
                    _metaRow(
                      'Ref:',
                      refNo,
                      responsiveFontSize,
                      responsiveLabelFontSize,
                      responsiveSpacing,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(
    String label,
    String value,
    double fontSize,
    double labelFontSize,
    double spacing,
  ) {
    return RichText(
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      text: TextSpan(
        style: TextStyle(
          fontSize: labelFontSize,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1A1A1A),
          height: 1.1,
        ),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.normal),
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
          if (!_isSigningMode && widget.enableSigning)
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
      body: Stack(
        children: [
          Column(
            children: [
              if (_isSigningMode)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFCC0000),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.drag_indicator, size: 16, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Drag to move · pull corners/edges to resize",
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
                            enableSwipe: true,
                            swipeHorizontal: false,
                            autoSpacing: true,
                            pageFling: false,
                            backgroundColor: Colors.grey.shade200,
                            onPageChanged: (page, total) {
                              if (mounted) {
                                setState(() {
                                  _currentPage = page ?? 0;
                                  _totalPages = total ?? 1;
                                });
                              }
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
                            left: _signaturePosition.dx - 12,
                            top: _signaturePosition.dy - 12,
                            child: SizedBox(
                              width: _signatureWidth + 24,
                              height: _signatureHeight + 24,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    left: 12,
                                    top: 12,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onPanUpdate: (d) {
                                        setState(() {
                                          _signaturePosition = Offset(
                                            (_signaturePosition.dx + d.delta.dx)
                                                .clamp(
                                                  0.0,
                                                  constraints.maxWidth -
                                                      _signatureWidth,
                                                ),
                                            (_signaturePosition.dy + d.delta.dy)
                                                .clamp(
                                                  0.0,
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
                                              color: Colors.black.withOpacity(
                                                0.15,
                                              ),
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
                                  ),

                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    child: _ResizeHandle(
                                      onPanUpdate: (d) {
                                        setState(() {
                                          final aspectRatio =
                                              _signatureWidth /
                                              _signatureHeight;
                                          final newW =
                                              (_signatureWidth - d.delta.dx)
                                                  .clamp(
                                                    100.0,
                                                    constraints.maxWidth,
                                                  );
                                          final newH = newW / aspectRatio;
                                          if (newH >= 40) {
                                            _signaturePosition = Offset(
                                              (_signaturePosition.dx +
                                                      d.delta.dx)
                                                  .clamp(0.0, double.infinity),
                                              (_signaturePosition.dy -
                                                      (newH - _signatureHeight))
                                                  .clamp(0.0, double.infinity),
                                            );
                                            _signatureWidth = newW;
                                            _signatureHeight = newH;
                                          }
                                        });
                                      },
                                    ),
                                  ),

                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: _ResizeHandle(
                                      onPanUpdate: (d) {
                                        setState(() {
                                          final aspectRatio =
                                              _signatureWidth /
                                              _signatureHeight;
                                          final newW =
                                              (_signatureWidth + d.delta.dx)
                                                  .clamp(
                                                    100.0,
                                                    constraints.maxWidth -
                                                        _signaturePosition.dx,
                                                  );
                                          final newH = newW / aspectRatio;
                                          if (newH >= 40) {
                                            _signaturePosition = Offset(
                                              _signaturePosition.dx,
                                              (_signaturePosition.dy -
                                                      (newH - _signatureHeight))
                                                  .clamp(0.0, double.infinity),
                                            );
                                            _signatureWidth = newW;
                                            _signatureHeight = newH;
                                          }
                                        });
                                      },
                                    ),
                                  ),

                                  Positioned(
                                    left: 0,
                                    bottom: 0,
                                    child: _ResizeHandle(
                                      onPanUpdate: (d) {
                                        setState(() {
                                          final aspectRatio =
                                              _signatureWidth /
                                              _signatureHeight;
                                          final newW =
                                              (_signatureWidth - d.delta.dx)
                                                  .clamp(
                                                    100.0,
                                                    constraints.maxWidth,
                                                  );
                                          final newH = newW / aspectRatio;
                                          if (newH >= 40) {
                                            _signaturePosition = Offset(
                                              (_signaturePosition.dx +
                                                      d.delta.dx)
                                                  .clamp(0.0, double.infinity),
                                              _signaturePosition.dy,
                                            );
                                            _signatureWidth = newW;
                                            _signatureHeight = newH;
                                          }
                                        });
                                      },
                                    ),
                                  ),

                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: _ResizeHandle(
                                      onPanUpdate: (d) {
                                        setState(() {
                                          final aspectRatio =
                                              _signatureWidth /
                                              _signatureHeight;
                                          final newW =
                                              (_signatureWidth + d.delta.dx)
                                                  .clamp(
                                                    100.0,
                                                    constraints.maxWidth -
                                                        _signaturePosition.dx,
                                                  );
                                          final newH = newW / aspectRatio;
                                          if (newH >= 40) {
                                            _signatureWidth = newW;
                                            _signatureHeight = newH;
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
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
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submitApproval,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            disabledBackgroundColor: Colors.green.withOpacity(
                              0.6,
                            ),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: Row(
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
                              Icon(
                                Icons.close,
                                color: Color(0xFFCC0000),
                                size: 18,
                              ),
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
          if (_isSubmitting || _showSignatureLoadingOverlay)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: Colors.black.withOpacity(0.45),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _PulsingDotsLoader(
                            color: Colors.white,
                            dotSize: 10,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _isSubmitting
                                ? 'Please wait...'
                                : 'Signature is still loading. Please wait...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESIZE HANDLE WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class _ResizeHandle extends StatelessWidget {
  final GestureDragUpdateCallback onPanUpdate;
  final bool isEdge;

  const _ResizeHandle({required this.onPanUpdate, this.isEdge = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: onPanUpdate,
      child: isEdge
          ? Container(color: const Color(0xFFCC0000).withOpacity(0.6))
          : Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFFCC0000),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.open_in_full,
                size: 12,
                color: Colors.white,
              ),
            ),
    );
  }
}

class _PulsingDotsLoader extends StatefulWidget {
  final Color color;
  final double dotSize;
  const _PulsingDotsLoader({this.color = Colors.white, this.dotSize = 8});

  @override
  State<_PulsingDotsLoader> createState() => _PulsingDotsLoaderState();
}

class _PulsingDotsLoaderState extends State<_PulsingDotsLoader>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );
    _animations = _controllers
        .map(
          (c) => Tween<double>(
            begin: 0,
            end: 1,
          ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
        )
        .toList();

    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers)
      _controllers[_controllers.indexOf(c)].dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _animations[i],
          builder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Opacity(
              opacity: 0.3 + (_animations[i].value * 0.7),
              child: Transform.translate(
                offset: Offset(0, -4 * _animations[i].value),
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
