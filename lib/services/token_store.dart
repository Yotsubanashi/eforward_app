import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eforward_app/constants/shared_prefs_keys.dart';

/// Holds the session's access/refresh tokens in the platform keystore (iOS
/// Keychain / Android Keystore) instead of plain SharedPreferences.
///
/// Values are cached in memory after the first read so the many call sites
/// that need the bearer token don't each hit the keystore. Older builds kept
/// the tokens in SharedPreferences; [init] moves them over once and deletes
/// the plaintext copies.
class TokenStore {
  TokenStore._();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _accessKey = 'session_access_token';
  static const _refreshKey = 'session_refresh_token';

  static String _access = '';
  static String _refresh = '';
  static Future<void>? _loading;

  /// Loads the tokens and migrates any legacy SharedPreferences copies. Call
  /// once from `main()` before anything reads a token; later reads also await
  /// it, so calling it is an optimisation rather than a requirement.
  static Future<void> init() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      _access = (await _storage.read(key: _accessKey))?.trim() ?? '';
      _refresh = (await _storage.read(key: _refreshKey))?.trim() ?? '';
    } catch (e) {
      debugPrint('TokenStore read failed: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final legacyAccess =
          prefs.getString(SharedPrefsKeys.legacyAccessToken)?.trim() ?? '';
      final legacyRefresh =
          prefs.getString(SharedPrefsKeys.legacyRefreshToken)?.trim() ?? '';
      if (_access.isEmpty && legacyAccess.isNotEmpty) {
        await _write(_accessKey, legacyAccess);
        _access = legacyAccess;
      }
      if (_refresh.isEmpty && legacyRefresh.isNotEmpty) {
        await _write(_refreshKey, legacyRefresh);
        _refresh = legacyRefresh;
      }
      await prefs.remove(SharedPrefsKeys.legacyAccessToken);
      await prefs.remove(SharedPrefsKeys.legacyRefreshToken);
    } catch (e) {
      debugPrint('TokenStore legacy migration failed: $e');
    }
  }

  /// The current access token, or '' when signed out.
  static Future<String> accessToken() async {
    await init();
    return _access;
  }

  /// The current refresh token, or '' when none is stored.
  static Future<String> refreshToken() async {
    await init();
    return _refresh;
  }

  /// Stores whichever tokens are given. Blank values are ignored so a response
  /// that omits the refresh token doesn't wipe the stored one.
  static Future<void> save({String? accessToken, String? refreshToken}) async {
    await init();
    final access = accessToken?.trim() ?? '';
    final refresh = refreshToken?.trim() ?? '';
    if (access.isNotEmpty) {
      _access = access;
      await _write(_accessKey, access);
    }
    if (refresh.isNotEmpty) {
      _refresh = refresh;
      await _write(_refreshKey, refresh);
    }
  }

  static Future<void> clear() async {
    await init();
    _access = '';
    _refresh = '';
    try {
      await _storage.delete(key: _accessKey);
      await _storage.delete(key: _refreshKey);
    } catch (e) {
      debugPrint('TokenStore clear failed: $e');
    }
  }

  // A keystore failure keeps the in-memory value, so the current session keeps
  // working; it just won't survive an app restart.
  static Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('TokenStore write failed: $e');
    }
  }

  /// Pulls the access token out of a login / verify-otp / refresh response.
  static String? accessTokenFrom(Map<String, dynamic>? data) =>
      _find(data, const ['accessToken', 'access_token', 'token']);

  /// Pulls the refresh token out of a login / verify-otp / refresh response.
  static String? refreshTokenFrom(Map<String, dynamic>? data) =>
      _find(data, const ['refreshToken', 'refresh_token']);

  // Checks the top level, then one level deep (e.g. data['data']['token']).
  static String? _find(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) return null;
    for (final key in keys) {
      final val = data[key];
      if (val is String && val.trim().isNotEmpty) return val.trim();
    }
    for (final value in data.values) {
      if (value is Map<String, dynamic>) {
        for (final key in keys) {
          final val = value[key];
          if (val is String && val.trim().isNotEmpty) return val.trim();
        }
      }
    }
    return null;
  }
}
