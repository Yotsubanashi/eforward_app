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
import 'services/biometric_credential_store.dart';
import 'services/notifications/fcm_token_service.dart';
import 'services/privacy_cover_service.dart';
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

  // Re-lock on resume: when the app is backgrounded/multitasked while a session
  // is active and the unlock toggle is on, require biometrics/PIN to return.
  bool _appLocked = false; // the cover overlay is currently painted
  bool _requireAuth = false; // the overlay can only be cleared by authenticating
  bool _unlocking = false;
  // Cached answer to "should we cover the screen if the app leaves the
  // foreground right now?" (session active + unlock enabled + device can
  // authenticate). Kept current so the overlay can be raised *synchronously* at
  // `inactive` — before iOS snapshots the screen for the app switcher — with no
  // async gap for content to leak through.
  bool _lockEligible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeepLinks();
    _refreshLockEligibility();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        // Fires *before* iOS captures the app-switcher snapshot. Cover the
        // screen now (synchronously) so the preview and the first frame on
        // reopen never show session content. A bare `inactive` (Control Center,
        // notification shade) does not by itself demand re-authentication.
        _raiseLock(requireAuth: false);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // The app was truly backgrounded — the overlay must now stay up until
        // the user authenticates.
        _raiseLock(requireAuth: true);
        break;
      case AppLifecycleState.resumed:
        _recheckVersionAfterResume();
        _handleResume();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Cover the screen when leaving the foreground. The cache-based path runs
  /// synchronously so the overlay is painted before the OS snapshot; an async
  /// safety net re-checks in case a session was created since the cache was last
  /// refreshed (e.g. the user just logged in and backgrounded immediately).
  void _raiseLock({required bool requireAuth}) {
    // The device auth prompt itself briefly drives the app `inactive`; don't let
    // that re-arm the lock we're in the middle of clearing.
    if (_unlocking) return;
    if (requireAuth) _requireAuth = true;
    if (_lockEligible && !_appLocked && mounted) {
      setState(() => _appLocked = true);
    }
    _verifyEligibilityAndRaise();
  }

  Future<void> _verifyEligibilityAndRaise() async {
    await _refreshLockEligibility();
    if (!mounted || _unlocking) return;
    if (_lockEligible && !_appLocked) {
      setState(() => _appLocked = true);
    }
  }

  /// Recompute [_lockEligible] and push the same answer to the native privacy
  /// cover, keeping the Dart overlay and the native cover on one gate.
  Future<void> _refreshLockEligibility() async {
    _lockEligible = await PrivacyCoverService.sync();
  }

  /// On return to the foreground: keep the cover and prompt for authentication
  /// if the app was really backgrounded (app switcher, or the device being
  /// locked and woken), or just drop it if the cover was only for a transient
  /// interruption. Also refreshes eligibility for next time.
  void _handleResume() {
    _refreshLockEligibility();

    if (_appLocked && _requireAuth) {
      // Authentication is required. Leave the native cover UP and let
      // _promptAppUnlock take it down only once auth resolves — otherwise the
      // cover would come off while Face ID is still prompting and flash the
      // content underneath (the device power-off/on case).
      _promptAppUnlock();
      return;
    }

    // No auth required (a transient inactive such as Control Center): reveal the
    // content, then take the native cover down once that frame has painted.
    if (_appLocked && mounted) {
      setState(() => _appLocked = false);
    }
    _requireAuth = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PrivacyCoverService.hideCover();
    });
  }

  /// Prompt for biometrics/PIN to clear the lock. Stays locked (with a retry
  /// button on the overlay) if authentication is cancelled or fails.
  Future<void> _promptAppUnlock() async {
    if (_unlocking) return;
    _unlocking = true;
    // Escape hatch for a lock raised before the screen lock was removed: with
    // nothing left to authenticate against, drop the overlay rather than
    // stranding the user behind a prompt that can never succeed.
    if (!await SecureUnlockService.isAvailable()) {
      _unlocking = false;
      if (mounted) {
        setState(() {
          _appLocked = false;
          _requireAuth = false;
        });
      }
      await PrivacyCoverService.hideCover();
      return;
    }
    final ok = await SecureUnlockService.authenticate(
      biometricOnly: false,
      reason: 'Unlock E-Forward',
    );
    _unlocking = false;
    if (!mounted) return;
    if (ok.success) {
      setState(() {
        _appLocked = false;
        _requireAuth = false;
      });
    }
    // Authentication has resolved: on success the real content is coming up; on
    // failure the Flutter lock overlay (with its retry button) must be reachable.
    // Either way the native cover has done its job — take it down after the next
    // frame paints so there's never a bare-content flash in between.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PrivacyCoverService.hideCover();
    });
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

    // Matches the reset-password link in all the forms it can arrive as:
    //   - Universal Link:  https://eforward.ardentnetworks.com.ph/auth/reset-password/?token=xxx
    //   - Older path:      https://eforward.ardentnetworks.com.ph/reset-password?token=xxx
    //   - Custom scheme:   eforward://reset-password?token=xxx
    // For the custom scheme, "reset-password" arrives as the host, not the path.
    // We normalize away a trailing slash and match on the path segment ending
    // with "reset-password" so /auth/reset-password/ and /reset-password both
    // work regardless of leading path or trailing slash.
    final normalizedPath = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    final isResetPassword =
        normalizedPath.endsWith('/reset-password') ||
        uri.host == 'reset-password';

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

  /// Mirrors the current session's refresh token into the secure enclave when
  /// biometric unlock is enabled, so the login-screen Face ID button can later
  /// restore the session without a password. No-op when the toggle is off or no
  /// refresh token is stored.
  Future<void> _captureRefreshTokenForBiometric(SharedPreferences prefs) async {
    try {
      if (!await SecureUnlockService.isEnabled()) return;
      final refreshToken =
          prefs.getString(SharedPrefsKeys.refreshToken)?.trim() ?? '';
      if (refreshToken.isNotEmpty) {
        await BiometricCredentialStore.saveRefreshToken(refreshToken);
      }
    } catch (e) {
      debugPrint('Capture refresh token for biometric failed: $e');
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

      // While we have a live session and biometric is on, stash the refresh
      // token so the login-screen Face ID button can restore the session later
      // with no password prompt — even if the user never did a password login
      // on this build (e.g. app was updated while already signed in).
      await _captureRefreshTokenForBiometric(prefs);

      // Biometrics are an alternate login method (see LoginScreen), not an
      // app-open gate: a valid saved session enters directly.
      authApi.dispose();
      return true;
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
      await _captureRefreshTokenForBiometric(prefs);
      return true;
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
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            if (_appLocked) _buildLockOverlay(),
          ],
        );
      },
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

  Widget _buildLockOverlay() {
    return Positioned.fill(
      child: Material(
        color: Colors.white,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: Color(0xFFCC0000),
                ),
                const SizedBox(height: 16),
                const Text(
                  "E-FORWARD LOCKED",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Authenticate to continue",
                  style: TextStyle(fontSize: 12, color: Colors.black45),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _unlocking ? null : _promptAppUnlock,
                    icon: const Icon(Icons.lock_open, color: Colors.white),
                    label: const Text(
                      "UNLOCK",
                      style: TextStyle(
                        color: Colors.white,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCC0000),
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
