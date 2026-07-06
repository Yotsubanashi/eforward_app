import 'package:flutter/material.dart';

/// Small uppercase "eyebrow" heading used above grouped content sections
/// (e.g. "DOCUMENT INFORMATION", "SECURITY REQUIREMENTS") — previously
/// hand-typed with the same TextStyle in ~10 places across the app.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color = Colors.black45});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: color,
      ),
    );
  }
}
