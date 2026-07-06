import 'dart:ui';

import 'package:flutter/material.dart';

import 'loaders.dart';

/// The single loading indicator style used everywhere in the app: a
/// blurred, slightly darkened backdrop (the screen behind stays visible)
/// with the app's branded pulsing-dots spinner centered on top.
///
/// Usage: wrap a screen's Scaffold in a Stack and add
/// `if (isLoading) const LoadingOverlay()` as the last child.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          color: Colors.black.withOpacity(0.15),
          child: const Center(
            child: PulsingDotsLoader(color: Color(0xFFCC0000), dotSize: 14),
          ),
        ),
      ),
    );
  }
}
