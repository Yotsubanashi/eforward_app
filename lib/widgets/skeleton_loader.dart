import 'package:flutter/material.dart';

/// Lightweight, dependency-free "skeleton" placeholder — a soft pulsing
/// grey box used to sketch out a card's shape while its real content loads,
/// instead of a bare spinner replacing the whole list.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 4,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.35,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: const Color(0xFFE8E8E8),
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
          ),
        );
      },
    );
  }
}

/// Placeholder shaped like an [ApprovalCard] row, shown while the real list
/// is loading.
class SkeletonApprovalCard extends StatelessWidget {
  const SkeletonApprovalCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              SkeletonBox(width: 70, height: 11),
              SizedBox(width: 8),
              SkeletonBox(width: 60, height: 16, borderRadius: 4),
            ],
          ),
          const SizedBox(height: 14),
          const SkeletonBox(width: double.infinity, height: 14),
          const SizedBox(height: 8),
          const SkeletonBox(width: 160, height: 11),
        ],
      ),
    );
  }
}

/// A column of [count] [SkeletonApprovalCard]s, used as a list's loading
/// state.
class SkeletonApprovalList extends StatelessWidget {
  const SkeletonApprovalList({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const SkeletonApprovalCard(),
    );
  }
}
