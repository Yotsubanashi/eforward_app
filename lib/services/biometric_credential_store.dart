import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the login credentials used by the biometric/PIN quick-login on the
/// login screen. Values live in the OS secure enclave (iOS Keychain / Android
/// Keystore), never in SharedPreferences. They are written on a successful
/// login while the unlock toggle is on, survive logout so the user can log back
/// in with biometrics, and are cleared when the toggle is turned off or a stored
/// credential is rejected by the backend (e.g. the password changed).
class BiometricCredentialStore {
  BiometricCredentialStore._();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _emailKey = 'biometric_login_email';
  static const _passwordKey = 'biometric_login_password';
  // A refresh token captured from a live session. Lets biometric login restore
  // the session WITHOUT replaying a password (so no password dialog is needed),
  // as long as the backend still honours the token.
  static const _refreshTokenKey = 'biometric_refresh_token';

  // Every operation is wrapped so a secure-storage failure (e.g. the native
  // plugin not yet registered after adding the dependency, or a Keystore
  // hiccup) can never break the login flow — it just degrades to "no biometric
  // login available".
  static Future<void> save({
    required String email,
    required String password,
  }) async {
    try {
      await _storage.write(key: _emailKey, value: email);
      await _storage.write(key: _passwordKey, value: password);
    } catch (e) {
      debugPrint('BiometricCredentialStore.save failed: $e');
    }
  }

  static Future<({String email, String password})?> read() async {
    try {
      final email = await _storage.read(key: _emailKey);
      final password = await _storage.read(key: _passwordKey);
      if (email == null || email.isEmpty || password == null) return null;
      return (email: email, password: password);
    } catch (e) {
      debugPrint('BiometricCredentialStore.read failed: $e');
      return null;
    }
  }

  /// Reads just the stored login email (without requiring the password to be
  /// present). Used to select the correct backend before a token refresh.
  static Future<String?> readEmail() async {
    try {
      final email = await _storage.read(key: _emailKey);
      if (email == null || email.isEmpty) return null;
      return email;
    } catch (e) {
      debugPrint('BiometricCredentialStore.readEmail failed: $e');
      return null;
    }
  }

  static Future<bool> hasCredentials() async {
    try {
      final email = await _storage.read(key: _emailKey);
      return email != null && email.isNotEmpty;
    } catch (e) {
      debugPrint('BiometricCredentialStore.hasCredentials failed: $e');
      return false;
    }
  }

  /// Stores a refresh token captured from the active session, used for
  /// password-free biometric login.
  static Future<void> saveRefreshToken(String token) async {
    if (token.trim().isEmpty) return;
    try {
      await _storage.write(key: _refreshTokenKey, value: token.trim());
    } catch (e) {
      debugPrint('BiometricCredentialStore.saveRefreshToken failed: $e');
    }
  }

  static Future<String?> readRefreshToken() async {
    try {
      final token = await _storage.read(key: _refreshTokenKey);
      if (token == null || token.trim().isEmpty) return null;
      return token.trim();
    } catch (e) {
      debugPrint('BiometricCredentialStore.readRefreshToken failed: $e');
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _emailKey);
      await _storage.delete(key: _passwordKey);
      await _storage.delete(key: _refreshTokenKey);
    } catch (e) {
      debugPrint('BiometricCredentialStore.clear failed: $e');
    }
  }
}
