/// Centralized [SharedPreferences] key names for session/session-adjacent
/// storage, so the same literal string isn't retyped across services/screens.
class SharedPrefsKeys {
  SharedPrefsKeys._();

  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String userData = 'user_data';
  static const String employeeId = 'employee_id';
  static const String fcmTokenCached = 'fcm_token_cached';

  /// Brand ('ARDENT' | 'VERSATECH') selected from the signed-in user's email
  /// domain, used to route the whole session to the correct backend API.
  static const String activeBrand = 'active_brand';
}
