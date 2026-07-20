/// Centralized [SharedPreferences] key names for session/session-adjacent
/// storage, so the same literal string isn't retyped across services/screens.
class SharedPrefsKeys {
  SharedPrefsKeys._();

  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String userData = 'user_data';
  static const String employeeId = 'employee_id';
  static const String fcmTokenCached = 'fcm_token_cached';

  /// Email domain of the tenant selected from the signed-in user's email,
  /// used to route the whole session to that tenant's backend API.
  static const String activeTenantDomain = 'active_tenant_domain';

  /// Deprecated: the previous brand-based routing key. Read once on startup to
  /// migrate old sessions to [activeTenantDomain]; no longer written.
  static const String legacyActiveBrand = 'active_brand';
}
