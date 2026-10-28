import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'motion.dart';

/// `.card` and its `.sel` / `.grn` / `.cor` / `.amb` variants.
enum AppCardVariant { plain, selected, green, coral, amber }

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.variant = AppCardVariant.plain,
    this.padding = const EdgeInsets.all(15),
    this.onTap,
  });

  final Widget child;
  final AppCardVariant variant;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (Color border, Color fill) = switch (variant) {
      AppCardVariant.plain => (AppColors.line, AppColors.navy800),
      AppCardVariant.selected => (
          AppColors.blue,
          AppColors.blue.withValues(alpha: 0.102)
        ),
      AppCardVariant.green => (
          AppColors.green.withValues(alpha: 0.349),
          AppColors.green.withValues(alpha: 0.09)
        ),
      AppCardVariant.coral => (
          AppColors.coral.withValues(alpha: 0.349),
          AppColors.coral.withValues(alpha: 0.078)
        ),
      AppCardVariant.amber => (
          AppColors.amber.withValues(alpha: 0.349),
          AppColors.amber.withValues(alpha: 0.078)
        ),
    };

    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Haptics.select();
          onTap!();
        },
        borderRadius: BorderRadius.circular(kRadius),
        child: card,
      ),
    );
  }
}
