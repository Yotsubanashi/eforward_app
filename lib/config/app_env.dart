import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  AppEnv._();

  static const String _defaultApiBaseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';
  static const String _defaultAppBaseUrl =
      'https://eforward.ardentnetworks.com.ph';

  static final String apiBaseUrl = _readEnv('API_BASE_URL', _defaultApiBaseUrl);
  static final String appBaseUrl = _readEnv('APP_BASE_URL', _defaultAppBaseUrl);

  static String _readEnv(String key, String fallback) {
    final value = dotenv.env[key]?.trim() ?? '';
    return value.isNotEmpty ? value : fallback;
  }
}
