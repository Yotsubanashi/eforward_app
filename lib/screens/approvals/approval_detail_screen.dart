import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eforward_app/config/app_env.dart';
import 'package:eforward_app/utils/manila_time.dart';
import 'package:eforward_app/screens/approvals/excel_viewer/excel_viewer_screen.dart';
import 'package:eforward_app/screens/approvals/pdf_signer/pdf_signer_screen.dart';
import 'package:eforward_app/services/api/approvals_api.dart';
import 'package:eforward_app/services/session_service.dart';
import 'package:eforward_app/widgets/app_snackbar.dart';
import 'package:eforward_app/widgets/eforward_app_bar.dart';
import 'package:eforward_app/widgets/loading_overlay.dart';
import 'package:eforward_app/widgets/section_label.dart';
import 'package:eforward_app/widgets/status_pill.dart';

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

  // Identity of the logged-in user, used to find THIS user's step in the
  // approval workflow so the action buttons hide once they've already signed.
  final Set<String> _currentUserIds = {};
  String _currentUserName = '';
  // True when the logged-in user's own approval step is already actioned
  // (approved/rejected). The overall routing stays PENDING until every step is
  // done, so we must not rely on the routing status alone to show the buttons.
  bool _currentUserActed = false;
  final TextEditingController _revisionRemarksController =
      TextEditingController();
  final TextEditingController _attachmentRemarksController =
      TextEditingController();

  String get _baseUrl => AppEnv.apiBaseUrl;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserIdentity();
    _fetchApprovalDetail();
  }

  // Read the logged-in user's ids and full name from the persisted session so
  // we can match them against an entry in the approval workflow (`details`).
  Future<void> _loadCurrentUserIdentity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user_data');
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final user = SessionService.normalizeUser(decoded);

      final ids = <String>{};
      for (final key in ['id', 'employee_id', 'employeeId', 'emp_id']) {
        final val = user[key];
        if (val != null && val.toString().trim().isNotEmpty) {
          ids.add(val.toString().trim());
        }
      }
      final name = _joinName(user['fname'], user['mname'], user['lname']);

      _currentUserIds
        ..clear()
        ..addAll(ids);
      _currentUserName = name;
      if (mounted) setState(() => _currentUserActed = _computeCurrentUserActed());
    } catch (e) {
      debugPrint('Load current user identity error: $e');
    }
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
                            child: const Text(
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
    HapticFeedback.mediumImpact();
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
                            child: const Text(
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
      AppSnackbar.error(context, 'Please enter remarks');
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
        AppSnackbar.success(
          context,
          'Revision request sent successfully',
          duration: const Duration(seconds: 2),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
      } else {
        String message = 'Failed to submit revision request';
        try {
          message = jsonDecode(response.body)['message'] ?? message;
        } catch (_) {}
        setState(() => _isSubmittingRevision = false);
        AppSnackbar.error(context, message);
      }
    } catch (e) {
      setState(() => _isSubmittingRevision = false);
      AppSnackbar.error(context, 'Error: $e');
    }
  }

  Future<void> _submitRequestAttachment(BuildContext dialogContext) async {
    final remarks = _attachmentRemarksController.text.trim();
    if (remarks.isEmpty) {
      AppSnackbar.error(context, 'Please enter remarks');
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
      AppSnackbar.success(
        context,
        'Attachment request sent successfully',
        duration: const Duration(seconds: 2),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _isSubmittingAttachmentRequest = false);
      AppSnackbar.error(context, 'Error: $e');
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
            _currentUserActed = _computeCurrentUserActed();
          });
          await _loadPdfFromApi(decoded);
          await _fetchDocumentLinks();
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingDetail = false;
            _documentNotFound = true;
          });
          await _fetchDocumentLinks();
        }
      }
    } catch (e) {
      debugPrint('Approval detail error: $e');
      if (mounted) {
        setState(() {
          _isLoadingDetail = false;
          _documentNotFound = true;
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

    if (!mounted) return;
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
    if (!mounted) return;
    setState(() {
      _documentNotFound = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      final fileId = _extractFileId(detailData);
      if (fileId == null || fileId.isEmpty) {
        if (mounted) {
          setState(() {
            _documentNotFound = true;
          });
        }
        return;
      }

      // Cache on disk keyed by fileId AND a version token derived from the
      // file's last-updated metadata. The SIGNED file is REGENERATED every time
      // an approver signs, and the backend may reuse the same file_id — so a
      // cache keyed on fileId alone would keep serving the pre-signature copy
      // and the newest signature would be missing on the phone (it still shows
      // correctly on the web, which never caches). Folding the version token
      // into the filename busts the cache whenever the file changes. When the
      // downloadable file is a SIGNED file and NO version token is available, we
      // skip the cache entirely and always re-download, so a freshly signed
      // document is never shown stale.
      final downloadable = _getDownloadableFile();
      final isSignedFile =
          downloadable?['file_type']?.toString().toUpperCase() == 'SIGNED';
      final versionToken = _getFileVersionToken(downloadable);

      final dir = await getTemporaryDirectory();
      final fileName = _getFileName();
      final fileExtension = _getFileExtension(fileName);
      final ext = fileExtension.isNotEmpty ? '.$fileExtension' : '.pdf';
      final cachedFileName =
          'doc_$fileId${versionToken.isNotEmpty ? '_$versionToken' : ''}$ext';
      final cachedFile = File('${dir.path}/$cachedFileName');

      // Only trust the on-disk cache when it can't go stale: either the key is
      // version-pinned, or the file isn't a (mutable) SIGNED file.
      final canUseCache = versionToken.isNotEmpty || !isSignedFile;

      if (canUseCache &&
          await cachedFile.exists() &&
          await cachedFile.length() > 0) {
        debugPrint('Using cached document for file $fileId ($cachedFileName)');
        if (mounted) {
          setState(() {
            _localPdfPath = cachedFile.path;
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
        await cachedFile.writeAsBytes(response.bodyBytes);
        if (mounted) {
          setState(() {
            _localPdfPath = cachedFile.path;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _documentNotFound = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Document fetch error: $e');
      if (mounted) {
        setState(() {
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

  // A short, filesystem-safe token that changes whenever the file's content
  // changes, taken from whatever "last updated" metadata the backend provides.
  // Used to version the on-disk PDF cache so a re-signed document busts it.
  String _getFileVersionToken(Map<dynamic, dynamic>? file) {
    if (file == null) return '';
    for (final key in [
      'updated_at',
      'date_updated',
      'updatedAt',
      'date_modified',
      'modified_at',
      'last_modified',
      'version',
      'revision',
      'date_created',
      'created_at',
    ]) {
      final val = file[key];
      if (val != null &&
          val.toString().trim().isNotEmpty &&
          val.toString() != 'null') {
        return val.toString().replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      }
    }
    return '';
  }

  // Future<void> _loadPdfLocal() async {
  //   try {
  //     final byteData = await rootBundle.load('assets/documents/sample.pdf');
  //     final dir = await getTemporaryDirectory();
  //     final file = File('${dir.path}/sample.pdf');
  //     await file.writeAsBytes(byteData.buffer.asUint8List());
  //     if (mounted) {
  //       setState(() {
  //         _localPdfPath = file.path;
  //         _isLoadingPdf = false;
  //       });
  //     }
  //   } catch (e) {
  //     if (mounted) setState(() => _isLoadingPdf = false);
  //   }
  // }

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
          AppSnackbar.error(
            context,
            'Storage permission denied. Cannot save file.',
          );
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';

      if (token.isEmpty) {
        if (mounted) {
          AppSnackbar.error(context, 'Session expired. Please login again.');
        }
        return;
      }

      if (fileId.isEmpty) {
        if (mounted) {
          AppSnackbar.error(context, 'Unable to download: File ID not found');
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
            AppSnackbar.error(context, 'Unable to determine save location');
          }
          return;
        }

        if (!await dir.exists()) await dir.create(recursive: true);

        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);

        if (mounted) {
          AppSnackbar.success(
            context,
            'File downloaded to Downloads folder: $fileName',
            duration: const Duration(seconds: 3),
          );
          await Future.delayed(const Duration(milliseconds: 500));
          await OpenFile.open(file.path);
        }
      } else {
        if (mounted) {
          AppSnackbar.error(context, 'Download failed: ${response.statusCode}');
        }
      }
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        AppSnackbar.error(context, 'Error downloading file: $e');
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

      AppSnackbar.error(
        context,
        'Unable to open ${_getFileTypeDisplayName(fileName)}. '
        'Please install a compatible viewer app.',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, 'Error opening file: $e');
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
          AppSnackbar.error(
            context,
            'Unable to view attachment: File ID not found',
          );
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';

      if (token.isEmpty) {
        if (mounted) {
          AppSnackbar.error(context, 'Session expired. Please login again.');
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
          AppSnackbar.error(
            context,
            'Failed to load attachment: ${response.statusCode}',
          );
        }
      }
    } catch (e) {
      debugPrint('Attachment view error: $e');
      if (mounted) {
        AppSnackbar.error(context, 'Error opening attachment: $e');
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

  DateTime? _parseApiDate(String raw) => ManilaTime.parse(raw);

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

    HapticFeedback.mediumImpact();
    final hasSignature = await _hasUploadedOrSavedSignature();
    if (!mounted) return;

    if (!hasSignature) {
      AppSnackbar.error(
        context,
        'No signature uploaded. Please upload/create one first.',
      );
      return;
    }

    setState(() => _isApproving = true);
    // Open the document in VIEW mode first: the reviewer can zoom and move
    // between pages, then tap SIGN (top-right) to lock onto the current page
    // and place the signature. (Previously this jumped straight into signing
    // mode, which skipped review and pinned signing to page 1.)
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
    if (!mounted) return;
    setState(() => _isApproving = false);
    // Re-pull the routing so that, if this user just signed, the action buttons
    // disappear and the freshly signed document (not a stale cache) is loaded.
    await _fetchApprovalDetail();
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
    // Even while the overall routing is still PENDING (later approvers haven't
    // signed yet), the CURRENT user must not see Approve / Request Revision once
    // their own step is done — re-approving only triggers a backend
    // "not authorized / not your turn" error.
    if (_currentUserActed) return false;
    return _getStatus() == 'PND';
  }

  // The per-approver workflow rows returned by the routing endpoint.
  List<Map<String, dynamic>> _getDetailsList() {
    final data = _detail?['data'] ?? _detail;
    if (data is Map) {
      final details = data['details'];
      if (details is List) {
        return details.whereType<Map<String, dynamic>>().toList();
      }
    }
    return [];
  }

  String _joinName(dynamic first, dynamic middle, dynamic last) {
    return [first, middle, last]
        .map((p) => p?.toString().trim() ?? '')
        .where((p) => p.isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // The approver's display name for a workflow row, pulled from whichever shape
  // the backend uses (flat fname/lname, a nested person object, or a name key).
  String _entryApproverName(Map<String, dynamic> entry) {
    final direct = _joinName(entry['fname'], entry['mname'], entry['lname']);
    if (direct.isNotEmpty) return direct;
    for (final key in [
      'emp',
      'employee',
      'user',
      'approver',
      'signatory',
      'reviewer',
      'to_emp',
      'to_user',
    ]) {
      final v = entry[key];
      if (v is Map) {
        final n = _joinName(v['fname'], v['mname'], v['lname']);
        if (n.isNotEmpty) return n;
        final full = v['name'] ?? v['full_name'] ?? v['fullname'];
        if (full != null && full.toString().trim().isNotEmpty) {
          return full.toString().trim();
        }
      }
    }
    final full =
        entry['approver_name'] ?? entry['name'] ?? entry['full_name'];
    if (full != null && full.toString().trim().isNotEmpty) {
      return full.toString().trim();
    }
    return '';
  }

  // Employee/user ids referenced by a workflow row, for matching the logged-in
  // user. Only id-bearing keys tied to a person are considered.
  Set<String> _entryApproverIds(Map<String, dynamic> entry) {
    final ids = <String>{};
    void addFrom(Map map) {
      map.forEach((key, value) {
        final k = key.toString().toLowerCase();
        if (value is Map) {
          if (k.contains('emp') ||
              k.contains('user') ||
              k.contains('approver') ||
              k.contains('signatory') ||
              k.contains('reviewer')) {
            final id = value['id'] ??
                value['employee_id'] ??
                value['emp_id'] ??
                value['user_id'];
            if (id != null && id.toString().trim().isNotEmpty) {
              ids.add(id.toString().trim());
            }
          }
          return;
        }
        if (value == null) return;
        final v = value.toString().trim();
        if (v.isEmpty) return;
        final isPersonId = k.contains('id') &&
            (k.contains('emp') ||
                k.contains('user') ||
                k.contains('approver') ||
                k.contains('signatory') ||
                k.contains('reviewer'));
        if (isPersonId) ids.add(v);
      });
    }

    addFrom(entry);
    return ids;
  }

  // The workflow row that belongs to the logged-in user, if any.
  Map<String, dynamic>? _currentUserDetail() {
    final details = _getDetailsList();
    if (details.isEmpty) return null;
    final myName = _currentUserName.toLowerCase();
    for (final entry in details) {
      if (_currentUserIds.isNotEmpty &&
          _entryApproverIds(entry).any(_currentUserIds.contains)) {
        return entry;
      }
      if (myName.isNotEmpty) {
        final n = _entryApproverName(entry).toLowerCase();
        if (n.isNotEmpty && n == myName) return entry;
      }
    }
    return null;
  }

  // True when the logged-in user's own step is already approved/rejected.
  // Returns false when the user's step can't be identified, so we fall back to
  // the routing-status behavior instead of hiding the buttons incorrectly.
  bool _computeCurrentUserActed() {
    final entry = _currentUserDetail();
    if (entry == null) return false;
    final status = entry['status']?.toString().toUpperCase().trim() ?? '';
    if (status.startsWith('APP') ||
        status == 'APV' ||
        status.startsWith('REJ') ||
        status == 'REJECTED') {
      return true;
    }
    final actionDate = entry['action_date']?.toString().trim() ?? '';
    if (actionDate.isNotEmpty && actionDate != 'null') return true;
    return false;
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                index == 0 ? Icons.attach_file_rounded : Icons.link_rounded,
                size: 13,
                color: isSelected ? const Color(0xFFCC0000) : Colors.black38,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFFCC0000)
                        : Colors.black45,
                    letterSpacing: 0.3,
                  ),
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
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF4F5F7),
          appBar: const EForwardAppBar(
            title: "APPROVAL DETAILS",
            backgroundColor: Colors.white,
            showBrand: false,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusPill(status: _getStatus()),
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
                      const SectionLabel("DOCUMENT INFORMATION"),
                      const SizedBox(height: 16),
                      if (_isLoadingDetail)
                        const SizedBox.shrink()
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
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel("DOCUMENT TO SIGN"),
                      const SizedBox(height: 14),
                      if (_documentNotFound)
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
                                color: const Color(
                                  0xFFCC0000,
                                ).withOpacity(0.08),
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
                      const SectionLabel("SUPPORTING DOCUMENTS"),
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
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black45,
                            ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                          _getFileTypeDisplayName(
                                            name.toString(),
                                          ),
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
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black45,
                            ),
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
                                                padding:
                                                    const EdgeInsets.symmetric(
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
                                                        color: Color(
                                                          0xFFCC0000,
                                                        ),
                                                        size: 16,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Text(
                                                        fileName.toString(),
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Color(
                                                            0xFF1A1A1A,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    GestureDetector(
                                                      onTap: () =>
                                                          _viewAttachment(file),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              7,
                                                            ),
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
                                                          Icons
                                                              .visibility_outlined,
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
                        const SectionLabel("TAKE ACTION"),
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
                                    (_isSubmittingRevision ||
                                        _localPdfPath == null)
                                    ? null
                                    : _handleApproveTap,
                                icon: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                label: const Text(
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
        ),
        if (_isLoadingDetail || _isApproving) const LoadingOverlay(),
      ],
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
