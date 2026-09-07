import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Platform bridge for managing the home screen app icon badge count on iOS and Android.
class AppBadgeService {
  AppBadgeService._();

  static const MethodChannel _channel = MethodChannel('eforward/badge');
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Updates the native app icon badge count on the device home screen.
  /// If [count] <= 0, clears the badge completely.
  static Future<void> updateBadgeCount(int count) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;

    try {
      if (count <= 0) {
        await clearBadge();
      } else {
        await _channel.invokeMethod('setBadgeCount', count);
      }
    } catch (e) {
      debugPrint('[AppBadgeService] updateBadgeCount error: $e');
    }
  }

  /// Clears the badge from the home screen app icon and dismisses delivered notifications.
  static Future<void> clearBadge() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('clearBadge');
      if (Platform.isAndroid) {
        // Also cancel any local notification tray entries
        await _localNotifications.cancelAll();
      }
    } catch (e) {
      debugPrint('[AppBadgeService] clearBadge error: $e');
    }
  }
}
