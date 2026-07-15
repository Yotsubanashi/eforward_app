/// Helpers to display backend timestamps in Philippine time (Asia/Manila).
///
/// The backend already stores and returns the value as Manila wall-clock time
/// (it appends a "Z" but the numbers are Manila, not real UTC). So the correct
/// behaviour is to show the clock value exactly as sent — NOT to run a UTC
/// conversion, which would shift it by the device/UTC offset.
class ManilaTime {
  ManilaTime._();

  static const Duration _offset = Duration(hours: 8);

  static final RegExp _timezoneSuffix = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

  /// Parses an API timestamp and returns a [DateTime] whose fields (year, hour,
  /// …) are exactly the values in the string. Any trailing timezone marker is
  /// dropped so the value is shown as-is. Do NOT call `.toLocal()`/`.toUtc()`
  /// on the result — that would re-introduce a shift.
  static DateTime? parse(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty || value == 'null') return null;

    // Accept both "2026-07-14 17:32:44" and the ISO "T" form, and drop the
    // timezone marker so the clock value is read verbatim.
    final normalized = value
        .replaceFirst(' ', 'T')
        .replaceFirst(_timezoneSuffix, '');
    try {
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  /// The current Manila wall-clock time, for relative-date comparisons and
  /// freshly-generated timestamps — correct on any device timezone.
  static DateTime now() => DateTime.now().toUtc().add(_offset);
}
