import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/shared_prefs_keys.dart';
import 'secure_unlock_service.dart';

/// Bridge to the native iOS privacy cover (see ios/Runner/AppDelegate.swift).
///
/// A Flutter-drawn overlay cannot reliably hide session content from the
/// app-switcher snapshot: iOS captures that snapshot on the platform thread as
/// the app resigns active, before Flutter rasterizes its next frame. The native
/// side paints an opaque cover on the real UIKit lifecycle instead; this service
/// tells it *when* covering is warranted and lets Flutter take the cover down
/// once its own lock screen has painted.
class PrivacyCoverService {
  PrivacyCoverService._();

  static const MethodChannel _channel = MethodChannel('eforward/privacy');

  /// Whether the background/app-switcher cover should be shown right now: an
  /// active session, the unlock toggle on, and a device that can actually
  /// authenticate. Mirrors the gate the Flutter lock overlay uses.
  static Future<bool> shouldCover() async {
    try {
      if (!await SecureUnlockService.isEnabled()) return false;
      // Never cover on a device that can't authenticate — there would be no way
      // to clear the lock and the user would be stranded.
      if (!await SecureUnlockService.isAvailable()) return false;
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString(SharedPrefsKeys.accessToken)?.trim() ?? '')
          .isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Recompute eligibility and push it to the native cover. Returns the value so
  /// callers can keep their own cached copy in step.
  static Future<bool> sync() async {
    final cover = await shouldCover();
    await setSecure(cover);
    return cover;
  }

  /// Tell native whether to protect the screen: on iOS this arms the cover shown
  /// on the next resign-active; on Android it toggles FLAG_SECURE so session
  /// content stays out of the recents preview (and screenshots).
  static Future<void> setSecure(bool value) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setSecure', value);
    } catch (e) {
      debugPrint('PrivacyCoverService.setSecure failed: $e');
    }
  }

  /// Take the native cover down. iOS-only: it removes the resign-active cover
  /// once Flutter's own lock overlay (or the real content, when no lock is
  /// required) has painted, so the handoff shows no exposed content. A no-op on
  /// Android, where FLAG_SECURE is a persistent window flag with nothing to hide.
  static Future<void> hideCover() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('hideCover');
    } catch (e) {
      debugPrint('PrivacyCoverService.hideCover failed: $e');
    }
  }
}
