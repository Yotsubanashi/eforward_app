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

  static Future<void> save({
    required String email,
    required String password,
  }) async {
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _passwordKey, value: password);
  }

  static Future<({String email, String password})?> read() async {
    final email = await _storage.read(key: _emailKey);
    final password = await _storage.read(key: _passwordKey);
    if (email == null || email.isEmpty || password == null) return null;
    return (email: email, password: password);
  }

  static Future<bool> hasCredentials() async {
    final email = await _storage.read(key: _emailKey);
    return email != null && email.isNotEmpty;
  }

  static Future<void> clear() async {
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passwordKey);
  }
}
