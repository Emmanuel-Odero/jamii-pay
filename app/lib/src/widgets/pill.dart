import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// `.pill` — used for the language/hero meta chips and the search filter
/// tabs (`All` / `Transactions` / ...).
class AppPill extends StatelessWidget {
  const AppPill(
      {super.key,
      required this.label,
      this.icon,
      this.selected = false,
      this.onTap});

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = selected ? AppColors.navy900 : AppColors.ink2;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.ink : Colors.transparent,
        border: Border.all(color: selected ? AppColors.ink : AppColors.line2),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style:
                AppText.mono(size: 11, letterSpacing: 0.55, color: textColor),
          ),
        ],
      ),
    );

    if (onTap == null) return pill;
    return GestureDetector(onTap: onTap, child: pill);
  }
}
