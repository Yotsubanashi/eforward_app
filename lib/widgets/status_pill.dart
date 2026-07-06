import 'package:flutter/material.dart';

/// Status badge (PENDING / APPROVED / CANCELLED / OPEN) used on the
/// dashboard, approvals list, and approval detail screens — previously each
/// screen hand-rolled its own color/label mapping and pill markup with
/// slightly different padding/radius/opacity.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

  static Color colorFor(String status) {
    switch (status.toUpperCase().trim()) {
      case 'CNL':
        return const Color(0xFFCC0000);
      case 'APV':
        return Colors.green;
      case 'PND':
        return Colors.orange;
      case 'OPN':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  static String labelFor(String status) {
    switch (status.toUpperCase().trim()) {
      case 'PND':
        return 'PENDING';
      case 'APV':
        return 'APPROVED';
      case 'OPN':
        return 'OPEN';
      case 'CNL':
        return 'CANCELLED';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.20), width: 0.5),
      ),
      child: Text(
        labelFor(status),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: color,
        ),
      ),
    );
  }
}
