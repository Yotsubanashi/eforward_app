import 'package:flutter/material.dart';

/// Centered "something went wrong" state (icon + message + optional retry
/// button) used on list screens — previously the only screen with a
/// designed error state was Approvals; others just showed a bare SnackBar.
class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 48, color: Color(0xFFCC0000)),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(fontSize: 13, color: Colors.black45),
          textAlign: TextAlign.center,
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFCC0000),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text(
              "RETRY",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
