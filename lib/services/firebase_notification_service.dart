import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eforward_app/services/notifications_service.dart';
import 'package:eforward_app/services/fcm_token_service.dart';
import 'package:eforward_app/pages/approvals/approval_details.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Module-level plugin + channel so the background isolate can reach them.
// ─────────────────────────────────────────────────────────────────────────────
const AndroidNotificationChannel kApprovalChannel = AndroidNotificationChannel(
  'eforward_approvals', // ← must match AndroidManifest meta-data value
  'E-Forward Approvals',
  description: 'Approval and document routing notifications',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

final FlutterLocalNotificationsPlugin flutterLocalNotifications =
    FlutterLocalNotificationsPlugin();

// ─────────────────────────────────────────────────────────────────────────────
// ✅ TOP-LEVEL background handler — MUST be outside any class.
// Firebase invokes this in a separate Dart isolate when the app is killed.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🔔 [BG] ${message.notification?.title} | data=${message.data}');
  await FirebaseNotificationService.showLocalNotification(message);
}

// ─────────────────────────────────────────────────────────────────────────────
class FirebaseNotificationService {
  static final FirebaseNotificationService _instance =
      FirebaseNotificationService._internal();

  FirebaseNotificationService._internal();
  factory FirebaseNotificationService() => _instance;

  static GlobalKey<NavigatorState>? _navigatorKey;

  static void setNavigatorKey(GlobalKey<NavigatorState> key) =>
      _navigatorKey = key;

  // ── Public entry point ────────────────────────────────────────────────────
  Future<void> initialize() async {
    try {
      debugPrint('🚀 Initialising Firebase Notifications...');

      // Firebase already initialised in main() — guard against double-init
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();

      // 1. OS permissions
      await _requestPermissions();

      // 2. Android notification channel
      await _createAndroidChannel();

      // 3. flutter_local_notifications
      await _initLocalNotifications();

      // 4. ✅ Register the TOP-LEVEL background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 5. Foreground messages
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // 6. Tap while app is backgrounded (resumed)
      FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);

      // 7. Tap while app was TERMINATED
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        debugPrint('📬 Launched from terminated state via notification');
        await Future.delayed(const Duration(milliseconds: 800));
        await _onNotificationTap(initial);
      }

      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('📱 FCM token: $token');
      debugPrint('✅ Firebase Notifications ready');
    } catch (e) {
      debugPrint('❌ Firebase init error: $e');
    }
  }

  // ── OS permissions ────────────────────────────────────────────────────────
  Future<void> _requestPermissions() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('🔔 FCM permission status: ${settings.authorizationStatus}');

    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      debugPrint('🤖 Android notification permission: $status');
    }

    if (Platform.isIOS) {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
  }

  // ── Android channel ───────────────────────────────────────────────────────
  Future<void> _createAndroidChannel() async {
    if (!Platform.isAndroid) return;
    await flutterLocalNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(kApprovalChannel);
    debugPrint(
      '📢 Android notification channel created: ${kApprovalChannel.id}',
    );
  }

  // ── flutter_local_notifications ───────────────────────────────────────────
  Future<void> _initLocalNotifications() async {
    await flutterLocalNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        debugPrint('👆 Local notif tapped — payload: ${response.payload}');
        _handlePayloadTap(response.payload);
      },
    );
  }

  // ── Show system-tray notification ─────────────────────────────────────────
  /// Static so the top-level background handler can call it without an instance.
  static Future<void> showLocalNotification(RemoteMessage message) async {
    final title =
        message.notification?.title ?? message.data['title'] ?? 'E-Forward';
    final body =
        message.notification?.body ??
        message.data['body'] ??
        'You have a new notification';
    final payload = jsonEncode(message.data);

    await flutterLocalNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          kApprovalChannel.id,
          kApprovalChannel.name,
          channelDescription: kApprovalChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          styleInformation: BigTextStyleInformation(body),
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  // ── Foreground message ────────────────────────────────────────────────────
  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    debugPrint('📨 [FG] ${message.notification?.title}');

    // Show system heads-up notification (FCM does NOT do this automatically
    // when the app is open on Android)
    await showLocalNotification(message);

    // Update badge counter
    NotificationsService().incrementUnreadCount();
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  static Future<void> _onNotificationTap(RemoteMessage message) async {
    debugPrint('👆 Notification tapped. data=${message.data}');
    _navigate(message.data);
  }

  static void _handlePayloadTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      _navigate(jsonDecode(payload) as Map<String, dynamic>);
    } catch (_) {}
  }

  static void _navigate(Map<String, dynamic> data) {
    final type = data['type'] ?? '';
    final routingId = data['routing_id'];

    if (type == 'pending_approval' && routingId != null) {
      _navigatorKey?.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ApprovalDetailPage(
            item: {
              'id': routingId,
              'routing_id': routingId,
              'status': 'PND',
              'referenceNo': data['reference_no'] ?? '',
              'particulars': data['particulars'] ?? '',
              'requester': data['requester'] ?? '',
              'dateSent': data['date_sent'] ?? '',
              'routing': {
                'reference_no': data['reference_no'] ?? '',
                'particulars': data['particulars'] ?? '',
              },
            },
            isFromHistory: false,
          ),
        ),
      );
    }
  }

  // ── Misc helpers ──────────────────────────────────────────────────────────
  Future<String?> getFCMToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      debugPrint('✅ Subscribed: $topic');
    } catch (e) {
      debugPrint('❌ Subscribe error: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      debugPrint('✅ Unsubscribed: $topic');
    } catch (e) {
      debugPrint('❌ Unsubscribe error: $e');
    }
  }
}
