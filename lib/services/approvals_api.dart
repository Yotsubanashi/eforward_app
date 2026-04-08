import 'dart:convert';
import 'package:http/http.dart' as http;

class ApprovalsApi {
  ApprovalsApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String baseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';

  // ─── Fetch Pending Approvals ───────────────────────────────────────────────
  // GET /approvals/pending
  // Params: search, page, limit
  Future<ApprovalsResult> fetchPendingApprovals({
    required String token,
    String? search,
    int? page,
    int? limit,
  }) async {
    final queryParams = <String, String>{};
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (page != null) queryParams['page'] = page.toString();
    if (limit != null) queryParams['limit'] = limit.toString();

    final uri = Uri.parse('$baseUrl/approvals/pending')
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    try {
      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final dynamic decodedBody =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApprovalsResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message: _extractMessage(decodedBody) ?? 'Pending approvals loaded.',
          data: decodedBody is Map<String, dynamic> ? decodedBody : null,
          list: decodedBody is List
              ? decodedBody.cast<Map<String, dynamic>>()
              : decodedBody is Map && decodedBody['data'] is List
                  ? (decodedBody['data'] as List)
                      .cast<Map<String, dynamic>>()
                  : null,
        );
      }

      return ApprovalsResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message: _extractMessage(decodedBody) ?? 'Failed to fetch approvals.',
        data: decodedBody is Map<String, dynamic> ? decodedBody : null,
      );
    } catch (error) {
      return ApprovalsResult(
        isSuccess: false,
        statusCode: 0,
        message: 'Network error: $error',
      );
    }
  }

  // ─── Fetch Single Approval Detail ─────────────────────────────────────────
  // GET /approvals/:id/routing
  Future<ApprovalsResult> fetchApprovalDetail({
    required String token,
    required String id,
  }) async {
    final uri = Uri.parse('$baseUrl/approvals/$id/routing');

    try {
      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final dynamic decodedBody =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApprovalsResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message:
              _extractMessage(decodedBody) ?? 'Approval detail loaded.',
          data: decodedBody is Map<String, dynamic> ? decodedBody : null,
        );
      }

      return ApprovalsResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message:
            _extractMessage(decodedBody) ?? 'Failed to fetch approval detail.',
        data: decodedBody is Map<String, dynamic> ? decodedBody : null,
      );
    } catch (error) {
      return ApprovalsResult(
        isSuccess: false,
        statusCode: 0,
        message: 'Network error: $error',
      );
    }
  }

  // ─── Approve Document ─────────────────────────────────────────────────────
  // POST /approvals/:id/approve
  // Body: FormData: remarks, signatureImage, signaturePlacement
  Future<ApprovalsResult> approveDocument({
    required String token,
    required String id,
    required String remarks,
    required List<int> signatureImageBytes,
    required String signatureImageFileName,
    String? signaturePlacement,
  }) async {
    final uri = Uri.parse('$baseUrl/approvals/$id/approve');

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'application/json'
        ..fields['remarks'] = remarks
        ..files.add(
          http.MultipartFile.fromBytes(
            'signatureImage',
            signatureImageBytes,
            filename: signatureImageFileName,
          ),
        );

      if (signaturePlacement != null && signaturePlacement.isNotEmpty) {
        request.fields['signaturePlacement'] = signaturePlacement;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      final dynamic decodedBody =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApprovalsResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message:
              _extractMessage(decodedBody) ?? 'Document approved successfully.',
          data: decodedBody is Map<String, dynamic> ? decodedBody : null,
        );
      }

      return ApprovalsResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message:
            _extractMessage(decodedBody) ?? 'Failed to approve document.',
        data: decodedBody is Map<String, dynamic> ? decodedBody : null,
      );
    } catch (error) {
      return ApprovalsResult(
        isSuccess: false,
        statusCode: 0,
        message: 'Network error: $error',
      );
    }
  }

  // ─── Request Revision ─────────────────────────────────────────────────────
  // POST /approvals/:id/revision
  // Body: { remarks }
  Future<ApprovalsResult> requestRevision({
    required String token,
    required String id,
    required String remarks,
  }) async {
    final uri = Uri.parse('$baseUrl/approvals/$id/revision');

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'remarks': remarks}),
      );

      final dynamic decodedBody =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApprovalsResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message: _extractMessage(decodedBody) ?? 'Revision requested.',
          data: decodedBody is Map<String, dynamic> ? decodedBody : null,
        );
      }

      return ApprovalsResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message:
            _extractMessage(decodedBody) ?? 'Failed to request revision.',
        data: decodedBody is Map<String, dynamic> ? decodedBody : null,
      );
    } catch (error) {
      return ApprovalsResult(
        isSuccess: false,
        statusCode: 0,
        message: 'Network error: $error',
      );
    }
  }

  // ─── Preview or Download Attached File ───────────────────────────────────
  // GET /upload/document/:file_id
  // responseType: blob (returns raw bytes)
  Future<DocumentFileResult> fetchDocument({
    required String token,
    required String fileId,
  }) async {
    final uri = Uri.parse('$baseUrl/upload/document/$fileId');

    try {
      final response = await _client.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return DocumentFileResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message: 'File loaded.',
          bytes: response.bodyBytes,
          contentType: response.headers['content-type'] ?? 'application/octet-stream',
        );
      }

      return DocumentFileResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message: 'Failed to fetch file.',
      );
    } catch (error) {
      return DocumentFileResult(
        isSuccess: false,
        statusCode: 0,
        message: 'Network error: $error',
      );
    }
  }

  String? _extractMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      final message = body['message'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    return null;
  }

  void dispose() {
    _client.close();
  }
}

// ─── Result Model ─────────────────────────────────────────────────────────────

class ApprovalsResult {
  const ApprovalsResult({
    required this.isSuccess,
    required this.statusCode,
    required this.message,
    this.data,
    this.list,
  });

  final bool isSuccess;
  final int statusCode;
  final String message;
  final Map<String, dynamic>? data;
  final List<Map<String, dynamic>>? list; // for list responses
}

// ─── Document File Result Model ───────────────────────────────────────────────

class DocumentFileResult {
  const DocumentFileResult({
    required this.isSuccess,
    required this.statusCode,
    required this.message,
    this.bytes,
    this.contentType,
  });

  final bool isSuccess;
  final int statusCode;
  final String message;
  final List<int>? bytes;           // raw file bytes (blob)
  final String? contentType;        // e.g. 'application/pdf', 'image/png'
}