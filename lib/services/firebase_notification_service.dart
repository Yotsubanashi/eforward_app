import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class FirebaseNotificationService {
  static final FirebaseNotificationService _instance =
      FirebaseNotificationService._internal();
  static GlobalKey<NavigatorState>? _navigatorKey;

  FirebaseNotificationService._internal();

  factory FirebaseNotificationService() {
    return _instance;
  }

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  /// Set navigator key for showing dialogs
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Initialize Firebase and request notification permissions
  Future<void> initialize() async {
    try {
      debugPrint(' Initializing Firebase Notifications...');

      // Initialize Firebase
      await Firebase.initializeApp();

      // Request notification permission (especially for iOS and Android 13+)
      await _requestNotificationPermission();

      // Get FCM token for backend
      final token = await _firebaseMessaging.getToken();
      debugPrint('📱 FCM Token: $token');

      // Handle foreground notifications
      FirebaseMessaging.onMessage.listen(_handleForegroundNotification);

      // Handle notification when app is opened from terminated state
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Handle background messages
      FirebaseMessaging.onBackgroundMessage(_handleBackgroundNotification);

      debugPrint(' Firebase Notifications initialized successfully');
    } catch (e) {
      debugPrint(' Firebase initialization error: $e');
    }
  }

  /// Request notification permission from user
  Future<void> _requestNotificationPermission() async {
    try {
      // iOS specific request
      final permission = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('iOS Permission status: ${permission.authorizationStatus}');

      // Android specific request (API 33+)
      await Permission.notification.request();

      debugPrint('✅ Notification permissions requested');
    } catch (e) {
      debugPrint('❌ Permission request error: $e');
    }
  }

  /// Handle notifications when app is in foreground
  static Future<void> _handleForegroundNotification(
    RemoteMessage message,
  ) async {
    debugPrint('📨 Foreground notification received');
    debugPrint('Title: ${message.notification?.title}');
    debugPrint('Body: ${message.notification?.body}');
    debugPrint('Data: ${message.data}');

    // Show local notification or dialog
    _showNotificationDialog(
      title: message.notification?.title ?? 'Notification',
      body: message.notification?.body ?? '',
      data: message.data,
    );
  }

  /// Handle background notifications
  static Future<void> _handleBackgroundNotification(
    RemoteMessage message,
  ) async {
    debugPrint('🔔 Background notification received');
    debugPrint('Title: ${message.notification?.title}');
    debugPrint('Body: ${message.notification?.body}');
  }

  /// Handle notification when user taps it
  static Future<void> _handleNotificationTap(RemoteMessage message) async {
    debugPrint('👆 Notification tapped');
    debugPrint('Data: ${message.data}');

    // Navigate to appropriate page based on notification data
    if (message.data.containsKey('link')) {
      final link = message.data['link'];
      debugPrint('Navigating to: $link');
      // You can add navigation logic here
    }
  }

  /// Show notification dialog when app is in foreground
  static void _showNotificationDialog({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    final context = _navigatorKey?.currentContext;
    if (context != null && context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(body),
                if (data.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Additional Info:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...data.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${e.key}: ${e.value}'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// Get current FCM token
  Future<String?> getFCMToken() async {
    try {
      final token = await _firebaseMessaging.getToken();
      return token;
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  /// Subscribe to notification topics
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      debugPrint('✅ Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('❌ Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from notification topics
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      debugPrint('✅ Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('❌ Error unsubscribing from topic: $e');
    }
  }
}
