import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:eforward_app/config/app_env.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FCMTokenService {
  static String get _baseUrl => AppEnv.apiBaseUrl;
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Registers the current device FCM token to your SQL Backend.
  /// This supports multiple devices per employee_id.
  static Future<void> registerToken(String employeeId) async {
    try {
      if (employeeId.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token') ?? '';
      
      String? token = await _messaging.getToken();
      if (token == null) {
        debugPrint('❌ Could not get FCM token');
        return;
      }

      // Cache token locally for logout cleanup
      await prefs.setString('fcm_token_cached', token);

      final deviceInfo = await _getDeviceInfo();
      
      // JSON Payload na match sa SQL Columns natin
      final Map<String, dynamic> payload = {
        'employee_id': employeeId,
        'fcm_token': token,
        'device_id': deviceInfo['deviceId'],
        'device_model': deviceInfo['deviceModel'],
        'platform': Platform.isIOS ? 'ios' : 'android',
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/users/fcm-token'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('✅ FCM Token saved to SQL (Multi-Device) for: $employeeId');
      } else {
        debugPrint('⚠️ SQL Backend Error (${response.statusCode}): ${response.body}');
      }

      // Listen for token refreshes (auto-update if Google changes the token)
      _messaging.onTokenRefresh.listen((newToken) async {
        await registerToken(employeeId);
      });
    } catch (e) {
      debugPrint('❌ Error syncing FCM token to SQL: $e');
    }
  }

  /// Removes only the current device's token from SQL on logout.
  static Future<void> removeToken(String employeeId) async {
    try {
      if (employeeId.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token') ?? '';

      String? token = await _messaging.getToken();
      token ??= prefs.getString('fcm_token_cached');

      if (token != null) {
        final deviceInfo = await _getDeviceInfo();
        
        // Match the registration payload for identification
        final Map<String, dynamic> payload = {
          'employee_id': employeeId,
          'fcm_token': token,
          'device_id': deviceInfo['deviceId'],
          'device_model': deviceInfo['deviceModel'],
          'platform': Platform.isIOS ? 'ios' : 'android',
        };

        // I-delete lang ang entry na match ang employee_id AT fcm_token
        final response = await http.delete(
          Uri.parse('$_baseUrl/users/fcm-token'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          debugPrint('🗑️ Device token removed from SQL Backend');
        }

        // Invalidate on device level
        await _messaging.deleteToken();
      }
    } catch (e) {
      debugPrint('❌ Error during token removal: $e');
    }
  }

  static Future<Map<String, String>> _getDeviceInfo() async {
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
}
