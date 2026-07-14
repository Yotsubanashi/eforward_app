import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants/shared_prefs_keys.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'services/api/auth_api.dart';
import 'services/app_version_service.dart';
import 'services/notifications/fcm_token_service.dart';
import 'services/secure_unlock_service.dart';
import 'services/session_service.dart';
import 'routes/route_generator.dart';

// ✅ FIX: navigatorKey must be a global — NOT declared inside main()
// If it's inside main(), the notification service loses the reference
// when the app rebuilds.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _appLinks = AppLinks();
  late final Future<bool> _hasSessionFuture = _hasSavedSession();
  bool _versionUpToDate = false;
  bool _versionDialogVisible = false;
  bool _versionCheckInProgress = false;
  bool _initialVersionCheckScheduled = false;
  DateTime? _lastVersionPromptAt;
  DateTime? _suppressVersionPromptUntil;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeepLinks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recheckVersionAfterResume();
    }
  }

  void _scheduleInitialVersionCheck() {
    if (_initialVersionCheckScheduled || _versionUpToDate) return;
    _initialVersionCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _enforceLatestVersionIfNeeded();
    });
  }

  Future<void> _enforceLatestVersionIfNeeded({bool fromResume = false}) async {
    if (_versionUpToDate || _versionDialogVisible || _versionCheckInProgress) {
      return;
    }

    final now = DateTime.now();
    final suppressPrompt =
        _suppressVersionPromptUntil != null &&
        now.isBefore(_suppressVersionPromptUntil!);

    if (fromResume && _lastVersionPromptAt != null && !suppressPrompt) {
      final elapsed = now.difference(_lastVersionPromptAt!);
      if (elapsed < const Duration(seconds: 30)) return;
    }

    _versionCheckInProgress = true;
    final svc = AppVersionService();
    try {
      final current = await svc.getInstalledVersion();
      final remote = await svc.fetchLatestVersion();

      debugPrint(
        '[VersionCheck] Current: $current, Latest: ${remote?.latestVersion}',
      );

      if (!mounted || current == null || remote == null) return;

      if (!AppVersionService.isUpdateRequired(current, remote.latestVersion)) {
        debugPrint('[VersionCheck] App is up to date');
        _versionUpToDate = true;
        _suppressVersionPromptUntil = null;
        return;
      }

      if (suppressPrompt) {
        debugPrint('[VersionCheck] Still outdated but prompt suppressed');
        return;
      }

      debugPrint(
        '[VersionCheck] Update required: $current < ${remote.latestVersion}',
      );

      final pkg = await svc.getPackageName();
      if (!mounted) return;

      BuildContext? dialogContext = navigatorKey.currentState?.overlay?.context;
      if (dialogContext == null) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        dialogContext = navigatorKey.currentState?.overlay?.context;
      }
      if (dialogContext == null) {
        debugPrint(
          '[VersionCheck] Navigator context not available, will retry on resume',
        );
        return;
      }

      _versionDialogVisible = true;
      _lastVersionPromptAt = DateTime.now();

      final updateInitiated = await showForceUpdateDialog(
        context: dialogContext,
        remote: remote,
        current: current,
        packageName: pkg,
      );

      if (!mounted) return;

      _versionDialogVisible = false;

      // Re-fetch latest from API in case it changed, then re-read installed version.
      final remoteAfter = await svc.fetchLatestVersion();
      final latest = remoteAfter?.latestVersion ?? remote.latestVersion;
      final currentAfter = await svc.getInstalledVersion();

      if (currentAfter != null &&
          !AppVersionService.isUpdateRequired(currentAfter, latest)) {
        debugPrint('[VersionCheck] Update completed, app is now up to date');
        _versionUpToDate = true;
        _suppressVersionPromptUntil = null;
        return;
      }

      // User opened the download link — avoid re-prompt loop while they install.
      if (updateInitiated) {
        _suppressVersionPromptUntil = DateTime.now().add(
          const Duration(minutes: 3),
        );
        debugPrint(
          '[VersionCheck] Update started, suppressing prompt for 3 minutes',
        );
      }
    } catch (e) {
      debugPrint('Version gate failed: $e');
      _versionDialogVisible = false;
    } finally {
      _versionCheckInProgress = false;
      svc.dispose();
    }
  }

  Future<void> _recheckVersionAfterResume() async {
    if (_versionUpToDate || _versionDialogVisible || _versionCheckInProgress) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted ||
        _versionUpToDate ||
        _versionDialogVisible ||
        _versionCheckInProgress) {
      return;
    }

    await _enforceLatestVersionIfNeeded(fromResume: true);
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

    // Matches both:
    //   - Universal Link:  https://eforward.ardentnetworks.com.ph/reset-password?token=xxx
    //   - Custom scheme:   eforward://reset-password?token=xxx
    // For the custom scheme, "reset-password" arrives as the host, not the path,
    // so we check both to be safe.
    final isResetPassword =
        uri.path == '/reset-password' || uri.host == 'reset-password';

    if (isResetPassword) {
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
    final accessToken =
        prefs.getString(SharedPrefsKeys.accessToken)?.trim() ?? '';
    if (accessToken.isEmpty) {
      authApi.dispose();
      return false;
    }

    final meResult = await authApi.getMe(token: accessToken);
    if (meResult.isSuccess && meResult.data != null) {
      final user = SessionService.normalizeUser(meResult.data!);
      final userId = SessionService.extractEmployeeId(user);

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

    final refreshedAccessToken =
        prefs.getString(SharedPrefsKeys.accessToken)?.trim() ?? '';
    if (refreshedAccessToken.isEmpty) {
      authApi.dispose();
      return false;
    }

    final meAfterRefresh = await authApi.getMe(token: refreshedAccessToken);
    authApi.dispose();
    if (meAfterRefresh.isSuccess && meAfterRefresh.data != null) {
      await prefs.setString(
        SharedPrefsKeys.userData,
        jsonEncode(meAfterRefresh.data),
      );
      return SecureUnlockService.authenticateAfterLogin();
    }

    await prefs.remove(SharedPrefsKeys.accessToken);
    await prefs.remove(SharedPrefsKeys.refreshToken);
    await prefs.remove(SharedPrefsKeys.userData);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      // Apply a consistent cross-fade to every page transition across the app,
      // not just the bottom-nav tabs.
      theme: ThemeData(pageTransitionsTheme: kFadePageTransitionsTheme),
      onGenerateRoute: RouteGenerator.onGenerateRoute,
      home: FutureBuilder<bool>(
        future: _hasSessionFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.data == true) {
            _scheduleInitialVersionCheck();
            return const DashboardPage();
          }

          _scheduleInitialVersionCheck();
          return const LoginScreen();
        },
      ),
    );
  }
}
