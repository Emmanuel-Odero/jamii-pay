import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text.dart';

/// `--r: 14px` in the mockup — the standard card/screen corner radius.
const double kRadius = 14.0;
const double kBtnRadius = 11.0;

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.navy900,
    colorScheme: ColorScheme(
      brightness: AppColors.brightness,
      surface: AppColors.navy900,
      onSurface: AppColors.ink,
      primary: AppColors.blue,
      onPrimary: Colors.white,
      secondary: AppColors.green,
      onSecondary: AppColors.onGreen,
      error: AppColors.coral,
      onError: Colors.white,
    ),
    textTheme: TextTheme(
      bodyMedium: AppText.ui(),
      bodySmall: AppText.ui(size: 13, color: AppColors.ink2),
    ),
    dividerColor: AppColors.line,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.navy900,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    // Call sites used to set only `activeThumbColor`, leaving the track and
    // the "off" thumb on Material's stock colors — inconsistent on the two
    // light presets in particular, where the default track reads as a
    // similar grey to the surrounding card rather than a deliberate "off"
    // state. Themed once here so every `Switch` in the app (not just the
    // ones a call site remembered to style) follows the current palette.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.blue
            : AppColors.ink3,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.blue.withValues(alpha: 0.3)
            : AppColors.navy600,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}
