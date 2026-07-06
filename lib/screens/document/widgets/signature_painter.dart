import 'package:flutter/material.dart';

/// Freehand signature stroke renderer shared by the draw-signature (sign)
/// and view-signature screens — previously duplicated as a private class
/// in each.
class SignaturePainter extends CustomPainter {
  final List<List<Offset?>> strokes;
  final Color penColor;

  SignaturePainter(this.strokes, {this.penColor = const Color(0xFF1A1A1A)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = penColor
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      final path = Path();
      bool started = false;
      for (final point in stroke) {
        if (point == null) {
          started = false;
        } else if (!started) {
          path.moveTo(point.dx, point.dy);
          started = true;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}
