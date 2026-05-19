import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/auth/login.dart';
import 'pages/auth/reset-password.dart';
import 'pages/dashboard/dashboard.dart';
import 'services/firebase_notification_service.dart';
import 'services/app_lifecycle_service.dart';
import 'services/auth_api.dart';
import 'services/secure_unlock_service.dart';
import 'services/app_version_service.dart';
import 'services/fcm_token_service.dart';
import 'firebase_options.dart';

// ✅ FIX: navigatorKey must be a global — NOT declared inside main()
// If it's inside main(), the notification service loses the reference
// when the app rebuilds.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

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
  bool _versionGateShown = false;
  bool _versionGateScheduled = false;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  void _scheduleVersionGateAfterHome() {
    if (_versionGateScheduled || _versionGateShown) return;
    _versionGateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _enforceLatestVersionIfNeeded();
    });
  }

  Future<void> _enforceLatestVersionIfNeeded() async {
    if (_versionGateShown) return;

    final svc = AppVersionService();
    try {
      final current = await svc.getInstalledVersion();
      final remote = await svc.fetchLatestVersion();
      if (!mounted || current == null || remote == null) return;

      if (current < remote.latestVersion) {
        _versionGateShown = true;
        final pkg = await svc.getPackageName();
        if (!mounted) return;
        final dialogContext = navigatorKey.currentState?.overlay?.context;
        if (dialogContext == null) {
          _versionGateShown = false;
          _versionGateScheduled = false;
          return;
        }
        await showForceUpdateDialog(
          context: dialogContext,
          remote: remote,
          current: current,
          packageName: pkg,
        );
      }
    } catch (e) {
      debugPrint('Version gate failed: $e');
    } finally {
      svc.dispose();
    }
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
        .catchError((err) {
          debugPrint('Error getting initial link: $err');
          return null;
        });
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('Handling deep link: $uri');
    debugPrint('Path: ${uri.path}');
    debugPrint('Query params: ${uri.queryParameters}');

    // Matches: {APP_BASE_URL}/auth/reset-password?token=xxx
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
    final authApi = AuthApi();
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token')?.trim() ?? '';
    if (accessToken.isEmpty) {
      authApi.dispose();
      return false;
    }

    final meResult = await authApi.getMe(token: accessToken);
    if (meResult.isSuccess && meResult.data != null) {
      final userData = meResult.data!;
      final user = userData['user'] is Map ? userData['user'] : userData;
      final userId = user['id']?.toString() ?? 
                     user['employee_id']?.toString() ?? 
                     user['employeeId']?.toString();
      
      if (userId != null) {
        FCMTokenService.registerToken(userId);
      }

      final isUnlocked = await SecureUnlockService.authenticateAfterLogin();
      authApi.dispose();
      return isUnlocked;
    }

    // Access token might be expired, try refresh token once.
    final refreshResult = await authApi.refreshWithStoredToken();
    if (!refreshResult.isSuccess) {
      authApi.dispose();
      return false;
    }

    final refreshedAccessToken = prefs.getString('access_token')?.trim() ?? '';
    if (refreshedAccessToken.isEmpty) {
      authApi.dispose();
      return false;
    }

    final meAfterRefresh = await authApi.getMe(token: refreshedAccessToken);
    authApi.dispose();
    if (meAfterRefresh.isSuccess && meAfterRefresh.data != null) {
      await prefs.setString('user_data', jsonEncode(meAfterRefresh.data));
      return SecureUnlockService.authenticateAfterLogin();
    }

    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_data');
    return false;
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
            _scheduleVersionGateAfterHome();
            return const DashboardPage();
          }

          _scheduleVersionGateAfterHome();
          return const LoginScreen();
        },
      ),
    );
  }
}
