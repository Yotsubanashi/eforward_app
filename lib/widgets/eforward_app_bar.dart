import 'package:flutter/material.dart';

/// Shared app bar (back button + uppercase title + "E-FORWARD" brand chip)
/// used across most screens — previously copy-pasted verbatim in ~8 files.
///
/// Each screen still supplies its own [backgroundColor] since several
/// screens intentionally match it to their Scaffold body color for a
/// seamless look, while others contrast it — unifying that choice is a
/// separate, higher-risk visual decision left for a future pass.
class EForwardAppBar extends StatelessWidget implements PreferredSizeWidget {
  const EForwardAppBar({
    super.key,
    this.title,
    required this.backgroundColor,
    this.onBackPressed,
    this.showBackButton = true,
    this.foregroundColor = const Color(0xFF1A1A1A),
  });

  final String? title;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onBackPressed;
  final bool showBackButton;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: backgroundColor,
      elevation: 0,
      automaticallyImplyLeading: showBackButton,
      leading: showBackButton
          ? IconButton(
              icon: Icon(Icons.arrow_back, color: foregroundColor, size: 20),
              onPressed: onBackPressed ?? () => Navigator.pop(context),
            )
          : null,
      title: title == null
          ? null
          : Text(
              title!,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: foregroundColor,
              ),
            ),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 16),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: Color(0xFFCC0000), size: 16),
              SizedBox(width: 4),
              Text(
                "E-FORWARD",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: Color(0xFFCC0000),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
