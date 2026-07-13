import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/constants/shared_prefs_keys.dart';
import 'package:eforward_app/validators/email_validator.dart';

class AppEnv {
  AppEnv._();

  static const String _defaultApiBaseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';
  static const String _defaultVersaApiBaseUrl =
      'https://eforward-api.versatech.com.ph/api';
  static const String _defaultAppBaseUrl =
      'https://eforward.ardentnetworks.com.ph';
  static const String _defaultBrand = 'ARDENT';

  /// Per-brand backend API URLs. In a unified single build BOTH are shipped,
  /// and the active one is chosen from the signed-in user's email domain.
  static final String ardentApiBaseUrl = _readEnv(
    'API_BASE_URL',
    _defaultApiBaseUrl,
  );
  static final String versaApiBaseUrl = _readEnv(
    'API_VERSA_BASE_URL',
    _defaultVersaApiBaseUrl,
  );

  static final String appBaseUrl = _readEnv('APP_BASE_URL', _defaultAppBaseUrl);
  static final String appBrand = _readEnv(
    'APP_BRAND',
    _defaultBrand,
  ).toUpperCase();

  /// Runtime-selected backend for the current session (chosen from the user's
  /// email domain at login and restored on startup). Null → fall back to the
  /// env/default brand's backend.
  static String? _activeApiBaseUrl;

  /// Active backend URL used by ALL API calls. This is a getter so every
  /// screen/service that reads `AppEnv.apiBaseUrl` automatically follows the
  /// backend selected for the signed-in user.
  static String get apiBaseUrl =>
      _activeApiBaseUrl ?? apiBaseUrlForBrand(appBrand);

  /// Backend API URL for a brand key ('ARDENT' | 'VERSATECH').
  static String apiBaseUrlForBrand(String brand) {
    switch (brand.toUpperCase().trim()) {
      case 'VERSATECH':
        return versaApiBaseUrl;
      case 'ARDENT':
      default:
        return ardentApiBaseUrl;
    }
  }

  /// Brand key ('ARDENT' | 'VERSATECH') for the given email's domain.
  static String brandForEmail(String email) =>
      EmailValidator.isVersatechDomain(email) ? 'VERSATECH' : 'ARDENT';

  /// Backend API URL for the given email's domain.
  static String apiBaseUrlForEmail(String email) =>
      apiBaseUrlForBrand(brandForEmail(email));

  /// Selects and persists the backend for the whole session based on [email].
  /// Call this right before the login request so login and every subsequent
  /// API call hit the correct backend.
  static Future<void> selectBackendForEmail(String email) async {
    final brand = brandForEmail(email);
    _activeApiBaseUrl = apiBaseUrlForBrand(brand);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SharedPrefsKeys.activeBrand, brand);
  }

  /// Restores the persisted session backend on app startup. Must run in
  /// `main()` before any API call (e.g. the startup `getMe` session check).
  static Future<void> restoreActiveBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final brand = prefs.getString(SharedPrefsKeys.activeBrand);
    if (brand != null && brand.trim().isNotEmpty) {
      _activeApiBaseUrl = apiBaseUrlForBrand(brand);
    }
  }

  /// Clears the selected backend on logout so the next user re-selects.
  static Future<void> clearActiveBackend() async {
    _activeApiBaseUrl = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SharedPrefsKeys.activeBrand);
  }

  static Map<String, String> _brandingConfig(String brandKey) {
    switch (brandKey.toUpperCase()) {
      case 'VERSATECH':
        return {
          'name': 'E-FORWARD',
          'logo': 'assets/eforward-logo.png',
          'color': '0xFF0056b3',
        };
      case 'ARDENT':
      default:
        return {
          'name': 'E-FORWARD',
          'logo': 'assets/eforward-logo.png',
          'color': '0xFFCC0000',
        };
    }
  }

  /// Returns branding based on the user's email domain, falling back to
  /// the current app brand (from `.env`) when the domain does not match.
  static Map<String, String> getBrandingForEmail(String email) {
    if (EmailValidator.isVersatechDomain(email)) {
      return _brandingConfig('VERSATECH');
    }
    if (EmailValidator.isArdentDomain(email)) {
      return _brandingConfig('ARDENT');
    }

    // No specific domain match – use the active app brand from environment.
    return _brandingConfig(appBrand);
  }

  /// Default branding for the running app (env-driven).
  static Map<String, String> get defaultBranding => _brandingConfig(appBrand);

  /// Returns the correct watermark asset path for the active brand.
  static String get watermarkAsset {
    switch (appBrand) {
      case 'VERSATECH':
        return 'assets/images/versa-watermarks.png';
      case 'ARDENT':
      default:
        return 'assets/images/eforward_watermark.png';
    }
  }

  static String _readEnv(String key, String fallback) {
    final value = dotenv.env[key]?.trim() ?? '';
    return value.isNotEmpty ? value : fallback;
  }
}
