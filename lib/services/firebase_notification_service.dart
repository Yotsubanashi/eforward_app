import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:eforward_app/services/notifications_service.dart';
import 'package:eforward_app/pages/approvals/approval_details.dart';

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

    // Increment unread count
    NotificationsService().incrementUnreadCount();

    // Show notification dialog with action
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

    final navigatorContext = _navigatorKey?.currentContext;
    if (navigatorContext == null) return;

    // Extract notification type and data
    final notificationType = message.data['type'] ?? 'general';
    final routingId = message.data['routing_id'];
    final approvalId = message.data['approval_id'];
    final documentId = message.data['document_id'];

    debugPrint('Navigation: type=$notificationType, routingId=$routingId');

    // Navigate based on notification type
    if (notificationType == 'pending_approval' && routingId != null) {
      // Navigate to approval details with full item data
      final approvalItem = {
        'id': routingId,
        'routing_id': routingId,
        'status': 'PND',
        'referenceNo': message.data['reference_no'] ?? '',
        'particulars': message.data['particulars'] ?? '',
        'requester': message.data['requester'] ?? '',
        'dateSent': message.data['date_sent'] ?? '',
        'routing': {
          'reference_no': message.data['reference_no'] ?? '',
          'particulars': message.data['particulars'] ?? '',
        },
      };

      _navigatorKey?.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ApprovalDetailPage(item: approvalItem),
        ),
      );
    } else {
      // Default: navigate to notifications page
      // You can add more navigation logic here
      debugPrint('Opening notifications...');
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
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(
                Icons.notifications_active,
                size: 24,
                color: Color(0xFFCC0000),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(body, style: const TextStyle(fontSize: 14, height: 1.5)),
                if (data.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Details:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ...data.entries
                      .where(
                        (e) =>
                            e.key != 'type' &&
                            e.key != 'routing_id' &&
                            e.key != 'approval_id',
                      )
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '• ${e.key}: ${e.value}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'DISMISS',
                style: TextStyle(
                  color: Colors.black45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (data['type'] == 'pending_approval')
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _handleNotificationTap(
                    RemoteMessage(
                      notification: RemoteNotification(
                        title: title,
                        body: body,
                      ),
                      data: data,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCC0000),
                  elevation: 0,
                ),
                child: const Text(
                  'VIEW',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
