import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'app_loading.dart';
import 'motion.dart';

/// `.btn-p` (primary/blue), `.btn-g` (green), `.btn-o` (outline).
///
/// [dangerOutline] — a coral-bordered, coral-text, transparent-background
/// button for a cautionary-but-not-final action (request a withdrawal,
/// stop a recovery, cancel something). Used to be hand-rolled with the
/// same `OutlinedButton` + `AppColors.coral.withValues(alpha: 0.4)` border
/// in three separate places (`SavingsScreen`, `RecoveryStartScreen`,
/// `RecoveryWaitingScreen`) before being promoted here.
enum AppButtonVariant { primary, green, outline, danger, dangerOutline }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;

  /// Busy state: button disables and the label pulses — no spinner.
  /// Pass the in-progress verb via [label] (e.g. "Sending…").
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isLoading ? null : onPressed;
    final (Color background, Color foreground, Border? border) =
        switch (variant) {
      AppButtonVariant.primary => (AppColors.blue, Colors.white, null),
      AppButtonVariant.green => (AppColors.green, AppColors.onGreen, null),
      AppButtonVariant.outline => (
          Colors.transparent,
          AppColors.ink2,
          Border.all(color: AppColors.line2),
        ),
      AppButtonVariant.danger => (AppColors.coral, Colors.white, null),
      AppButtonVariant.dangerOutline => (
          Colors.transparent,
          AppColors.coral,
          Border.all(color: AppColors.coral.withValues(alpha: 0.4)),
        ),
    };

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        elevation: effectiveOnPressed == null
            ? 0
            : (variant == AppButtonVariant.primary ||
                    variant == AppButtonVariant.green
                ? 6
                : 0),
        shadowColor: effectiveOnPressed == null
            ? Colors.transparent
            : AppColors.blue.withValues(alpha: 0.3),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: effectiveOnPressed == null
              ? null
              : () {
                  Haptics.select();
                  effectiveOnPressed();
                },
          child: Container(
            decoration: BoxDecoration(
              border: border,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: Opacity(
              opacity: effectiveOnPressed == null ? 0.45 : 1.0,
              child: isLoading
                  ? BusyLabel(text: label, color: foreground)
                  : Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppText.ui(
                          size: 14.5,
                          weight: FontWeight.w700,
                          color: foreground),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
