/// Convention-based multi-tenant routing helpers.
///
/// The app is fully open: every institutional email domain gets its own
/// backend/database, derived from the domain itself — there is NO hardcoded
/// list of tenants. A user signing in with `name@acme.com.ph` is routed to the
/// backend produced by [apiBaseUrlFor] for the domain `acme.com.ph`.
///
/// The URL shape is a single template (`https://eforward-api.{domain}/api` by
/// default, overridable per build via the `API_URL_TEMPLATE` env key), so new
/// tenants need zero code changes — just a reachable backend at that address.
class TenantResolver {
  TenantResolver._();

  /// Extracts the lowercase domain (the part after '@') from [email], or null
  /// when [email] has no usable, dotted domain (so `user@localhost` and
  /// malformed input don't get routed anywhere).
  static String? domainOf(String email) {
    final trimmed = email.trim().toLowerCase();
    final at = trimmed.lastIndexOf('@');
    if (at <= 0 || at == trimmed.length - 1) return null;
    final domain = trimmed.substring(at + 1);
    if (!domain.contains('.') || domain.startsWith('.') ||
        domain.endsWith('.')) {
      return null;
    }
    return domain;
  }

  /// Builds a backend base URL for [domain] from [template] by substituting
  /// every `{domain}` placeholder.
  static String apiBaseUrlFor(String domain, String template) =>
      template.replaceAll('{domain}', domain);
}
