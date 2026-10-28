import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// `.pbar` — a stacked horizontal percentage bar, one coloured segment per
/// `(fraction, color)` pair. `fraction`s need not sum to 1 — any
/// remainder renders as unfilled track (`AppColors.navy600`). Used for
/// Group detail's voting-power split and Group vote's approve/withhold/
/// veto share.
class SegmentedBar extends StatelessWidget {
  const SegmentedBar({super.key, required this.segments, this.height = 8});

  final List<(double fraction, Color color)> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (sum, s) => sum + s.$1);
    final remainder = (1 - total).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final (fraction, color) in segments)
              if (fraction > 0)
                Expanded(
                    flex: (fraction * 1000).round().clamp(1, 1000),
                    child: Container(color: color)),
            // Explicit trailing segment for "not yet accounted for" — the
            // colored segments would otherwise stretch to fill 100% via
            // Expanded's flex, hiding that a bar is only partially filled.
            if (remainder > 0)
              Expanded(
                  flex: (remainder * 1000).round().clamp(1, 1000),
                  child: Container(color: AppColors.navy600)),
          ],
        ),
      ),
    );
  }
}
