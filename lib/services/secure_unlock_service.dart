import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The unlock method to surface on the login button, resolved from the device's
/// enrolled biometrics.
enum UnlockMethod { face, fingerprint, pin }

/// Result of a device authentication attempt. A plain `false` can't tell the
/// caller whether the user simply cancelled, or the device refused (no screen
/// lock, locked out after too many attempts, plugin misconfiguration) — those
/// need very different messages, so the reason is carried out to the UI instead
/// of being swallowed.
class UnlockResult {
  const UnlockResult._(this.success, {this.cancelled = false, this.message});

  final bool success;

  /// True when the user dismissed the prompt themselves. The UI should stay
  /// silent rather than accusing them of a failed authentication.
  final bool cancelled;

  /// A user-facing explanation when [success] is false and it wasn't a cancel.
  final String? message;

  static const UnlockResult ok = UnlockResult._(true);
  static const UnlockResult userCancelled =
      UnlockResult._(false, cancelled: true);

  factory UnlockResult.failure(String message) =>
      UnlockResult._(false, message: message);
}

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

  /// Whether the device can actually authenticate the user *right now*.
  ///
  /// Deliberately uses [isDeviceSupported] alone. `canCheckBiometrics` only
  /// reports that a sensor exists — it is true on an Android phone with a
  /// fingerprint reader but no enrolled finger and no screen lock, and OR-ing
  /// the two let us offer unlock on devices where every prompt is guaranteed to
  /// fail with no fallback. [isDeviceSupported] is the check that means "a PIN,
  /// pattern, password, or biometric is enrolled".
  static Future<bool> isAvailable() async {
    try {
      return await _localAuth.isDeviceSupported();
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

  /// Short label for the login button. Apple and Android name the same concepts
  /// differently — showing "Fingerprint" next to a Touch ID sensor or "PIN" on
  /// an iPhone reads as a different product than the OS prompt that follows.
  static String labelFor(UnlockMethod method) {
    if (Platform.isIOS) {
      return switch (method) {
        UnlockMethod.face => 'Face ID',
        UnlockMethod.fingerprint => 'Touch ID',
        UnlockMethod.pin => 'Passcode',
      };
    }
    return switch (method) {
      UnlockMethod.face => 'Face Unlock',
      UnlockMethod.fingerprint => 'Fingerprint',
      UnlockMethod.pin => 'PIN',
    };
  }

  /// What the user has to go set up when the device can't authenticate at all.
  /// Named per platform so the instruction matches the Settings app they'll
  /// actually open.
  static String get screenLockSetupMessage => Platform.isIOS
      ? 'Set up a passcode or Face ID / Touch ID in your iPhone Settings '
          'first.'
      : 'Set up a screen lock on your phone first — a PIN, pattern, password, '
          'or fingerprint in your device settings.';

  /// The device's own name for its credential fallback, for use mid-sentence.
  static String get _credentialName =>
      Platform.isIOS ? 'passcode' : 'PIN, pattern, or password';

  /// Directly prompts the device for authentication, used by the login-screen
  /// quick-unlock buttons. Unlike [authenticateAfterLogin] this does not short
  /// circuit on the toggle/availability — the caller only shows the buttons
  /// when unlock is enabled, and here a failure/cancel must return false so the
  /// user stays on the login form.
  ///
  /// [biometricOnly] true drives the Face ID button; false allows the device
  /// passcode/PIN (local_auth has no passcode-exclusive mode).
  static Future<UnlockResult> authenticate({
    required bool biometricOnly,
    String reason = 'Authenticate to continue to your account',
  }) async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      // `false` with no exception means the user cancelled or the sensor
      // rejected them — the OS already showed its own feedback.
      return ok ? UnlockResult.ok : UnlockResult.userCancelled;
    } on PlatformException catch (e) {
      debugPrint(
        'local_auth failed (biometricOnly: $biometricOnly): '
        '${e.code} — ${e.message}',
      );

      // Asked for biometrics on a device that has none enrolled: retry allowing
      // the device PIN/pattern/password instead of dead-ending. Android reports
      // no enrolled biometrics only at this point, so the button's label can be
      // "fingerprint" while the sensor is actually unusable.
      final noBiometrics = e.code == auth_error.notEnrolled ||
          e.code == auth_error.notAvailable ||
          e.code == auth_error.biometricOnlyNotSupported;
      if (biometricOnly && noBiometrics) {
        return authenticate(biometricOnly: false, reason: reason);
      }

      return UnlockResult.failure(_messageForCode(e.code));
    }
  }

  static String _messageForCode(String code) {
    switch (code) {
      case auth_error.notEnrolled:
      case auth_error.passcodeNotSet:
        return screenLockSetupMessage;
      case auth_error.notAvailable:
      case auth_error.biometricOnlyNotSupported:
      case auth_error.otherOperatingSystem:
        return 'This device can\'t authenticate you right now. Log in with '
            'your email and password.';
      case auth_error.lockedOut:
        return 'Too many failed attempts. Wait a moment, then try again or '
            'use your password.';
      case auth_error.permanentlyLockedOut:
        return 'Unlock your device with your $_credentialName first, then try '
            'again.';
      default:
        return 'Device authentication is unavailable. Log in with your email '
            'and password.';
    }
  }
}
