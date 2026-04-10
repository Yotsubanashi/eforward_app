import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class AuthApi {
  AuthApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String baseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';

  Future<AuthLoginResult> login({
    required String email,
    required String password,
  }) async {
    return _post(
      endpoint: '/auth/login',
      body: {'email': email, 'password': password},
      successMessage: 'Login successful.',
      failureMessage: 'Login failed.',
    );
  }

  Future<AuthLoginResult> verifyOtp({
    required String email,
    required String otp,
  }) async {
    return _post(
      endpoint: '/auth/verify-otp',
      body: {'email': email, 'otp': otp},
      successMessage: 'OTP verified successfully.',
      failureMessage: 'OTP verification failed.',
    );
  }

  Future<AuthLoginResult> forgotPassword({required String email}) async {
    return _post(
      endpoint: '/auth/forgotPassword',
      body: {'email': email},
      successMessage: 'Password reset link sent to your email.',
      failureMessage: 'Failed to send password reset link.',
    );
  }

  Future<AuthLoginResult> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    return _post(
      endpoint: '/auth/resetPassword',
      body: {'token': token, 'newPassword': newPassword},
      successMessage: 'Password reset successfully.',
      failureMessage: 'Password reset failed.',
    );
  }

  Future<AuthLoginResult> logout() async {
    return _post(
      endpoint: '/auth/logout',
      body: {},
      successMessage: 'Logout successful.',
      failureMessage: 'Logout failed.',
    );
  }

  Future<AuthLoginResult> resendOtp({required String email}) async {
    return _post(
      endpoint: '/auth/resend-otp',
      body: {'email': email},
      successMessage: 'OTP resent to your email.',
      failureMessage: 'Failed to resend OTP.',
    );
  }

  Future<AuthLoginResult> getMe({String? token}) async {
    final uri = Uri.parse('$baseUrl/auth/me');

    try {
      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (token != null && token.trim().isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      );

      final dynamic decodedBody = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : null;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return AuthLoginResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message: _extractMessage(decodedBody) ?? 'User profile loaded.',
          data: decodedBody is Map<String, dynamic> ? decodedBody : null,
          requiredOTP: false,
        );
      }

      return AuthLoginResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message: _extractMessage(decodedBody) ?? 'Failed to load user profile.',
        data: decodedBody is Map<String, dynamic> ? decodedBody : null,
        requiredOTP: false,
      );
    } catch (error) {
      return AuthLoginResult(
        isSuccess: false,
        statusCode: 0,
        message: 'Network error: $error',
      );
    }
  }

  // ─── Fetch signature ──────────────────────────────────────────────────────
  // API response format:
  // {
  //   "data": {
  //     "base64": "data:image/png;base64,iVBOR...",
  //     "mime_type": "image/png",
  //     "file_name": "signature_A0000939.png"
  //   }
  // }
  Future<SignatureResult> getSignature({required String token}) async {
    final uri = Uri.parse('$baseUrl/upload/signature/image');

    try {
      final response = await _client.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      debugPrint('Signature status: ${response.statusCode}');
      debugPrint(
        'Signature body preview: ${response.body.length > 300 ? response.body.substring(0, 300) : response.body}',
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final dynamic decoded = jsonDecode(response.body);

          if (decoded is Map<String, dynamic>) {
            // ── Extract base64 from data.base64 ──
            final dynamic dataField = decoded['data'];
            String? base64Str;
            String? rawDate;

            if (dataField is Map) {
              base64Str = dataField['base64'] as String?;
              rawDate =
                  dataField['createdAt'] as String? ??
                  dataField['signedAt'] as String? ??
                  dataField['updatedAt'] as String?;
            }

            // Also check top-level keys as fallback
            base64Str ??= decoded['base64'] as String?;
            rawDate ??=
                decoded['createdAt'] as String? ??
                decoded['signedAt'] as String? ??
                decoded['updatedAt'] as String?;

            if (base64Str != null && base64Str.isNotEmpty) {
              // Strip the data URI prefix: "data:image/png;base64,"
              final String pureBase64 = base64Str.contains(',')
                  ? base64Str.split(',').last.trim()
                  : base64Str.trim();

              try {
                final bytes = base64Decode(pureBase64);
                debugPrint(
                  'Signature decoded from base64: ${bytes.length} bytes',
                );
                return SignatureResult(
                  isSuccess: true,
                  statusCode: response.statusCode,
                  message: 'Signature loaded.',
                  imageBytes: bytes,
                  rawDate: rawDate,
                  data: decoded,
                );
              } catch (e) {
                debugPrint('Base64 decode error: $e');
              }
            }

            // Fallback: check for a URL field
            final String? imageUrl = _extractImageUrl(decoded);
            return SignatureResult(
              isSuccess: true,
              statusCode: response.statusCode,
              message: 'Signature loaded.',
              imageUrl: imageUrl,
              rawDate: rawDate,
              data: decoded,
            );
          }
        } catch (e) {
          debugPrint('JSON parse error: $e');
          // If not JSON but has bytes, treat as raw image
          if (response.bodyBytes.isNotEmpty) {
            return SignatureResult(
              isSuccess: true,
              statusCode: response.statusCode,
              message: 'Signature loaded.',
              imageBytes: response.bodyBytes,
            );
          }
        }
      }

      debugPrint('Signature fetch failed: ${response.statusCode}');
      return SignatureResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message: 'Failed to load signature. Status: ${response.statusCode}',
      );
    } catch (error) {
      debugPrint('Signature error: $error');
      return SignatureResult(
        isSuccess: false,
        statusCode: 0,
        message: 'Network error: $error',
      );
    }
  }

  String? _extractImageUrl(Map<String, dynamic> body) {
    final dynamic data = body['data'];
    if (data is Map) {
      return data['imageUrl'] as String? ??
          data['url'] as String? ??
          data['filePath'] as String? ??
          data['file_path'] as String?;
    }
    return body['imageUrl'] as String? ??
        body['url'] as String? ??
        body['filePath'] as String? ??
        body['file_path'] as String?;
  }

  // ─── Upload signature image to API ────────────────────────────────────────
  // POST /api/upload/signature
  // Field name: "signature"
  // Response: { "message": "...", "data": { "file_path": "...", "file_name": "...", "mime_type": "..." } }
  Future<AuthLoginResult> uploadSignature({
    required String token,
    required List<int> imageBytes,
    required String fileName,
  }) async {
    final uri = Uri.parse('$baseUrl/upload/signature');

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'application/json'
        ..files.add(
          http.MultipartFile.fromBytes(
            'signature', // FormData field name confirmed by API
            imageBytes,
            filename: fileName,
            contentType: MediaType(
              'image',
              'png',
            ), // 👈 CRITICAL: Specify content type
          ),
        );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('Upload status: ${response.statusCode}');
      debugPrint('Upload response: ${response.body}');

      final dynamic decodedBody = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : null;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return AuthLoginResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message: _extractMessage(decodedBody) ?? 'Signature uploaded.',
          data: decodedBody is Map<String, dynamic> ? decodedBody : null,
          requiredOTP: false,
        );
      }

      return AuthLoginResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message: _extractMessage(decodedBody) ?? 'Signature upload failed.',
        data: decodedBody is Map<String, dynamic> ? decodedBody : null,
        requiredOTP: false,
      );
    } catch (error) {
      return AuthLoginResult(
        isSuccess: false,
        statusCode: 0,
        message: 'Network error: $error',
      );
    }
  }

  Future<AuthLoginResult> _post({
    required String endpoint,
    required Map<String, dynamic> body,
    required String successMessage,
    required String failureMessage,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      );

      final dynamic decodedBody = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : null;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic>? bodyMap =
            decodedBody is Map<String, dynamic> ? decodedBody : null;
        return AuthLoginResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message: _extractMessage(decodedBody) ?? successMessage,
          data: bodyMap,
          requiredOTP: bodyMap?['requiredOTP'] ?? false,
        );
      }

      final Map<String, dynamic>? bodyMap = decodedBody is Map<String, dynamic>
          ? decodedBody
          : null;
      return AuthLoginResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message: _extractMessage(decodedBody) ?? failureMessage,
        data: bodyMap,
        requiredOTP: bodyMap?['requiredOTP'] ?? false,
      );
    } catch (error) {
      return AuthLoginResult(
        isSuccess: false,
        statusCode: 0,
        message: 'Network error: $error',
        requiredOTP: false,
      );
    }
  }

  String? _extractMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      final message = body['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  void dispose() {
    _client.close();
  }
}

class SignatureResult {
  const SignatureResult({
    required this.isSuccess,
    required this.statusCode,
    required this.message,
    this.imageBytes,
    this.imageUrl,
    this.rawDate,
    this.data,
  });

  final bool isSuccess;
  final int statusCode;
  final String message;
  final List<int>? imageBytes;
  final String? imageUrl;
  final String? rawDate;
  final dynamic data;
}

class AuthLoginResult {
  const AuthLoginResult({
    required this.isSuccess,
    required this.statusCode,
    required this.message,
    this.data,
    this.requiredOTP = false,
  });

  final bool isSuccess;
  final int statusCode;
  final String message;
  final Map<String, dynamic>? data;
  final bool requiredOTP;
}
