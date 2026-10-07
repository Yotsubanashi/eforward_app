import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles the leftover install created when the Android [applicationId] was
/// renamed from `com.example.eforward_app` to `com.ardentnetworks.eforward`.
///
/// A package rename can never upgrade in place, so devices that had the old
/// build keep it as a second, orphaned icon after installing the new one. This
/// service detects that old package from inside the new app and offers to
/// uninstall it, so the user is left with a single app.
class LegacyAppService {
  LegacyAppService._();

  static const _channel = MethodChannel('eforward/legacy');

  /// The app's previous applicationId, now orphaned on upgraded devices.
  static const String legacyPackageName = 'com.example.eforward_app';

  static const String _promptedKey = 'legacy_app_prompted';

  /// True only the first time the old app is found: the prompt is shown once
  /// per install. If the user keeps the old app, we don't nag them again.
  static Future<bool> shouldPrompt() async {
    if (!Platform.isAndroid) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_promptedKey) ?? false) return false;
    } catch (e) {
      debugPrint('legacy prompt flag read failed: $e');
    }
    return isLegacyInstalled();
  }

  static Future<void> markPrompted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_promptedKey, true);
    } catch (e) {
      debugPrint('legacy prompt flag write failed: $e');
    }
  }

  static Future<bool> isLegacyInstalled() async {
    if (!Platform.isAndroid) return false;
    try {
      final installed = await _channel.invokeMethod<bool>(
        'isPackageInstalled',
        {'package': legacyPackageName},
      );
      return installed ?? false;
    } catch (e) {
      debugPrint('isLegacyInstalled failed: $e');
      return false;
    }
  }

  /// Opens the system uninstall dialog for the old package.
  static Future<void> launchLegacyUninstall() async {
    if (!Platform.isAndroid) return;
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.DELETE',
        data: 'package:$legacyPackageName',
      );
      await intent.launch();
    } catch (e) {
      debugPrint('launchLegacyUninstall failed: $e');
    }
  }
}

/// One-time prompt asking the user to remove the orphaned old app. Returns after
/// the dialog is dismissed; the actual uninstall happens in the system UI.
Future<void> showRemoveLegacyAppDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(
          Icons.delete_sweep_rounded,
          color: Color(0xFFCC0000),
          size: 36,
        ),
        title: const Text(
          'Remove the old app',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'An older copy of E-Forward is still installed on this device. '
          'It no longer receives updates. Remove it so you only have one '
          'E-Forward app.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFCC0000),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              LegacyAppService.launchLegacyUninstall();
            },
            child: const Text('Remove old app'),
          ),
        ],
      );
    },
  );
}
