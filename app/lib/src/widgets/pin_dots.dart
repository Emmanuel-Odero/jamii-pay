import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// `.pins` — six dots, filled left-to-right as the user types their PIN.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.filled, this.length = 6});

  final int filled;
  final int length;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++) ...[
          if (i != 0) const SizedBox(width: 11),
          Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? AppColors.blue : Colors.transparent,
              border: Border.all(
                  color: i < filled ? AppColors.blue : AppColors.line2,
                  width: 1.5),
            ),
          ),
        ],
      ],
    );
  }
}
