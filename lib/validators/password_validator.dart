/// Centralized password strength rules — previously duplicated verbatim
/// across the reset-password and change-password screens.
class PasswordValidator {
  PasswordValidator._();

  static bool hasMinLength(String password) => password.length >= 8;

  static bool hasNumber(String password) => password.contains(RegExp(r'[0-9]'));

  static bool hasSpecialChar(String password) =>
      password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

  static bool hasUppercase(String password) =>
      password.contains(RegExp(r'[A-Z]'));

  static bool hasLowercase(String password) =>
      password.contains(RegExp(r'[a-z]'));

  static bool hasMixedCase(String password) =>
      hasUppercase(password) && hasLowercase(password);

  static bool meetsRequirements(String password) =>
      hasMinLength(password) &&
      hasNumber(password) &&
      hasSpecialChar(password) &&
      hasMixedCase(password);
}
