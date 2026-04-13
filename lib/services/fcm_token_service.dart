import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class FCMTokenService {
  static const String _baseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';

  /// Save FCM token to backend after user login
  static Future<bool> saveFCMTokenToBackend({
    required String token,
    required String accessToken,
  }) async {
    try {
      debugPrint('📱 Saving FCM token to backend...');

      // Get FCM token from Firebase
      final fcmToken = await FirebaseMessaging.instance.getToken();

      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('❌ FCM token is null or empty');
        return false;
      }

      debugPrint('🔑 FCM Token: $fcmToken');

      // Send to backend
      final response = await http.post(
        Uri.parse('$_baseUrl/users/fcm-token'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'fcm_token': fcmToken,
          'device_type': 'android', // or 'ios' depending on platform
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('✅ FCM token saved to backend successfully');
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

  /// Get current FCM token
  static Future<String?> getFCMToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  /// Refresh FCM token (useful for periodic updates)
  static Future<bool> refreshFCMToken({required String accessToken}) async {
    try {
      debugPrint('🔄 Refreshing FCM token...');

      // Force refresh
      await FirebaseMessaging.instance.deleteToken();
      final newToken = await FirebaseMessaging.instance.getToken();

      if (newToken != null) {
        return await saveFCMTokenToBackend(
          token: newToken,
          accessToken: accessToken,
        );
      }

      return false;
    } catch (e) {
      debugPrint('Error refreshing FCM token: $e');
      return false;
    }
  }
}
