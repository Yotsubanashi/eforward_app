import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureUnlockService {
  static const String biometricEnabledKey = 'biometric_unlock_enabled';
  static final LocalAuthentication _localAuth = LocalAuthentication();
  static const Set<String> _nonBlockingAuthErrorCodes = {
    // No biometric template is enrolled on device.
    'NotEnrolled',
    'notEnrolled',
    // No PIN/pattern/passcode is configured for device credentials.
    'PasscodeNotSet',
    'passcodeNotSet',
    // Generic "no local auth available" style responses.
    'NotAvailable',
    'notAvailable',
  };

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
    } on PlatformException catch (e) {
      // If there is no biometric/PIN configured on the device,
      // don't block a valid username/password login.
      if (_nonBlockingAuthErrorCodes.contains(e.code)) {
        return true;
      }
      return false;
    }
  }
}
