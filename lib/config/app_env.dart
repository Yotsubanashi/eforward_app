import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/constants/shared_prefs_keys.dart';
import 'package:eforward_app/config/tenant.dart';

/// Environment + per-tenant backend resolution.
///
/// Backends are NOT listed anywhere — each tenant's API URL is derived from the
/// signed-in user's email domain via [TenantResolver] and a single URL
/// template. See [selectBackendForEmail].
class AppEnv {
  AppEnv._();

  static const String _defaultApiUrlTemplate =
      'https://eforward-api.{domain}/api';
  static const String _defaultDomain = 'ardentnetworks.com.ph';
  static const String _defaultAppBaseUrl =
      'https://eforward.ardentnetworks.com.ph';

  static final String appBaseUrl = _readEnv('APP_BASE_URL', _defaultAppBaseUrl);

  /// Template used to derive every tenant's backend from its email domain.
  /// `{domain}` → the part after '@'. Override per build with `API_URL_TEMPLATE`.
  static final String _apiUrlTemplate = _readEnv(
    'API_URL_TEMPLATE',
    _defaultApiUrlTemplate,
  );

  /// Domain used before any tenant is selected (app's own default). Override
  /// per build with `APP_DEFAULT_DOMAIN`.
  static final String _fallbackDomain = _readEnv(
    'APP_DEFAULT_DOMAIN',
    _defaultDomain,
  );

  /// Runtime-selected backend for the current session (chosen from the user's
  /// email domain at login and restored on startup). Null → fall back to the
  /// default domain's backend.
  static String? _activeApiBaseUrl;

  /// Email domain of the current session, used to pick per-domain branding
  /// assets (e.g. the signature watermark). Null before a tenant is selected.
  static String? _activeDomain;

  /// Active backend URL used by ALL API calls. This is a getter so every
  /// screen/service that reads `AppEnv.apiBaseUrl` automatically follows the
  /// backend selected for the signed-in user.
  static String get apiBaseUrl =>
      _activeApiBaseUrl ?? _urlForDomain(_fallbackDomain);

  static String _urlForDomain(String domain) =>
      TenantResolver.apiBaseUrlFor(domain, _apiUrlTemplate);

  /// Backend API URL for the given email's domain (falls back to the default
  /// domain when [email] has no usable domain).
  static String apiBaseUrlForEmail(String email) =>
      _urlForDomain(TenantResolver.domainOf(email) ?? _fallbackDomain);

  /// Selects and persists the backend for the whole session based on [email].
  /// Call this right before the login request so login and every subsequent
  /// API call hit the correct backend.
  static Future<void> selectBackendForEmail(String email) async {
    final domain = TenantResolver.domainOf(email) ?? _fallbackDomain;
    _activeApiBaseUrl = _urlForDomain(domain);
    _activeDomain = domain;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SharedPrefsKeys.activeTenantDomain, domain);
  }

  /// Restores the persisted session backend on app startup. Must run in
  /// `main()` before any API call (e.g. the startup `getMe` session check).
  static Future<void> restoreActiveBackend() async {
    final prefs = await SharedPreferences.getInstance();
    var domain = prefs.getString(SharedPrefsKeys.activeTenantDomain)?.trim();

    // Migrate sessions saved by the previous brand-based build so already
    // signed-in users keep hitting their own backend after this update.
    if (domain == null || domain.isEmpty) {
      final legacyBrand = prefs
          .getString(SharedPrefsKeys.legacyActiveBrand)
          ?.trim()
          .toUpperCase();
      final migrated = _legacyBrandDomains[legacyBrand];
      if (migrated != null) {
        domain = migrated;
        await prefs.setString(SharedPrefsKeys.activeTenantDomain, migrated);
        await prefs.remove(SharedPrefsKeys.legacyActiveBrand);
      }
    }

    if (domain != null && domain.isNotEmpty) {
      _activeApiBaseUrl = _urlForDomain(domain);
      _activeDomain = domain;
    }
  }

  /// Clears the selected backend on logout so the next user re-selects.
  static Future<void> clearActiveBackend() async {
    _activeApiBaseUrl = null;
    _activeDomain = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SharedPrefsKeys.activeTenantDomain);
    await prefs.remove(SharedPrefsKeys.legacyActiveBrand);
  }

  /// One-time domain mapping for sessions persisted by the old brand-based
  /// build. Not part of routing — only used to migrate the stored value.
  static const Map<String, String> _legacyBrandDomains = {
    'ARDENT': 'ardentnetworks.com.ph',
    'VERSATECH': 'versatech.com.ph',
  };

  // ─── Branding assets ────────────────────────────────────────────────────
  // Routing is fully domain-derived and open. Branding assets (logo, color,
  // signature watermark) must be bundled in the build, so a domain only gets a
  // custom look if it ships one here — every other domain uses the E-Forward
  // default. This map does NOT gate access or routing; unknown domains still
  // log in and route normally, just with default branding.

  static const Map<String, String> _defaultAssets = {
    'name': 'E-FORWARD',
    'logo': 'assets/eforward-logo.png',
    'color': '0xFFCC0000',
    'watermark': 'assets/images/eforward_watermark.png',
  };

  /// Per-domain branding-asset overrides. Add an entry only for a domain that
  /// ships its own bundled assets.
  static const Map<String, Map<String, String>> _domainAssets = {
    'ardentnetworks.com.ph': _defaultAssets,
    'versatech.com.ph': {
      'name': 'E-FORWARD',
      'logo': 'assets/eforward-logo.png',
      'color': '0xFF0056b3',
      'watermark': 'assets/images/versa-watermarks.png',
    },
  };

  static Map<String, String> _assetsForDomain(String? domain) =>
      _domainAssets[domain] ?? _defaultAssets;

  static Map<String, String> _brandingOf(Map<String, String> assets) => {
    'name': assets['name']!,
    'logo': assets['logo']!,
    'color': assets['color']!,
  };

  /// Default branding for the running app (no tenant selected yet).
  static Map<String, String> get defaultBranding =>
      _brandingOf(_assetsForDomain(_activeDomain));

  /// Branding for a given email, resolved from its domain.
  static Map<String, String> getBrandingForEmail(String email) =>
      _brandingOf(_assetsForDomain(TenantResolver.domainOf(email)));

  /// Signature watermark asset for the current session's domain.
  static String get watermarkAsset =>
      _assetsForDomain(_activeDomain)['watermark']!;

  static String _readEnv(String key, String fallback) {
    final value = dotenv.env[key]?.trim() ?? '';
    return value.isNotEmpty ? value : fallback;
  }
}
