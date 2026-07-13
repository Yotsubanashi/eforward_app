/// Institutional email-domain rules shared by login access control
/// ([EmailValidator.isKnownInstitutionalDomain]) and per-domain backend /
/// branding selection (`AppEnv.brandForEmail`, `AppEnv.getBrandingForEmail`) —
/// so the same domain suffixes aren't hardcoded independently in each place.
class EmailValidator {
  EmailValidator._();

  static const String ardentDomain = '@ardentnetworks.com.ph';
  static const String versatechDomain = '@versatech.com.ph';

  static bool isArdentDomain(String email) =>
      email.toLowerCase().trim().endsWith(ardentDomain);

  static bool isVersatechDomain(String email) =>
      email.toLowerCase().trim().endsWith(versatechDomain);

  /// Whether [email] belongs to either supported institution (Ardent or
  /// Versatech). Used by the unified single-build login to allow both.
  static bool isKnownInstitutionalDomain(String email) =>
      isArdentDomain(email) || isVersatechDomain(email);
}
