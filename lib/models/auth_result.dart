/// Result of a signature fetch — success carries either raw image bytes
/// (decoded from base64) or a hosted image URL, depending on what the
/// backend returned.
class SignatureResult {
  const SignatureResult({
    required this.isSuccess,
    required this.statusCode,
    required this.message,
    this.imageBytes,
    this.imageUrl,
    this.rawDate,
    this.data,
  });

  final bool isSuccess;
  final int statusCode;
  final String message;
  final List<int>? imageBytes;
  final String? imageUrl;
  final String? rawDate;
  final dynamic data;
}

/// Generic result wrapper returned by [AuthApi] calls.
class AuthLoginResult {
  const AuthLoginResult({
    required this.isSuccess,
    required this.statusCode,
    required this.message,
    this.data,
    this.requiredOTP = false,
  });

  final bool isSuccess;
  final int statusCode;
  final String message;
  final Map<String, dynamic>? data;
  final bool requiredOTP;
}
