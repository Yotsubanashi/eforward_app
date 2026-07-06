import 'package:flutter/material.dart';

/// Live "Passwords matched" / "Passwords do not match" message for a
/// New Password + Confirm Password field pair. Hidden while [confirmPassword]
/// is empty. Rebuild with the latest controller text on every keystroke in
/// either field to update live.
class PasswordMatchMessage extends StatelessWidget {
  final String newPassword;
  final String confirmPassword;

  const PasswordMatchMessage({
    super.key,
    required this.newPassword,
    required this.confirmPassword,
  });

  @override
  Widget build(BuildContext context) {
    if (confirmPassword.isEmpty) return const SizedBox.shrink();

    final matches = newPassword == confirmPassword;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        matches ? "Passwords matched" : "Passwords do not match",
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: matches ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
        ),
      ),
    );
  }
}
