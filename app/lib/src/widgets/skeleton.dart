import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Skeleton placeholders — 2026 rule: skeletons show *structure*,
/// spinners show *nothing*. Every full-screen `CircularProgressIndicator`
/// for Group detail / Home / Notifications / Chat must become one of
/// these, with cached stale data underneath where available.
class SkeletonLine extends StatefulWidget {
  const SkeletonLine({super.key, this.width = double.infinity, this.height = 14, this.radius = 8});

  final double width;
  final double height;
  final double radius;

  @override
  State<SkeletonLine> createState() => _SkeletonLineState();
}

class _SkeletonLineState extends State<SkeletonLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            AppColors.navy700,
            AppColors.navy600,
            0.35 + 0.35 * _c.value,
          ),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 3});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navy800,
        border: Border.all(color: AppColors.line2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonLine(width: 120, height: 12),
          const SizedBox(height: 10),
          const SkeletonLine(width: 180, height: 26, radius: 8),
          for (var i = 0; i < lines; i++) ...[
            const SizedBox(height: 8),
            const SkeletonLine(height: 12),
          ],
        ],
      ),
    );
  }
}
