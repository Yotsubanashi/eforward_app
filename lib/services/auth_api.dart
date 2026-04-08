import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

class AuthApi {
  AuthApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String baseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';
  static const String localBaseUrl = 'http://localhost:3000';

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
        );
      }

      return AuthLoginResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message:
            _extractMessage(decodedBody) ?? 'Failed to load user profile.',
        data: decodedBody is Map<String, dynamic> ? decodedBody : null,
      );
    } catch (error) {
      return AuthLoginResult(
        isSuccess: false,
        statusCode: 0,
        message: 'Network error: $error',
      );
    }
  }

  // ─── Fetch signature — returns bytes (blob) or JSON with URL ─────────────
  Future<SignatureResult> getSignature({required String token}) async {
    final uri = Uri.parse('$baseUrl/upload/signature/image');

    try {
      final response = await _client.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': '*/*',
        },
      );

      debugPrint('Signature status: ${response.statusCode}');
      debugPrint('Signature content-type: ${response.headers['content-type']}');
      debugPrint('Signature bytes: ${response.bodyBytes.length}');
      debugPrint('Signature body preview: ${response.body.length > 300 ? response.body.substring(0, 300) : response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final contentType = response.headers['content-type'] ?? '';

        // Case 1: Image blob
        if (contentType.contains('image/') ||
            contentType.contains('octet-stream') ||
            contentType.contains('binary')) {
          debugPrint('Got image blob ${response.bodyBytes.length} bytes');
          return SignatureResult(
            isSuccess: true,
            statusCode: response.statusCode,
            message: 'Signature image loaded.',
            imageBytes: response.bodyBytes,
          );
        }

        // Case 2: Try JSON
        try {
          final dynamic decodedBody = jsonDecode(response.body);
          debugPrint('Signature JSON: $decodedBody');

          if (decodedBody is Map<String, dynamic>) {
            // Print every key
            debugPrint('=== SIGNATURE JSON KEYS ===');
            decodedBody.forEach((key, value) {
              debugPrint('SIGN KEY: $key  =>  VALUE: $value');
              if (value is Map) {
                value.forEach((k, v) => debugPrint('  NESTED: $k  =>  $v'));
              }
            });
            debugPrint('===========================');
            final imageUrl = decodedBody['imageUrl']
                ?? decodedBody['url']
                ?? decodedBody['signatureUrl']
                ?? decodedBody['image']
                ?? decodedBody['filePath']
                ?? decodedBody['path']
                ?? decodedBody['signature']
                ?? (decodedBody['data'] is Map ? decodedBody['data']['imageUrl'] : null)
                ?? (decodedBody['data'] is Map ? decodedBody['data']['url'] : null)
                ?? (decodedBody['data'] is Map ? decodedBody['data']['filePath'] : null)
                ?? '';

            final rawDate = decodedBody['signedAt']
                ?? decodedBody['createdAt']
                ?? decodedBody['date']
                ?? decodedBody['updatedAt']
                ?? (decodedBody['data'] is Map ? decodedBody['data']['createdAt'] : null)
                ?? (decodedBody['data'] is Map ? decodedBody['data']['signedAt'] : null)
                ?? '';

            debugPrint('imageUrl: $imageUrl');
            debugPrint('rawDate: $rawDate');

            return SignatureResult(
              isSuccess: true,
              statusCode: response.statusCode,
              message: 'Signature loaded.',
              imageUrl: imageUrl is String && imageUrl.isNotEmpty ? imageUrl : null,
              rawDate: rawDate is String && rawDate.isNotEmpty ? rawDate : null,
              data: decodedBody,
            );
          }
        } catch (_) {
          if (response.bodyBytes.isNotEmpty) {
            debugPrint('Not JSON, raw bytes: ${response.bodyBytes.length}');
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
        message: 'Network error: \$error',
      );
    }
  }

    // ─── Upload signature image to API ────────────────────────────────────────
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
            'signature', // 👈 FormData field name
            imageBytes,
            filename: fileName,
          ),
        );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      final dynamic decodedBody = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : null;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return AuthLoginResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message: _extractMessage(decodedBody) ?? 'Signature uploaded.',
          data: decodedBody is Map<String, dynamic> ? decodedBody : null,
        );
      }

      return AuthLoginResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message:
            _extractMessage(decodedBody) ?? 'Signature upload failed.',
        data: decodedBody is Map<String, dynamic> ? decodedBody : null,
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
        return AuthLoginResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message: _extractMessage(decodedBody) ?? successMessage,
          data: decodedBody is Map<String, dynamic> ? decodedBody : null,
        );
      }

      return AuthLoginResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message: _extractMessage(decodedBody) ?? failureMessage,
        data: decodedBody is Map<String, dynamic> ? decodedBody : null,
      );
    } catch (error) {
      return AuthLoginResult(
        isSuccess: false,
        statusCode: 0,
        message: 'Network error: $error',
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
  final List<int>? imageBytes;   // raw image bytes if blob
  final String? imageUrl;        // URL if JSON response
  final String? rawDate;         // date string from API
  final dynamic data;            // full JSON response
}

class AuthLoginResult {
  const AuthLoginResult({
    required this.isSuccess,
    required this.statusCode,
    required this.message,
    this.data,
  });

  final bool isSuccess;
  final int statusCode;
  final String message;
  final Map<String, dynamic>? data;
}