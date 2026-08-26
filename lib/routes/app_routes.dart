/// Named route constants for screens reachable with no or simple arguments.
///
/// Screens that need complex typed constructor arguments (e.g.
/// `ApprovalDetailPage`, `PdfSignerPage`, `ExcelFileViewerPage`,
/// `ResetPasswordScreen`) are intentionally not covered here — they keep
/// using direct `Navigator.push(MaterialPageRoute(...))` calls so their
/// arguments stay compile-time typed rather than cast from
/// `RouteSettings.arguments`.
class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String dashboard = '/dashboard';
  static const String approvals = '/approvals';
  static const String settings = '/settings';
  static const String sign = '/sign';
  static const String viewSign = '/view-sign';
  static const String notifications = '/notifications';
  static const String notificationSettings = '/notification-settings';
  static const String forgotPassword = '/forgot-password';
  static const String changePassword = '/change-password';
  static const String privacyPolicy = '/privacy-policy';
  static const String editProfile = '/edit-profile';
}
