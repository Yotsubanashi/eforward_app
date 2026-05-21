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
import 'package:eforward_app/pages/approvals/approvals.dart';
import 'package:eforward_app/config/app_env.dart';
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
  bool _documentNotFound = false;
  String? _localPdfPath;
  String? _localExcelPath;
  bool _isSubmittingRevision = false;
  bool _isApproving = false;
  bool _isSubmittingAttachmentRequest = false;
  int _selectedAttachmentTab = 0;

  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _documentLinks = [];
  final TextEditingController _revisionRemarksController =
      TextEditingController();
  final TextEditingController _attachmentRemarksController =
      TextEditingController();

  String get _baseUrl => AppEnv.apiBaseUrl;

  @override
  void initState() {
    super.initState();
    setState(() => _isLoadingPdf = true);
    _fetchApprovalDetail();
  }

  @override
  void dispose() {
    _revisionRemarksController.dispose();
    _attachmentRemarksController.dispose();
    super.dispose();
  }

  void _showRequestAttachmentDialog() {
    _attachmentRemarksController.clear();
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
                      "REQUEST ATTACHMENT",
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
                      controller: _attachmentRemarksController,
                      minLines: 4,
                      maxLines: 6,
                      decoration: InputDecoration(
                        hintText: "Enter your attachment request remarks...",
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
                            onPressed: _isSubmittingAttachmentRequest
                                ? null
                                : () => _submitRequestAttachment(context),
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
                            child: _isSubmittingAttachmentRequest
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

  Future<void> _submitRequestAttachment(BuildContext dialogContext) async {
    final remarks = _attachmentRemarksController.text.trim();
    if (remarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter remarks'),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }
    setState(() => _isSubmittingAttachmentRequest = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final id = _getRoutingId();
      if (token.isEmpty || id.isEmpty) {
        throw Exception('Missing token or approval ID');
      }

      await ApprovalsApi().requestAttachment(
        token: token,
        routingId: id,
        remarks: remarks,
      );

      if (!mounted) return;
      Navigator.pop(dialogContext);
      setState(() => _isSubmittingAttachmentRequest = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attachment request sent successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _isSubmittingAttachmentRequest = false);
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
          setState(() {
            _isLoadingDetail = false;
            _isLoadingPdf = false;
          });
          await _fetchDocumentLinks();
        }
      }
    } catch (e) {
      debugPrint('Approval detail error: $e');
      if (mounted) {
        setState(() {
          _isLoadingDetail = false;
          _isLoadingPdf = false;
        });
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
    setState(() {
      _isLoadingPdf = true;
      _documentNotFound = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final fileId = _extractFileId(detailData);
      if (fileId == null || fileId.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoadingPdf = false;
            _documentNotFound = true;
          });
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
        final dir = await getTemporaryDirectory();
        final fileName = _getFileName();
        final fileExtension = _getFileExtension(fileName);
        final preservedFileName =
            'doc_${fileId}_${DateTime.now().millisecondsSinceEpoch}'
            '${fileExtension.isNotEmpty ? '.$fileExtension' : '.pdf'}';
        final file = File('${dir.path}/$preservedFileName');
        await file.writeAsBytes(response.bodyBytes);
        if (mounted) {
          setState(() {
            _localPdfPath = file.path;
            _isLoadingPdf = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingPdf = false;
            _documentNotFound = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Document fetch error: $e');
      if (mounted) {
        setState(() {
          _isLoadingPdf = false;
          _documentNotFound = true;
        });
      }
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

  Future<Directory?> _getDownloadsDirectory() async {
    try {
      if (Platform.isAndroid) {
        final androidDownloads = Directory('/storage/emulated/0/Download');
        if (await androidDownloads.exists()) return androidDownloads;
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

        if (!await dir.exists()) await dir.create(recursive: true);

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
    if (fileName.contains('.')) return fileName.split('.').last.toLowerCase();
    return '';
  }

  bool _isPdfFile(String fileName) {
    return _getFileExtension(fileName) == 'pdf';
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
            'Unable to open ${_getFileTypeDisplayName(fileName)}. '
            'Please install a compatible viewer app.',
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
            'attachment_${fileId}_${DateTime.now().millisecondsSinceEpoch}'
            '${fileExtension.isNotEmpty ? '.$fileExtension' : '.pdf'}';

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
    if (data is Map<String, dynamic>) return {...widget.item, ...data};
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

    setState(() => _isApproving = true);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfSignerPage(
          pdfPath: _localPdfPath!,
          item: _signerItemData(),
          enableSigning: true,
          initialSigningMode: true,
        ),
      ),
    );
    if (mounted) setState(() => _isApproving = false);
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
    return _getStatus() == 'PND';
  }

  String _getStatusLabel() {
    switch (_getStatus()) {
      case 'PND':
        return 'PENDING';
      case 'APV':
        return 'APPROVED';
      case 'OPN':
        return 'OPEN';
      case 'CNL':
        return 'CANCELLED';
      default:
        return _getStatus();
    }
  }

  Color _getStatusBadgeColor() {
    switch (_getStatus()) {
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
      final created = data['date_created']?.toString() ?? '';
      if (created.isNotEmpty && created != 'null') return _formatDate(created);

      final details = data['details'];
      if (details is List && details.isNotEmpty) {
        DateTime? earliestDate;
        for (final d in details) {
          if (d is Map) {
            final ds = d['date_sent']?.toString() ?? '';
            final parsed = _parseApiDate(ds);
            if (parsed != null) {
              if (earliestDate == null || parsed.isBefore(earliestDate)) {
                earliestDate = parsed;
              }
            }
          }
        }
        if (earliestDate != null) {
          return _formatDate(earliestDate.toIso8601String());
        }
      }

      final topLevelDateSent = data['date_sent']?.toString() ?? '';
      if (topLevelDateSent.isNotEmpty && topLevelDateSent != 'null') {
        return _formatDate(topLevelDateSent);
      }
    }
    return widget.item['dateSent']?.toString() ?? '—';
  }

  String _getDateUpdated() {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      DateTime? latestDate;

      void check(String? raw) {
        final parsed = _parseApiDate(raw ?? '');
        if (parsed != null) {
          final current = latestDate;
          if (current == null || parsed.isAfter(current)) latestDate = parsed;
        }
      }

      check(data['date_updated']?.toString());
      check(data['action_date']?.toString());

      final details = data['details'];
      if (details is List && details.isNotEmpty) {
        for (final d in details) {
          if (d is Map) {
            check(d['action_date']?.toString());
            check(d['date_sent']?.toString());
          }
        }
      }

      final finalLatest = latestDate;
      if (finalLatest != null)
        return _formatDate(finalLatest.toIso8601String());
    }
    final fromItem =
        widget.item['dateUpdated']?.toString() ??
        widget.item['date_updated']?.toString() ??
        '';
    if (fromItem.isNotEmpty && fromItem != 'null') return _formatDate(fromItem);
    return '—';
  }

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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE8E8E8)),
                borderRadius: BorderRadius.circular(8),
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
                  if (_isLoadingPdf)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFCC0000),
                        ),
                      ),
                    )
                  else if (_documentNotFound)
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.error_outline,
                            color: Colors.black38,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            "Document Not Found (404)",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black38,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
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
                          child: Text(
                            fileName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A1A),
                            ),
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap:
                              _localPdfPath != null ? _openMainDocument : null,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color:
                                  _localPdfPath != null
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
                    "SUPPORTING DOCUMENTS",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 12),
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
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            ),
                            label: _isApproving
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
                              backgroundColor: const Color(0xFF059669),
                              disabledBackgroundColor: const Color(
                                0xFF059669,
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
                          child: ElevatedButton(
                            onPressed:
                                (_isSubmittingRevision ||
                                    _isSubmittingAttachmentRequest)
                                ? null
                                : _showRequestRevisionDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(
                                255,
                                199,
                                41,
                                30,
                              ),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.refresh_outlined,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    "REQUEST REVISION",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
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
                        onPressed:
                            (_isSubmittingRevision ||
                                _isSubmittingAttachmentRequest)
                            ? null
                            : _showRequestAttachmentDialog,
                        icon: const Icon(
                          Icons.attach_file_outlined,
                          color: Colors.black,
                          size: 16,
                        ),
                        label: const Text(
                          "REQUEST ATTACHMENT",
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
                            side: const BorderSide(
                              color: Color.fromARGB(255, 199, 199, 199),
                              width: 1,
                            ),
                          ),
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
// EXCEL VIEWER
// ─────────────────────────────────────────────────────────────────────────────

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

  // ── Capture keys ──────────────────────────────────────────────────────────
  final GlobalKey _signatureKey = GlobalKey();
  final GlobalKey _commentKey = GlobalKey();

  // ── Signature data ────────────────────────────────────────────────────────
  Uint8List? _signatureBytes;
  String? _signatureText;

  // ── Signer info ───────────────────────────────────────────────────────────
  String _signerName = '';
  String _signerEmployeeId = '';

  // ── PDF controller & dimensions ──────────────────────────────────────────
  PDFViewController? _pdfController;
  final TransformationController _transformationController =
      TransformationController();
  int _signaturePage = 0;
  double _sigAspectRatio = 3.5; // Width / Height
  double _cmtAspectRatio = 4.0;

  // PDF Page Size in points (e.g. 612x792 for Letter)
  double _pdfPageWidth = 0;
  double _pdfPageHeight = 0;

  // Anchor position in PDF Point Space (fixed to the document content)
  double? _sigPdfX;
  double? _sigPdfY;
  double? _cmtPdfX;
  double? _cmtPdfY;

  // ── Fraction-based overlay positions (0.0 – 1.0 of viewport) ─────────────
  // Signature
  double _sigFracX = 0.25;
  double _sigFracY = 0.78;
  double _sigFracW = 0.40;
  double _sigFracH = 0.11; // Initial height based on 3.5 ratio (0.4/3.5)
  // Comment
  double _cmtFracX = 0.05;
  double _cmtFracY = 0.58;
  double _cmtFracW = 0.55;
  double _cmtFracH = 0.14; // Initial height based on 4.0 ratio (0.55/4.0)

  // ── Viewport size (pixels — from LayoutBuilder) ───────────────────────────
  double _viewportWidth = 0;
  double _viewportHeight = 0;

  // ── Computed pixel sizes from fractions ───────────────────────────────────
  double get _sigPixelW =>
      (_sigFracW * _viewportWidth).clamp(80, double.infinity);
  double get _sigPixelH =>
      (_sigFracH * _viewportHeight).clamp(30, double.infinity);
  double get _cmtPixelW =>
      (_cmtFracW * _viewportWidth).clamp(80, double.infinity);
  double get _cmtPixelH =>
      (_cmtFracH * _viewportHeight).clamp(30, double.infinity);

  // ── PDF page info ─────────────────────────────────────────────────────────
  int _currentPage = 0;
  int _totalPages = 1;

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

    if (widget.initialSigningMode) {
      _isSigningMode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _signedAt = _resolveSigningApiTime() ?? DateTime.now();
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

  // ── Asset loaders ─────────────────────────────────────────────────────────

  Future<void> _loadWatermark() async {
    try {
      final bd = await rootBundle.load('assets/images/eforward_watermark.png');
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
            });
            _updateSigAspectRatio(processed); // Update ratio
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
                _updateSigAspectRatio(processed); // Update ratio
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

  Future<void> _updateSigAspectRatio(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (mounted) {
        setState(() {
          // The signature content is: image (45% width) + metadata (55% width)
          _sigAspectRatio = (image.width / 0.45) / image.height;
          // Sync height to initial width if viewport is already known
          if (_viewportWidth > 0 && _viewportHeight > 0) {
            _sigFracH =
                (_sigFracW * _viewportWidth / _sigAspectRatio) /
                _viewportHeight;
          }
        });
      }
    } catch (e) {
      debugPrint('Error updating aspect ratio: $e');
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
      // Reset to default fractions each time signing mode is entered
      _sigFracX = 0.25;
      _sigFracY = 0.78;
      _sigFracW = 0.40;
      _sigFracH = 0.11;
      _cmtFracX = 0.05;
      _cmtFracY = 0.58;
      _cmtFracW = 0.55;
      _cmtFracH = 0.12;
    });
  }

  Future<void> _moveToCurrentView() async {
    if (_pdfController == null || _viewportWidth <= 0) return;
    try {
      // Get the center of the viewport in screen coordinates
      final screenCenter = Offset(_viewportWidth / 2, _viewportHeight / 2);

      // Convert screen center to scene (stack) coordinates using TransformationController
      final sceneCenter = _transformationController.toScene(screenCenter);

      setState(() {
        _signaturePage = _currentPage;

        // Calculate new fractions based on scene coordinates
        // We want the overlay to be CENTERED at sceneCenter
        _sigFracX =
            ((sceneCenter.dx - (_sigFracW * _viewportWidth / 2)) /
                    _viewportWidth)
                .clamp(0.0, 1.0 - _sigFracW);
        _sigFracY =
            ((sceneCenter.dy - (_sigFracH * _viewportHeight / 2)) /
                    _viewportHeight)
                .clamp(0.0, 1.0 - _sigFracH);

        // Move comment relative to signature or to the same spot
        _cmtFracX = _sigFracX;
        _cmtFracY = (_sigFracY - 0.15).clamp(0.0, 1.0 - _cmtFracH);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signature moved to current view'),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
    } catch (e) {
      debugPrint('Move to view error: $e');
    }
  }

  // ── Date helpers ──────────────────────────────────────────────────────────

  DateTime? _parseApiDate(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty || value == 'null') return null;
    try {
      return DateTime.parse(
        value.replaceFirst(RegExp(r'(Z|[+-]\d{2}:\d{2})$'), ''),
      );
    } catch (_) {
      return null;
    }
  }

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
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      return bd?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Capture error: $e');
      return null;
    }
  }

  // ── PDF generation (fraction → PDF point space) ───────────────────────────

  Future<File?> _generateSignedPdf() async {
    final capturedSignature = await _captureWidget(_signatureKey);
    if (capturedSignature == null) {
      debugPrint('_generateSignedPdf: signature capture returned null');
      return null;
    }

    try {
      final pdfBytes = await File(widget.pdfPath).readAsBytes();
      final document = PdfDocument(inputBytes: pdfBytes);
      final page = document.pages[_currentPage];
      final pdfW = page.size.width;
      final pdfH = page.size.height;

      // Fraction → PDF point coordinates — zoom-independent
      final sigRect = Rect.fromLTWH(
        _sigFracX * pdfW,
        _sigFracY * pdfH,
        _sigFracW * pdfW,
        _sigFracH * pdfH,
      );
      page.graphics.drawImage(PdfBitmap(capturedSignature), sigRect);

      if (_remarks.trim().isNotEmpty) {
        final capturedComment = await _captureWidget(_commentKey);
        if (capturedComment != null) {
          final cmtRect = Rect.fromLTWH(
            _cmtFracX * pdfW,
            _cmtFracY * pdfH,
            _cmtFracW * pdfW,
            _cmtFracH * pdfH,
          );
          page.graphics.drawImage(PdfBitmap(capturedComment), cmtRect);
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
    setState(() => _isSubmitting = true);
    try {
      final signedPdfFile = await _generateSignedPdf();
      if (signedPdfFile == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to generate signed PDF.'),
              backgroundColor: Color(0xFFCC0000),
            ),
          );
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Missing required data. Cannot approve.'),
              backgroundColor: Color(0xFFCC0000),
            ),
          );
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
          'sign_height': double.parse(_sigFracH.toStringAsFixed(4)),
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

    final now = _signedAt ?? DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final refNo =
        widget.item['referenceNo']?.toString() ??
        widget.item['routing']?['reference_no']?.toString() ??
        '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: w * 0.45, // Responsive width (45% of total width)
          height: h,
          child: Stack(
            alignment: Alignment.center, // Center internally as requested
            children: [
              if (_signatureBytes != null)
                Image.memory(
                  _signatureBytes!,
                  fit: BoxFit.contain,
                  width: w * 0.45,
                  height: h,
                  alignment: Alignment.center,
                )
              else if (_signatureText != null && _signatureText!.isNotEmpty)
                SizedBox(
                  width: w * 0.45,
                  height: h,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    child: Text(
                      _signatureText!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                ),
              if (_watermarkBytes != null)
                Opacity(
                  opacity: 0.15,
                  child: Image.memory(
                    _watermarkBytes!,
                    fit: BoxFit.contain,
                    width: w * 0.45,
                    height: h,
                    alignment: Alignment.center,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            height: h,
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color(0xFF1B5E20).withOpacity(0.2),
                width: 0.6,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
        ),
      ],
    );
  }

  Widget _buildCommentWidget({double? width, double? height}) {
    final w = width ?? _cmtPixelW;
    final h = height ?? _cmtPixelH;
    final displayName = _signerName.isNotEmpty
        ? _signerName
              .split(' ')
              .map(
                (w) => w.isEmpty
                    ? ''
                    : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
              )
              .join(' ')
        : 'User';
    return SizedBox(
      width: w,
      height: h,
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topLeft,
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
                      text: displayName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _remarks,
                style: const TextStyle(
                  fontSize: 12.0,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),
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
          height: 1.1,
        ),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.normal),
          ),
        ],
      ),
    );
  }

  // ── Draggable overlay — fraction-based, no transform matrix ──────────────
  //
  // All positions/sizes stored as fractions (0.0–1.0).
  // Drag deltas are in screen pixels; divide by viewport size → fraction delta.
  // This works correctly regardless of PDFView's internal zoom level.
  //
  Widget _buildDraggableOverlay({
    required double fracX,
    required double fracY,
    required double fracW,
    required double fracH,
    required Widget child,
    required void Function(double fx, double fy) onMove,
    required void Function(double fw, double fh, double fx, double fy) onResize,
    required double aspectRatio, // LOCK RATIO
    Color accentColor = const Color(0xFFCC0000),
    double minFracW = 0.08,
  }) {
    // Convert fractions → screen pixels for Positioned widget
    final left = fracX * _viewportWidth;
    final top = fracY * _viewportHeight;
    final w = fracW * _viewportWidth;
    final h = fracH * _viewportHeight;

    return Positioned(
      left: left - 12,
      top: top - 12,
      child: SizedBox(
        width: w + 24,
        height: h + 24,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Draggable body ──────────────────────────────────────────
            Positioned(
              left: 12,
              top: 12,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  // Convert screen delta → fraction delta
                  final newFx = (fracX + d.delta.dx / _viewportWidth).clamp(
                    0.0,
                    (1.0 - fracW).clamp(0.0, 1.0),
                  );
                  final newFy = (fracY + d.delta.dy / _viewportHeight).clamp(
                    -0.1,
                    1.1,
                  );

                  // Page jump logic
                  if (newFy > 0.96 && _currentPage < _totalPages - 1) {
                    _signaturePage++;
                    _pdfController?.setPage(_signaturePage);
                    onMove(newFx, 0.05);
                  } else if (newFy < 0.04 && _currentPage > 0) {
                    _signaturePage--;
                    _pdfController?.setPage(_signaturePage);
                    onMove(newFx, 0.85);
                  } else {
                    onMove(newFx, newFy.clamp(0.0, 1.0 - fracH));
                  }
                },
                child: Container(
                  width: w,
                  height: h,
                  color: Colors.transparent,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(width: w, height: h, child: child),
                  ),
                ),
              ),
            ),
            // ── Corner handles ──────────────────────────────────────────
            // Bottom-right (simplest for aspect ratio locking)
            _cornerHandle(
              accentColor: accentColor,
              right: 0,
              bottom: 0,
              onPan: (d) {
                final dfw = d.delta.dx / _viewportWidth;
                final newFw = (fracW + dfw).clamp(minFracW, 0.95);
                // Calculate new height based on aspect ratio
                // Ratio = (PixelW) / (PixelH)
                // PixelH = PixelW / Ratio
                // fracH = (PixelW / Ratio) / ViewportH
                final newPixelW = newFw * _viewportWidth;
                final newPixelH = newPixelW / aspectRatio;
                final newFh = (newPixelH / _viewportHeight).clamp(0.02, 0.95);

                onResize(newFw, newFh, fracX, fracY);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _cornerHandle({
    required Color accentColor,
    required GestureDragUpdateCallback onPan,
    double? left,
    double? right,
    double? top,
    double? bottom,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: onPan,
        child: Container(
          width: 24,
          height: 24,
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
          child: const Icon(Icons.open_in_full, size: 12, color: Colors.white),
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
            backgroundColor: Colors.black,
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
                  IconButton(
                    onPressed: isBlocking ? null : _moveToCurrentView,
                    icon: const Icon(
                      Icons.center_focus_weak,
                      color: Colors.white,
                      size: 20,
                    ),
                    tooltip: 'Move signature here',
                  ),
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
                        const Expanded(
                          child: Text(
                            "Drag to move · drag bottom-right corner to resize",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_currentPage != _signaturePage)
                          GestureDetector(
                            onTap: isBlocking ? null : _moveToCurrentView,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                "MOVE SIGNATURE HERE",
                                style: TextStyle(
                                  color: Color(0xFFCC0000),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
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
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_viewportWidth != constraints.maxWidth ||
                            _viewportHeight != constraints.maxHeight) {
                          setState(() {
                            _viewportWidth = constraints.maxWidth;
                            _viewportHeight = constraints.maxHeight;
                          });
                        }
                      });

                      return Stack(
                        children: [
                          // ── PDF viewer ────────────────────────────────
                          Positioned.fill(
                            child: PDFView(
                              filePath: widget.pdfPath,
                              enableSwipe: true,
                              swipeHorizontal: false,
                              autoSpacing: false,
                              pageFling: false,
                              fitPolicy: FitPolicy.BOTH,
                              backgroundColor: Colors.grey.shade200,
                              onViewCreated: (controller) =>
                                  _pdfController = controller,
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

                          // ── Draggable overlays ────────────────────────
                          // Only render these when on the specific signature page
                          if (_isSigningMode &&
                              _currentPage == _signaturePage) ...[
                            // Comment overlay
                            if (_remarks.trim().isNotEmpty)
                              _buildDraggableOverlay(
                                fracX: _cmtFracX,
                                fracY: _cmtFracY,
                                fracW: _cmtFracW,
                                fracH: _cmtFracH,
                                accentColor: const Color(0xFFFFC107),
                                aspectRatio: _cmtAspectRatio,
                                child: _buildCommentWidget(
                                  width: _cmtPixelW,
                                  height: _cmtPixelH,
                                ),
                                onMove: (fx, fy) => setState(() {
                                  _cmtFracX = fx;
                                  _cmtFracY = fy;
                                }),
                                onResize: (fw, fh, fx, fy) => setState(() {
                                  _cmtFracW = fw;
                                  _cmtFracH = fh;
                                  _cmtFracX = fx;
                                  _cmtFracY = fy;
                                }),
                              ),

                            // Signature overlay
                            _buildDraggableOverlay(
                              fracX: _sigFracX,
                              fracY: _sigFracY,
                              fracW: _sigFracW,
                              fracH: _sigFracH,
                              accentColor: const Color(0xFFCC0000),
                              aspectRatio: _sigAspectRatio,
                              child: _buildSignatureContent(
                                width: _sigPixelW,
                                height: _sigPixelH,
                              ),
                              onMove: (fx, fy) => setState(() {
                                _sigFracX = fx;
                                _sigFracY = fy;
                              }),
                              onResize: (fw, fh, fx, fy) => setState(() {
                                _sigFracW = fw;
                                _sigFracH = fh;
                                _sigFracX = fx;
                                _sigFracY = fy;
                              }),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),

                // ── Action bar ────────────────────────────────────────────
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
                              backgroundColor: const Color(0xFF059669),
                              disabledBackgroundColor: Colors.green.withOpacity(
                                0.6,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.check,
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
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
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
          ),

          // ── Off-screen RepaintBoundary layer ─────────────────────────
          // Fixed native size — _captureWidget() always gets real pixels.
          Positioned(
            left: -10000,
            top: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  key: _signatureKey,
                  child: SizedBox(
                    width: 500,
                    height: 130,
                    child: _buildSignatureContent(width: 500, height: 130),
                  ),
                ),
                const SizedBox(height: 8),
                if (_remarks.trim().isNotEmpty)
                  RepaintBoundary(
                    key: _commentKey,
                    child: SizedBox(
                      width: 400,
                      height: 160,
                      child: _buildCommentWidget(width: 400, height: 160),
                    ),
                  ),
              ],
            ),
          ),

          // ── Blocking overlay ──────────────────────────────────────────
          if (isBlocking)
            Positioned.fill(
              child: AbsorbPointer(
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
                              decoration: TextDecoration.none,
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
// RESIZE HANDLE
// ─────────────────────────────────────────────────────────────────────────────

class _ResizeHandle extends StatelessWidget {
  final GestureDragUpdateCallback onPanUpdate;
  final bool isEdge;
  final Color color;

  const _ResizeHandle({
    required this.onPanUpdate,
    this.isEdge = false,
    this.color = const Color(0xFFCC0000),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: onPanUpdate,
      child: isEdge
          ? Container(color: color.withOpacity(0.6))
          : Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const Icon(
                Icons.open_in_full,
                size: 12,
                color: Colors.white,
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PULSING DOTS LOADER
// ─────────────────────────────────────────────────────────────────────────────

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
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => AnimatedBuilder(
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
        ),
      ),
    );
  }
}
