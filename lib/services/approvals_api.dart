import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:eforward_app/config/app_env.dart';

class ApprovalsApi {
  static String get _baseUrl => AppEnv.apiBaseUrl;

  Future<List<Map<String, dynamic>>> getDocumentLinks({
    required String token,
    required String routingId,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/routing/$routingId/document-links'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load document links (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, dynamic> ? decoded['data'] : null;

    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  Future<void> requestAttachment({
    required String token,
    required String routingId,
    required String remarks,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/approvals/$routingId/request-attachment'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'remarks': remarks}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Failed to submit attachment request';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          message = decoded['message']?.toString() ?? message;
        }
      } catch (_) {}
      throw Exception(message);
    }
  }
}
