import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// `.banner` — an icon + one line of explanatory copy. Used everywhere the
/// design calls for stating a security rationale plainly on-screen instead
/// of hiding it in a help centre.
enum BannerTone { info, success, warning, danger }

class InfoBanner extends StatelessWidget {
  const InfoBanner(
      {super.key,
      required this.icon,
      required this.text,
      this.tone = BannerTone.success});

  final IconData icon;
  final String text;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color border, Color fill, Color iconColor) = switch (tone) {
      BannerTone.success => (
          AppColors.green.withValues(alpha: 0.302),
          AppColors.green.withValues(alpha: 0.09),
          AppColors.green
        ),
      BannerTone.warning => (
          AppColors.amber.withValues(alpha: 0.302),
          AppColors.amber.withValues(alpha: 0.09),
          AppColors.amber
        ),
      BannerTone.danger => (
          AppColors.coral.withValues(alpha: 0.302),
          AppColors.coral.withValues(alpha: 0.09),
          AppColors.coral
        ),
      BannerTone.info => (AppColors.line2, AppColors.navy800, AppColors.ink2),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style:
                    AppText.ui(size: 12, color: AppColors.ink2, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
