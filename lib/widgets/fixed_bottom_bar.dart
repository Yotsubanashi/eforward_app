import 'package:flutter/material.dart';

/// Safe-area-aware footer that sits outside a screen's scrollable content
/// (as a sibling to `Expanded(child: SingleChildScrollView(...))` in a
/// `Column`), so [child] — typically a primary action button plus a
/// secondary link — stays pinned to the bottom of the screen instead of
/// floating in the scroll flow or getting pushed off by the keyboard.
class FixedBottomBar extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;

  const FixedBottomBar({
    super.key,
    required this.child,
    this.backgroundColor,
    this.padding = const EdgeInsets.fromLTRB(24, 8, 24, 16),
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(color: backgroundColor, padding: padding, child: child),
    );
  }
}
