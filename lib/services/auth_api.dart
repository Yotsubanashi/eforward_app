import 'dart:convert';

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
        message: _extractMessage(decodedBody) ?? 'Failed to load user profile.',
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
