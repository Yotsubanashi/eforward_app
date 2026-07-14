import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:eforward_app/config/app_env.dart';
import 'package:eforward_app/constants/api_endpoints.dart';
import 'package:eforward_app/constants/shared_prefs_keys.dart';
import 'package:eforward_app/utils/device_info_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FCMTokenService {
  static String get _baseUrl => AppEnv.apiBaseUrl;
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Registers the current device FCM token to your SQL Backend.
  /// This supports multiple devices per employee_id.
  /// Returns `true` only when the backend confirms the token was saved.
  static Future<bool> registerToken(String employeeId) async {
    try {
      if (employeeId.isEmpty) return false;

      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(SharedPrefsKeys.accessToken) ?? '';

      String? token = await _messaging.getToken();
      if (token == null) {
        debugPrint('❌ Could not get FCM token');
        return false;
      }

      // Cache token locally for logout cleanup
      await prefs.setString(SharedPrefsKeys.fcmTokenCached, token);

      final deviceInfo = await DeviceInfoUtil.current();

      // JSON Payload na match sa SQL Columns natin
      final Map<String, dynamic> payload = {
        'employee_id': employeeId,
        'fcm_token': token,
        'device_id': deviceInfo['deviceId'],
        'device_model': deviceInfo['deviceModel'],
        'platform': Platform.isIOS ? 'ios' : 'android',
      };

      final response = await http.post(
        Uri.parse('$_baseUrl${ApiEndpoints.fcmToken}'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );

      final bool saved =
          response.statusCode >= 200 && response.statusCode < 300;

      if (saved) {
        debugPrint('✅ FCM Token saved to SQL (Multi-Device) for: $employeeId');
      } else {
        debugPrint(
          '⚠️ SQL Backend Error (${response.statusCode}): ${response.body}',
        );
      }

      // Listen for token refreshes (auto-update if Google changes the token)
      _messaging.onTokenRefresh.listen((newToken) async {
        await registerToken(employeeId);
      });

      return saved;
    } catch (e) {
      debugPrint('❌ Error syncing FCM token to SQL: $e');
      return false;
    }
  }

  /// Removes only the current device's token from SQL on logout.
  static Future<void> removeToken(String employeeId) async {
    try {
      if (employeeId.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(SharedPrefsKeys.accessToken) ?? '';

      String? token = await _messaging.getToken();
      token ??= prefs.getString(SharedPrefsKeys.fcmTokenCached);

      if (token != null) {
        final deviceInfo = await DeviceInfoUtil.current();

        // Match the registration payload for identification
        final Map<String, dynamic> payload = {
          'employee_id': employeeId,
          'fcm_token': token,
          'device_id': deviceInfo['deviceId'],
          'device_model': deviceInfo['deviceModel'],
          'platform': Platform.isIOS ? 'ios' : 'android',
        };

        // I-delete lang ang entry na match ang employee_id AT fcm_token.
        // Wrapped separately so a network failure here still lets us
        // invalidate the token on the device below.
        try {
          final response = await http.delete(
            Uri.parse('$_baseUrl${ApiEndpoints.fcmToken}'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          );

          if (response.statusCode >= 200 && response.statusCode < 300) {
            debugPrint('🗑️ Device token removed from SQL Backend');
          } else {
            debugPrint(
              '⚠️ Backend token delete failed (${response.statusCode}); '
              'still invalidating token on device.',
            );
          }
        } catch (e) {
          debugPrint(
            '⚠️ Backend token delete errored ($e); '
            'still invalidating token on device.',
          );
        }
      }

      // Always invalidate the token on the device on logout, even if the
      // backend delete failed. This guarantees a logged-out device stops
      // receiving pushes: the old token becomes undeliverable and a brand-new
      // token is generated only after the next login re-registers it.
      await _messaging.deleteToken();
      await prefs.remove(SharedPrefsKeys.fcmTokenCached);
    } catch (e) {
      debugPrint('❌ Error during token removal: $e');
    }
  }
}
