import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'app_card.dart';

/// `.opt` — an icon, a title + description, and a trailing checkmark or
/// radio. Used for language choice, recovery-method choice, etc.
class OptionCard extends StatelessWidget {
  const OptionCard({
    super.key,
    this.icon,
    this.badgeText,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.selected,
    this.onTap,
  }) : assert(icon != null || badgeText != null,
            'OptionCard needs either an icon or a badgeText');

  /// A vector icon for the leading badge — used everywhere except language
  /// choice, which shows a two-letter code (see [badgeText]) instead.
  final IconData? icon;

  /// A short text badge (e.g. a language code like "EN") shown instead of
  /// [icon] when the option is better represented as text than a glyph.
  final String? badgeText;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '$title. $description',
      child: AppCard(
        variant: selected ? AppCardVariant.selected : AppCardVariant.plain,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(10)),
                child: icon != null
                    ? Icon(icon, size: 17, color: iconColor)
                    : Text(badgeText!,
                        style: AppText.ui(
                            size: 12,
                            weight: FontWeight.w800,
                            color: iconColor)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppText.ui(size: 13.5, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(description,
                        style: AppText.ui(
                            size: 11.5, color: AppColors.ink2, height: 1.45)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Container(
                  width: 19,
                  height: 19,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.green : Colors.transparent,
                    border: Border.all(
                        color: selected ? AppColors.green : AppColors.line2,
                        width: 1.5),
                    shape: BoxShape.circle,
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 13, color: AppColors.onGreen)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
