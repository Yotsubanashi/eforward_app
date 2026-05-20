import 'package:flutter/material.dart';

class PulsingDotsLoader extends StatefulWidget {
  final Color color;
  final double dotSize;

  const PulsingDotsLoader({
    super.key,
    this.color = Colors.white,
    this.dotSize = 8,
  });

  @override
  State<PulsingDotsLoader> createState() => _PulsingDotsLoaderState();
}

class _PulsingDotsLoaderState extends State<PulsingDotsLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delay = index * 0.2;
            double value = (_controller.value - delay) % 1.0;
            if (value < 0) value += 1.0;

            final scale = 1.0 + (0.5 * (1.0 - (value - 0.5).abs() * 2));
            final opacity = 0.3 + (0.7 * (1.0 - (value - 0.5).abs() * 2));

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: widget.dotSize * scale,
              height: widget.dotSize * scale,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(opacity.clamp(0.0, 1.0)),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}

class LoadingDialog extends StatelessWidget {
  final String message;

  const LoadingDialog({super.key, this.message = "PLEASE WAIT..."});

  static void show(BuildContext context, {String message = "PLEASE WAIT..."}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => LoadingDialog(message: message),
    );
  }

  static void hide(BuildContext context) {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PulsingDotsLoader(
                color: Color(0xFFCC0000),
                dotSize: 12,
              ),
              const SizedBox(height: 24),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
