/// Simple non-empty/required-field checks used across auth forms.
class RequiredFieldValidator {
  RequiredFieldValidator._();

  static bool isEmpty(String value) => value.trim().isEmpty;

  static bool anyEmpty(List<String> values) =>
      values.any((value) => value.trim().isEmpty);
}
