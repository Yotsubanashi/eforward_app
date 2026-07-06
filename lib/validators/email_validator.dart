/// Institutional email-domain rules shared by login access control
/// ([EmailValidator.isAllowedForBrand]) and branding lookup
/// (`AppEnv.getBrandingForEmail`) — previously the same domain suffixes
/// were hardcoded independently in both places.
class EmailValidator {
  EmailValidator._();

  static const String ardentDomain = '@ardentnetworks.com.ph';
  static const String versatechDomain = '@versatech.com.ph';

  static bool isArdentDomain(String email) =>
      email.toLowerCase().trim().endsWith(ardentDomain);

  static bool isVersatechDomain(String email) =>
      email.toLowerCase().trim().endsWith(versatechDomain);

  /// Whether [email] is allowed to log in on a build for [brand]
  /// (e.g. `'ARDENT'` or `'VERSATECH'`).
  static bool isAllowedForBrand(String email, String brand) {
    final normalizedEmail = email.toLowerCase().trim();
    final activeBrand = brand.toUpperCase().trim();

    switch (activeBrand) {
      case 'ARDENT':
        return normalizedEmail.endsWith(ardentDomain) ||
            normalizedEmail.endsWith(versatechDomain);

      case 'VERSATECH':
        // Versa build serves both Versatech and Ardent users.
        return normalizedEmail.endsWith(versatechDomain) ||
            normalizedEmail.endsWith(ardentDomain);
      default:
        return true;
    }
  }
}
