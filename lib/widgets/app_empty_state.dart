import 'package:flutter/material.dart';

/// Centered "nothing here" state (icon + title + optional subtitle) used on
/// list screens — previously hand-rolled per screen with drifting icon
/// sizes, spacing, and text styles for the same concept.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconSize = 48,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: iconSize, color: Colors.black12),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black38,
          ),
          textAlign: TextAlign.center,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(fontSize: 12, color: Colors.black26),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
