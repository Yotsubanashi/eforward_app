import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:eforward_app/firebase_options.dart';
import 'package:eforward_app/services/notifications_service.dart';
import 'package:eforward_app/pages/approvals/approval_details.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Android-only: module-level plugin + channel so the background isolate
// can reach them. On iOS, Firebase is the sole UNUserNotificationCenterDelegate
// and handles display natively — flutter_local_notifications must NOT be
// initialized on iOS because its initialize() call replaces Firebase's
// UNUserNotificationCenterDelegate, which silently breaks all iOS notifications.
// ─────────────────────────────────────────────────────────────────────────────
const AndroidNotificationChannel kApprovalChannel = AndroidNotificationChannel(
  'eforward_approvals', // must match AndroidManifest meta-data value
  'E-Forward Approvals',
  description: 'Approval and document routing notifications',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

final FlutterLocalNotificationsPlugin flutterLocalNotifications =
    FlutterLocalNotificationsPlugin();

// ─────────────────────────────────────────────────────────────────────────────
// TOP-LEVEL background handler — MUST be outside any class.
// Firebase invokes this in a separate Dart isolate when the app is killed.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // On iOS, APNs already displayed the notification; nothing to do here.
  if (Platform.isIOS) return;

  // Android: flutter_local_notifications is a fresh instance in this background
  // isolate — initialize it before calling show().
  await flutterLocalNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  // Ensure the Android channel exists in this isolate (idempotent).
  await flutterLocalNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(kApprovalChannel);

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

      // 1. OS permissions + iOS foreground presentation options
      await _requestPermissions();

      // 2. Android: notification channel + flutter_local_notifications
      //    iOS: skipped — initializing flutter_local_notifications on iOS
      //    replaces Firebase's UNUserNotificationCenterDelegate, which
      //    silently breaks setForegroundNotificationPresentationOptions.
      if (Platform.isAndroid) {
        await _createAndroidChannel();
        await _initLocalNotifications();
      }

      // 3. Register the TOP-LEVEL background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 4. Foreground messages
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // 5. Tap while app is backgrounded (resumed)
      FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);

      // 6. Tap while app was TERMINATED
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
      // Tell Firebase to display the notification banner even when the app is
      // open. This only works when Firebase IS the UNUserNotificationCenterDelegate,
      // which is why we must NOT call flutterLocalNotifications.initialize() on iOS.
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
    await flutterLocalNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(kApprovalChannel);
    debugPrint(
      '📢 Android notification channel created: ${kApprovalChannel.id}',
    );
  }

  // ── flutter_local_notifications (Android only) ────────────────────────────
  Future<void> _initLocalNotifications() async {
    await flutterLocalNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        debugPrint('👆 Local notif tapped — payload: ${response.payload}');
        _handlePayloadTap(response.payload);
      },
    );
  }

  // ── Show system-tray notification (Android only) ─────────────────────────
  /// On iOS Firebase displays the notification natively via APNs.
  /// This method is only called on Android (foreground + background isolate).
  static Future<void> showLocalNotification(RemoteMessage message) async {
    if (Platform.isIOS) return;

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
      ),
      payload: payload,
    );
  }

  // ── Foreground message ────────────────────────────────────────────────────
  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    debugPrint('📨 [FG] ${message.notification?.title}');

    // Android: FCM does NOT auto-show notifications when the app is in the
    // foreground, so we show them manually.
    // iOS: setForegroundNotificationPresentationOptions already handles this;
    // showLocalNotification is a no-op on iOS.
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
