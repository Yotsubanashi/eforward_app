import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureUnlockService {
  static const String biometricEnabledKey = 'biometric_unlock_enabled';
  static final LocalAuthentication _localAuth = LocalAuthentication();

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(biometricEnabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(biometricEnabledKey, value);
  }

  static Future<bool> isAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateAfterLogin() async {
    final enabled = await isEnabled();
    if (!enabled) return true;

    final available = await isAvailable();
    if (!available) return true;

    try {
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to continue to your account',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
