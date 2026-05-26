import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/config/app_env.dart';

class AuthApi {
  AuthApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static String get baseUrl => AppEnv.apiBaseUrl;

  Future<AuthLoginResult> login({
    required String email,
    required String password,
  }) async {
    return _post(
      endpoint: '/auth/mobile-login',
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

  Future<AuthLoginResult> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final String accessToken = prefs.getString('access_token') ?? '';

    // Get employee_id from storage directly or parse from user_data
    String? employeeId = prefs.getString('employee_id');
    if (employeeId == null || employeeId.isEmpty) {
      final userDataStr = prefs.getString('user_data');
      if (userDataStr != null) {
        try {
          final userData = jsonDecode(userDataStr);
          final user = userData['user'] is Map ? userData['user'] : userData;
          employeeId =
              user['id']?.toString() ??
              user['employee_id']?.toString() ??
              user['employeeId']?.toString();
        } catch (e) {
          debugPrint('Error parsing user_data for logout: $e');
        }
      }
    }

    String? fcmToken = prefs.getString('fcm_token_cached');
    final deviceInfo = await _getDeviceInfo();

    final Map<String, dynamic> payload = {
      'employee_id': employeeId,
      'fcm_token': fcmToken,
      'device_id': deviceInfo['deviceId'],
      'device_model': deviceInfo['deviceModel'],
      'platform': Platform.isIOS ? 'ios' : 'android',
    };

    debugPrint('Sending logout payload: ${jsonEncode(payload)}');

    final uri = Uri.parse('$baseUrl/auth/logout');
    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      final dynamic decodedBody =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;

      // Always clear local session even if backend call fails
      await clearSession();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return AuthLoginResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message: _extractMessage(decodedBody) ?? 'Logout successful.',
          data: decodedBody is Map<String, dynamic> ? decodedBody : null,
        );
      }

      return AuthLoginResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message: _extractMessage(decodedBody) ?? 'Logout failed.',
        data: decodedBody is Map<String, dynamic> ? decodedBody : null,
      );
    } catch (error) {
      // Still clear local session on error
      await clearSession();
      return AuthLoginResult(
        isSuccess: false,
        statusCode: 0,
        message: 'Network error: $error',
      );
    }
  }

  Future<Map<String, String>> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      return {
        'deviceId': info.id,
        'deviceModel': '${info.brand} ${info.model}',
      };
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      return {
        'deviceId': info.identifierForVendor ?? 'unknown',
        'deviceModel': info.utsname.machine,
      };
    }
    return {'deviceId': 'unknown', 'deviceModel': 'unknown'};
  }

  Future<AuthLoginResult> refresh({required String token}) async {
    final uri = Uri.parse('$baseUrl/auth/refresh');

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'refreshToken': token}),
      );

      final dynamic decodedBody = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : null;

      debugPrint('Refresh token status: ${response.statusCode}');
      debugPrint('Refresh token response: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic>? bodyMap =
            decodedBody is Map<String, dynamic> ? decodedBody : null;
        return AuthLoginResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message:
              _extractMessage(decodedBody) ?? 'Token refreshed successfully.',
          data: bodyMap,
          requiredOTP: false,
        );
      }

      final Map<String, dynamic>? bodyMap = decodedBody is Map<String, dynamic>
          ? decodedBody
          : null;
      return AuthLoginResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message: _extractMessage(decodedBody) ?? 'Token refresh failed.',
        data: bodyMap,
        requiredOTP: false,
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

  Future<AuthLoginResult> refreshWithStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    final storedRefreshToken = prefs.getString('refresh_token')?.trim() ?? '';

    if (storedRefreshToken.isEmpty) {
      await clearSession();
      return const AuthLoginResult(
        isSuccess: false,
        statusCode: 401,
        message: 'Session expired. Please login again.',
      );
    }

    final refreshResult = await refresh(token: storedRefreshToken);

    if (refreshResult.isSuccess) {
      final newAccessToken =
          refreshResult.data?['accessToken'] ??
          refreshResult.data?['access_token'] ??
          refreshResult.data?['token'];
      final newRefreshToken =
          refreshResult.data?['refreshToken'] ??
          refreshResult.data?['refresh_token'];

      if (newAccessToken is String && newAccessToken.trim().isNotEmpty) {
        await prefs.setString('access_token', newAccessToken.trim());
      }
      if (newRefreshToken is String && newRefreshToken.trim().isNotEmpty) {
        await prefs.setString('refresh_token', newRefreshToken.trim());
      }

      return refreshResult;
    }

    // If backend marks refresh token invalid/inactive/unauthorized,
    // force local logout to keep session in sync with backend policy.
    if (refreshResult.statusCode == 401 || refreshResult.statusCode == 403) {
      await clearSession();
      return const AuthLoginResult(
        isSuccess: false,
        statusCode: 401,
        message: 'Session expired. Please login again.',
      );
    }

    return refreshResult;
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_data');
    await prefs.remove('employee_id');
    await prefs.remove('fcm_token_cached');
    debugPrint('🧹 Local session and FCM cache cleared');
  }

  Future<AuthLoginResult> resendOtp({required String email}) async {
    return _post(
      endpoint: '/auth/resend-otp',
      body: {'email': email},
      successMessage: 'OTP resent to your email.',
      failureMessage: 'Failed to resend OTP.',
    );
  }

  Future<AuthLoginResult> verifyResetToken({required String token}) async {
    return _post(
      endpoint: '/auth/verifyToken',
      body: {'token': token},
      successMessage: 'Reset token is valid.',
      failureMessage: 'Invalid or expired reset token.',
    );
  }

  Future<AuthLoginResult> resetPasswordWithToken({
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

  // ─── Update Profile ───────────────────────────────────────────────────────
  // PUT /api/users/{employee_id}
  Future<AuthLoginResult> updateProfile({
    required String token,
    required String employeeId,
    required String fname,
    required String mname,
    required String lname,
  }) async {
    final uri = Uri.parse('$baseUrl/users/$employeeId');

    try {
      final response = await _client.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'fname': fname, 'mname': mname, 'lname': lname}),
      );

      final dynamic decodedBody = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : null;

      debugPrint('updateProfile status: ${response.statusCode}');
      debugPrint('updateProfile response: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return AuthLoginResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message: _extractMessage(decodedBody) ?? 'Profile updated.',
          data: decodedBody is Map<String, dynamic> ? decodedBody : null,
        );
      }

      return AuthLoginResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message: _extractMessage(decodedBody) ?? 'Profile update failed.',
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

  // ─── Change Password ──────────────────────────────────────────────────────
  // POST /api/auth/changePassword
  // Payload: { currentPassword, newPassword, confirmPassword }
  Future<AuthLoginResult> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/changePassword');

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'currentPassword': currentPassword,
          'newPassword': newPassword,
          'confirmPassword': confirmPassword,
        }),
      );

      final dynamic decodedBody = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : null;

      debugPrint('changePassword status: ${response.statusCode}');
      debugPrint('changePassword response: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return AuthLoginResult(
          isSuccess: true,
          statusCode: response.statusCode,
          message:
              _extractMessage(decodedBody) ?? 'Password changed successfully.',
          data: decodedBody is Map<String, dynamic> ? decodedBody : null,
        );
      }

      return AuthLoginResult(
        isSuccess: false,
        statusCode: response.statusCode,
        message: _extractMessage(decodedBody) ?? 'Password change failed.',
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

  // ─── Fetch signature ──────────────────────────────────────────────────────
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

            base64Str ??= decoded['base64'] as String?;
            rawDate ??=
                decoded['createdAt'] as String? ??
                decoded['signedAt'] as String? ??
                decoded['updatedAt'] as String?;

            if (base64Str != null && base64Str.isNotEmpty) {
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

  // ─── Upload signature ─────────────────────────────────────────────────────
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
            'signature',
            imageBytes,
            filename: fileName,
            contentType: MediaType('image', 'png'),
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
