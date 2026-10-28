import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// Themed toast — the app's answer to the default `SnackBar`, which is
/// always white-on-white-ish and font-mismatched no matter what theme is
/// active. Every transient confirmation ("Contributed $25.00", "Sent to
/// everyone", …) should go through this, not a raw `Text('✓ …')` inside a
/// stock `SnackBar` — see [InfoBanner] for the same tone/icon language
/// used on persistent, in-page banners.
enum SnackTone { success, warning, danger, info }

abstract final class AppSnackBar {
  static void show(BuildContext context,
      {required String message,
      IconData? icon,
      SnackTone tone = SnackTone.success,
      String? actionLabel,
      VoidCallback? onAction,
      Duration? duration}) {
    final (Color accent, IconData defaultIcon) = switch (tone) {
      SnackTone.success => (AppColors.green, Icons.check_circle_outline),
      SnackTone.warning => (AppColors.amber, Icons.warning_amber_rounded),
      SnackTone.danger => (AppColors.coral, Icons.error_outline),
      SnackTone.info => (AppColors.ink2, Icons.info_outline),
    };

    // Money confirmations stay longer (8s) so receipt IDs can be noted;
    // transient info keeps 4s. Never leak raw exceptions: callers must
    // pass user-friendly copy.
    final effectiveDuration =
        duration ?? (tone == SnackTone.success || actionLabel != null
            ? const Duration(seconds: 8)
            : const Duration(seconds: 4));

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navy800,
          duration: effectiveDuration,
          action: actionLabel == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  textColor: accent,
                  onPressed: onAction ?? () {},
                ),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kRadius),
              side: BorderSide(color: AppColors.line2)),
          elevation: 0,
          content: Row(
            children: [
              Icon(icon ?? defaultIcon, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(message,
                      style: AppText.ui(
                          size: 13,
                          color: AppColors.ink,
                          weight: FontWeight.w600))),
            ],
          ),
        ),
      );
  }

  /// User-friendly money-error wrapper — strips Dart exception noise
  /// (`FormatException: ...`, paths) that used to leak via `$e`.
  static void showMoneyError(BuildContext context, String what) {
    show(context,
        message: '$what. Please check and try again.',
        tone: SnackTone.danger);
  }
}
