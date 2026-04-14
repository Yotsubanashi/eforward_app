import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FCMTokenService {
  static const String _baseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';

  /// Call this immediately after a successful login.
  static Future<bool> saveFCMTokenToBackend({
    required String accessToken,
  }) async {
    try {
      debugPrint('📱 Saving FCM token to backend...');

      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        debugPrint('⚠️ Warning: Could not retrieve FCM token: $e');
        debugPrint(
          '   This usually means Google Play Services is not installed on your emulator.',
        );
        debugPrint(
          '   The app will continue but will not receive push notifications.',
        );
        return false;
      }

      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('❌ FCM token is null or empty');
        return false;
      }

      debugPrint('🔑 FCM Token: $fcmToken');

      // ✅ FIX: detect platform instead of hardcoding 'android'
      final deviceType = Platform.isIOS ? 'ios' : 'android';

      final response = await http.post(
        Uri.parse('$_baseUrl/users/fcm-token'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'fcm_token': fcmToken, 'device_type': deviceType}),
      );

      debugPrint(
        '📡 Token save response: ${response.statusCode} ${response.body}',
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('✅ FCM token saved to backend successfully');
        // Cache locally so we can detect token rotation on next launch
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_saved_fcm_token', fcmToken);
        return true;
      } else {
        debugPrint(
          '⚠️ Backend returned ${response.statusCode}: ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
      return false;
    }
  }

  /// Call from home page initState — re-syncs if the token rotated while
  /// the user was logged out.
  static Future<void> syncTokenIfNeeded({required String accessToken}) async {
    try {
      String? currentToken;
      try {
        currentToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        debugPrint('⚠️ Could not sync token: $e');
        return;
      }

      if (currentToken == null) return;

      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('last_saved_fcm_token') ?? '';

      if (currentToken != savedToken) {
        debugPrint('🔄 Token changed — re-syncing to backend...');
        await saveFCMTokenToBackend(accessToken: accessToken);
      } else {
        debugPrint('✅ FCM token already in sync');
      }
    } catch (e) {
      debugPrint('Error syncing token: $e');
    }
  }

  /// Get current FCM token (for display / debug).
  static Future<String?> getFCMToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  /// Force-rotate token and re-save. Use after re-login on a different account.
  static Future<bool> refreshFCMToken({required String accessToken}) async {
    try {
      debugPrint('🔄 Refreshing FCM token...');
      await FirebaseMessaging.instance.deleteToken();
      await Future.delayed(const Duration(milliseconds: 500));
      return await saveFCMTokenToBackend(accessToken: accessToken);
    } catch (e) {
      debugPrint('Error refreshing FCM token: $e');
      return false;
    }
  }

  /// Call on logout so we do not reuse a stale token on next login.
  static Future<void> clearSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_saved_fcm_token');
  }
}
