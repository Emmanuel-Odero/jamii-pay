import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// `.rowline` — a key/value line inside a card (fee breakdowns, recovery
/// approval status, etc).
class RowLine extends StatelessWidget {
  const RowLine(
      {super.key,
      required this.label,
      required this.value,
      this.valueColor,
      this.showBorder = true});

  final String label;
  final String value;
  final Color? valueColor;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: showBorder
            ? Border(bottom: BorderSide(color: AppColors.line))
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.ui(size: 12.5, color: AppColors.ink2)),
          Text(value,
              style: AppText.mono(
                  size: 12,
                  weight: FontWeight.w600,
                  color: valueColor ?? AppColors.ink)),
        ],
      ),
    );
  }
}
