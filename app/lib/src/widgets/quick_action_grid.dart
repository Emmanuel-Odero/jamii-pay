import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'motion.dart';

/// `.qa` — the 4-up quick action row on the wallet home screen (Receive /
/// Send / Cash out / Pay bill).
///
/// Premium pass (Rec #3): 56px cells, 22px icons in tinted pills, 12.5px
/// labels, spring press (scale 0.97 + haptic via [Pressable]). `badge`
/// marks honest placeholders ("Soon") with a muted style so dead actions
/// never masquerade as live money moves.
class QuickAction {
  const QuickAction(
      {required this.icon,
      required this.label,
      this.tint,
      this.badge,
      this.onTap});
  final IconData icon;
  final String label;
  final Color? tint;
  final String? badge;
  final VoidCallback? onTap;
}

class QuickActionGrid extends StatelessWidget {
  const QuickActionGrid({super.key, required this.actions});

  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final action in actions) ...[
          if (action != actions.first) const SizedBox(width: 8),
          Expanded(
            child: Pressable(
              onTap: action.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                decoration: BoxDecoration(
                  color: action.badge != null
                      ? AppColors.navy800.withValues(alpha: 0.6)
                      : AppColors.navy800,
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: (action.tint ?? AppColors.ink)
                                .withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(action.icon,
                              size: 22,
                              color: action.badge != null
                                  ? AppColors.ink3
                                  : (action.tint ?? AppColors.ink)),
                        ),
                        if (action.badge != null)
                          Positioned(
                            top: -6,
                            right: -14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.navy600,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(action.badge!,
                                  style: AppText.mono(
                                      size: 9,
                                      weight: FontWeight.w700,
                                      color: AppColors.ink3)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      action.label,
                      textAlign: TextAlign.center,
                      style: AppText.ui(
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: action.badge != null
                              ? AppColors.ink3
                              : AppColors.ink2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
