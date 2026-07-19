import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:eforward_app/app.dart' show navigatorKey;
import 'package:eforward_app/screens/auth/login_screen.dart';
import 'package:eforward_app/services/api/auth_api.dart';
import 'package:eforward_app/services/notifications/notifications_service.dart';

/// Centralized handler for mid-session token expiry.
///
/// Individual screens fire many authenticated requests directly. When any of
/// them comes back `401` ("Token expired"), the screen used to just swallow the
/// error, so the app happily stayed on the Dashboard with a dead token (see the
/// "Token expired" logs). This service gives every call site one thing to call
/// on a 401:
///
///   if (SessionExpiryService().isUnauthorized(response.statusCode)) {
///     await SessionExpiryService().handleUnauthorized();
///     return;
///   }
///
/// The token is expired, so we log the user straight out: clear the session and
/// send them back to the login screen. The call is guarded so a burst of failing
/// requests only triggers one logout.
class SessionExpiryService {
  SessionExpiryService._internal();
  static final SessionExpiryService _instance =
      SessionExpiryService._internal();
  factory SessionExpiryService() => _instance;

  /// Guards against running the logout more than once for a burst of 401s.
  bool _loggingOut = false;

  bool isUnauthorized(int statusCode) => statusCode == 401;

  /// Handles a 401 from an authenticated request by logging the user out.
  Future<void> handleUnauthorized() async {
    if (_loggingOut) return;
    _loggingOut = true;

    try {
      await AuthApi().clearSession();
      await FirebaseAuth.instance.signOut();
      NotificationsService().reset();
      debugPrint('🔒 Session expired (401) — logging out');
    } catch (e) {
      debugPrint('Session expiry cleanup error: $e');
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _loggingOut = false;
      return;
    }

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );

    final messengerContext = navigator.overlay?.context;
    if (messengerContext != null && messengerContext.mounted) {
      ScaffoldMessenger.of(messengerContext).showSnackBar(
        const SnackBar(
          content: Text('Session expired. Please log in again.'),
        ),
      );
    }

    // Allow a fresh logout on the next expiry once we're back at login.
    _loggingOut = false;
  }
}
