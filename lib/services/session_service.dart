/// Pure helpers for interpreting the decoded `user_data` payload — the
/// backend sometimes nests the user under a `user` key and sometimes
/// returns it flat, and the employee id has been sent under a few different
/// key names over time. Previously this normalization was duplicated
/// wherever `user_data` was read (auth session bootstrap, logout).
class SessionService {
  SessionService._();

  static Map<String, dynamic> normalizeUser(Map<String, dynamic> decoded) {
    // The user object arrives under `data` (the /auth/me refresh response),
    // under `user` (the login response), or flat. Check in that order so a
    // persisted+refreshed session resolves the same fields as a fresh login.
    final data = decoded['data'];
    if (data is Map<String, dynamic>) return data;
    final user = decoded['user'];
    return user is Map<String, dynamic> ? user : decoded;
  }

  static String? extractEmployeeId(Map<String, dynamic> user) {
    return user['id']?.toString() ??
        user['employee_id']?.toString() ??
        user['employeeId']?.toString();
  }
}
