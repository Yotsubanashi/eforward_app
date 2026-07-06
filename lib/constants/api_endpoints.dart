/// Centralized backend API endpoint paths (relative to [AppEnv.apiBaseUrl]).
///
/// Static paths are constants; paths with path segments are helper methods
/// so call sites don't hand-build interpolated strings.
class ApiEndpoints {
  ApiEndpoints._();

  // ─── Auth ───────────────────────────────────────────────────────────────
  static const String mobileLogin = '/auth/mobile-login';
  static const String verifyOtp = '/auth/verify-otp';
  static const String resendOtp = '/auth/resend-otp';
  static const String forgotPassword = '/auth/forgotPassword';
  static const String verifyResetToken = '/auth/verifyToken';
  static const String resetPassword = '/auth/resetPassword';
  static const String changePassword = '/auth/changePassword';
  static const String logout = '/auth/logout';
  static const String refresh = '/auth/refresh';
  static const String me = '/auth/me';

  // ─── Users ──────────────────────────────────────────────────────────────
  static String user(String employeeId) => '/users/$employeeId';
  static const String fcmToken = '/users/fcm-token';

  // ─── Signature / uploads ────────────────────────────────────────────────
  static const String uploadSignature = '/upload/signature';
  static const String signatureImage = '/upload/signature/image';
  static String uploadDocument(String fileId) => '/upload/document/$fileId';

  // ─── App version ────────────────────────────────────────────────────────
  static const String appVersion = '/app/version';

  // ─── Notifications ──────────────────────────────────────────────────────
  static const String unreadCount = '/notifications/unread-count';
  static const String markAllRead = '/notifications/read-all';
  static const String notificationsList = '/notifications';
  static String markRead(String notificationId) =>
      '/notifications/$notificationId/read';

  // ─── Approvals ──────────────────────────────────────────────────────────
  static const String approvalsPending = '/approvals/pending';
  static const String approvalsHistory = '/approvals/history';
  static String approvalRevision(String id) => '/approvals/$id/revision';
  static String approvalRouting(String id) => '/approvals/$id/routing';
  static String approvalApprove(String id) => '/approvals/$id/approve';
  static String requestAttachment(String routingId) =>
      '/approvals/$routingId/request-attachment';
  static String documentLinks(String routingId) =>
      '/routing/$routingId/document-links';
}
