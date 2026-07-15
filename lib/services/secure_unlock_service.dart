import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The unlock method to surface on the login button, resolved from the device's
/// enrolled biometrics.
enum UnlockMethod { face, fingerprint, pin }

class SecureUnlockService {
  // Enables biometric/PIN as an alternate *login* method (the login button).
  static const String biometricEnabledKey = 'biometric_unlock_enabled';
  // Two-factor: require a device biometric/PIN check *after* the password on
  // every email+password login.
  static const String twoFactorEnabledKey = 'two_factor_enabled';
  static final LocalAuthentication _localAuth = LocalAuthentication();

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(biometricEnabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(biometricEnabledKey, value);
  }

  static Future<bool> isTwoFactorEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(twoFactorEnabledKey) ?? false;
  }

  static Future<void> setTwoFactorEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(twoFactorEnabledKey, value);
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

  /// Resolves which method to present on the login button:
  ///   - iPhone with Face ID  -> [UnlockMethod.face]
  ///   - Touch ID / Android fingerprint -> [UnlockMethod.fingerprint]
  ///   - anything else (only device passcode) -> [UnlockMethod.pin]
  static Future<UnlockMethod> resolveMethod() async {
    List<BiometricType> types;
    try {
      types = await _localAuth.getAvailableBiometrics();
    } catch (_) {
      types = const [];
    }

    if (types.contains(BiometricType.face)) return UnlockMethod.face;
    if (types.contains(BiometricType.fingerprint)) {
      return UnlockMethod.fingerprint;
    }
    // Newer Android reports generic strong/weak rather than a concrete sensor.
    if (types.contains(BiometricType.strong) ||
        types.contains(BiometricType.weak)) {
      return Platform.isIOS ? UnlockMethod.face : UnlockMethod.fingerprint;
    }
    return UnlockMethod.pin;
  }

  /// Directly prompts the device for authentication, used by the login-screen
  /// quick-unlock buttons. Unlike [authenticateAfterLogin] this does not short
  /// circuit on the toggle/availability — the caller only shows the buttons
  /// when unlock is enabled, and here a failure/cancel must return false so the
  /// user stays on the login form.
  ///
  /// [biometricOnly] true drives the Face ID button; false allows the device
  /// passcode/PIN (local_auth has no passcode-exclusive mode).
  static Future<bool> authenticate({
    required bool biometricOnly,
    String reason = 'Authenticate to continue to your account',
  }) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
