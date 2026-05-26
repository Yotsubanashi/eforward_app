import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  AppEnv._();

  static const String _defaultApiBaseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';
  static const String _defaultAppBaseUrl =
      'https://eforward.ardentnetworks.com.ph';
  static const String _defaultBrand = 'ARDENT';

  static final String apiBaseUrl = _readEnv('API_BASE_URL', _defaultApiBaseUrl);
  static final String appBaseUrl = _readEnv('APP_BASE_URL', _defaultAppBaseUrl);
  static final String appBrand = _readEnv(
    'APP_BRAND',
    _defaultBrand,
  ).toUpperCase();

  static Map<String, String> _brandingConfig(String brandKey) {
    switch (brandKey.toUpperCase()) {
      case 'VERSATECH':
        return {
          'name': 'E-FORWARD',
          'logo': 'assets/versa-logo.png',
          'color': '0xFF0056b3',
        };
      case 'ARDENT':
      default:
        return {
          'name': 'E-FORWARD',
          'logo': 'assets/ardent-logo-with-powering-innovation-8.webp',
          'color': '0xFFCC0000',
        };
    }
  }

  /// Returns branding based on the user's email domain, falling back to
  /// the current app brand (from `.env`) when the domain does not match.
  static Map<String, String> getBrandingForEmail(String email) {
    final lower = email.toLowerCase().trim();

    if (lower.endsWith('@versatech.com.ph')) {
      return _brandingConfig('VERSATECH');
    }
    if (lower.endsWith('@ardentnetworks.com.ph')) {
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
