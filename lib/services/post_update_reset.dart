import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eforward_app/services/api/auth_api.dart';

/// Post-update sign-out. On every launch we compare the installed app version
/// to the one recorded on the last launch. If it changed — the user just
/// installed a new build — we wipe the stored session so they have to sign
/// in again. New builds may change the auth contract (claims, token format,
/// endpoints), so stale credentials shouldn't carry across upgrades.
///
/// Fails open: any error (missing PackageInfo, prefs not ready, etc.) just
/// skips the reset. Never blocks launch.
class PostUpdateReset {
  PostUpdateReset._();

  static const _kLastLaunchedVersion = 'last_launched_version';

  /// Call once from `main()` BEFORE `runApp`.
  static Future<void> runIfVersionChanged() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version.trim();
      if (current.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_kLastLaunchedVersion);

      if (last != null && last.isNotEmpty && last != current) {
        debugPrint('[PostUpdateReset] version changed $last → $current, '
            'clearing session');
        await AuthApi().clearSession();
      }
      await prefs.setString(_kLastLaunchedVersion, current);
    } catch (e) {
      debugPrint('[PostUpdateReset] skipped: $e');
    }
  }
}
