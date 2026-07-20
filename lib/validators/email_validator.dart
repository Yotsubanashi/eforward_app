import 'package:eforward_app/config/tenant.dart';

/// Email-domain rules for login access control.
///
/// The app is open to any institutional domain — access is granted to any email
/// with a usable, routable domain, and that domain decides which backend the
/// session talks to (see [TenantResolver] / `AppEnv.selectBackendForEmail`).
class EmailValidator {
  EmailValidator._();

  /// Whether [email] has a usable domain the app can route to. Returns false
  /// only for malformed emails with no dotted domain part.
  static bool isKnownInstitutionalDomain(String email) =>
      TenantResolver.domainOf(email) != null;
}
