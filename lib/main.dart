import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'pages/auth/login.dart';
import 'pages/auth/reset_password.dart';
import 'services/firebase_notification_service.dart';
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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // ✅ uses the global key
      home: const LoginScreen(),
      onGenerateRoute: _generateRoute,
      onGenerateInitialRoutes: _generateInitialRoutes,
    );
  }

  /// Generate initial routes for deep linking support
  static List<Route<dynamic>> _generateInitialRoutes(String initialRouteName) {
    final routes = [MaterialPageRoute(builder: (_) => const LoginScreen())];

    // Check if we're opening from a deep link
    if (initialRouteName.contains('/auth/reset-password')) {
      final uri = Uri.parse(initialRouteName);
      final token = uri.queryParameters['token'];
      routes.add(
        MaterialPageRoute(builder: (_) => ResetPasswordScreen(token: token)),
      );
    }

    return routes;
  }

  /// Handle named routes and query parameters
  static Route<dynamic>? _generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/auth/reset-password':
        // settings.arguments might contain the full URL or query string
        final token = _extractTokenFromArgs(settings.arguments);
        return MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(token: token),
          settings: settings,
        );
      default:
        return null;
    }
  }

  /// Extract token from various argument formats
  static String? _extractTokenFromArgs(dynamic args) {
    if (args is String) {
      // Try parsing as URL
      try {
        final uri = Uri.parse(args.contains('?') ? args : '/?$args');
        return uri.queryParameters['token'];
      } catch (_) {
        return args;
      }
    }
    if (args is Map) {
      return args['token'] as String?;
    }
    return null;
  }
}
