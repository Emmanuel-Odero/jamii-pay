import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'motion.dart';

/// `.nav` + `.back` — the small back-button-and-title header used at the
/// top of most non-tab screens. Distinct from a Material `AppBar` so it can
/// match the mockup's exact 30x30 rounded-square back button.
///
/// Pass [step]/[totalSteps] on a multi-screen flow (onboarding, restore) to
/// show a "how much is left" dot trail beneath the title — without it, a
/// 7-screen flow gives no sense of progress beyond "keep tapping Continue".
class ScreenNav extends StatelessWidget {
  const ScreenNav(
      {super.key,
      this.title,
      this.onBack,
      this.trailing,
      this.step,
      this.totalSteps});

  final String? title;
  final VoidCallback? onBack;

  /// Optional right-aligned slot — e.g. Group Detail's "Chat" shortcut.
  /// Additive-only: every existing call site (no `trailing`) is unchanged.
  final Widget? trailing;

  /// 1-indexed current step, paired with [totalSteps]. Omit both to get the
  /// old behaviour (no progress trail).
  final int? step;
  final int? totalSteps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onBack != null)
                Semantics(
                  button: true,
                  label: 'Back',
                  child: InkWell(
                    onTap: () {
                      Haptics.select();
                      onBack!();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.line2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppColors.ink2, size: 16),
                    ),
                  ),
                ),
              if (title != null) ...[
                const SizedBox(width: 11),
                Expanded(
                    child: Text(title!,
                        style: AppText.ui(size: 15, weight: FontWeight.w600))),
              ] else
                const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          if (step != null && totalSteps != null) ...[
            const SizedBox(height: 12),
            Semantics(
              label: 'Step $step of $totalSteps',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    for (var i = 0; i < totalSteps!; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 6,
                          decoration: BoxDecoration(
                            color: i < step!
                                ? AppColors.blue
                                : AppColors.line2,
                            borderRadius: BorderRadius.circular(99),
                            boxShadow: i < step! - 1
                                ? null
                                : (i == step! - 1
                                    ? [
                                        BoxShadow(
                                          color: AppColors.blue
                                              .withValues(alpha: 0.4),
                                          blurRadius: 8,
                                        )
                                      ]
                                    : null),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
