import 'package:flutter/material.dart';

/// Consistent floating/rounded [SnackBar] used across the whole app —
/// previously every screen built its own [SnackBar] inline, and only one
/// screen (forgot password) used the floating/rounded treatment.
class AppSnackbar {
  AppSnackbar._();

  static const Color errorColor = Color(0xFFCC0000);
  static const Color successColor = Color(0xFF2E7D32);

  static void _show(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Neutral/informational toast — keeps SnackBar's own default background
  /// (used where the original code didn't set a color).
  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(context, message, duration: duration);
  }

  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(context, message, backgroundColor: errorColor, duration: duration);
  }

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(context, message, backgroundColor: successColor, duration: duration);
  }

  static void custom(
    BuildContext context,
    String message, {
    required Color backgroundColor,
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(
      context,
      message,
      backgroundColor: backgroundColor,
      duration: duration,
    );
  }
}
