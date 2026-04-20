import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/auth/login.dart';
import 'pages/auth/reset-password.dart';
import 'pages/dashboard/dashboard.dart';
import 'services/firebase_notification_service.dart';
import 'services/app_lifecycle_service.dart';
import 'firebase_options.dart';

// ✅ FIX: navigatorKey must be a global — NOT declared inside main()
// If it's inside main(), the notification service loses the reference
// when the app rebuilds.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Init Firebase first
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. Set navigator key BEFORE initialize() so background-tap navigation works
  FirebaseNotificationService.setNavigatorKey(navigatorKey);

  // 3. Init notifications (permissions, channel, listeners, background handler)
  await FirebaseNotificationService().initialize();

  // 4. Initialize app lifecycle service to monitor app lifecycle
  AppLifecycleService().initialize();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _appLinks = AppLinks();
  late final Future<bool> _hasSessionFuture = _hasSavedSession();

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  void _initDeepLinks() {
    // Handle deep link when app is already running
    _appLinks.uriLinkStream.listen(
      (uri) => _handleDeepLink(uri),
      onError: (err) => debugPrint('Deep link error: $err'),
    );

    // Handle deep link that launched the app from terminated state
    _appLinks
        .getInitialLink()
        .then((uri) {
          if (uri != null) {
            debugPrint('App launched with deep link: $uri');
            _handleDeepLink(uri);
          }
        })
        .catchError((err) => debugPrint('Error getting initial link: $err'));
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('Handling deep link: $uri');
    debugPrint('Path: ${uri.path}');
    debugPrint('Query params: ${uri.queryParameters}');

    // Matches: https://eforward.ardentnetworks.com.ph/auth/reset-password?token=xxx
    if (uri.path == '/auth/reset-password') {
      final token = uri.queryParameters['token'];
      debugPrint('Found token: $token');

      if (token != null && token.isNotEmpty) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => ResetPasswordScreen(token: token)),
          (route) => route.isFirst, // Keep the first route (LoginScreen)
        );
      }
    }
  }

  Future<bool> _hasSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token')?.trim() ?? '';
    return accessToken.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      home: FutureBuilder<bool>(
        future: _hasSessionFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.data == true) {
            return const DashboardPage();
          }

          return const LoginScreen();
        },
      ),
    );
  }
}
