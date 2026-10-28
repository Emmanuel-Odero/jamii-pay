import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type tokens matching `--display` (Bricolage Grotesque), `--ui` (Plus
/// Jakarta Sans), and `--mono` (JetBrains Mono) from the mockup, plus the
/// specific per-screen sizes used throughout it (`.scr-title`, `.bal`,
/// `.handle`, `.timer`, etc).
///
/// Bundled as local assets (`assets/fonts/`, see `pubspec.yaml` `fonts:`
/// and `tool/fetch_fonts.py`) — fully offline, zero first-paint FOUT on
/// cheap phones and patchy data. Weights resolve through the family
/// declarations, so call sites keep passing `FontWeight` normally.
abstract final class AppText {
  static const _displayFamily = 'BricolageGrotesque';
  static const _uiFamily = 'PlusJakartaSans';
  static const _monoFamily = 'JetBrainsMono';

  static TextStyle display({
    double size = 25,
    FontWeight weight = FontWeight.w800,
    Color? color,
    double? height,
  }) =>
      TextStyle(
        fontFamily: _displayFamily,
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink,
        letterSpacing: -0.025 * size,
        height: height,
      );

  static TextStyle ui({
    double size = 15,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
  }) =>
      TextStyle(
        fontFamily: _uiFamily,
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink,
        height: height,
      );

  static TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double letterSpacing = 0,
  }) =>
      TextStyle(
        fontFamily: _monoFamily,
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink,
        letterSpacing: letterSpacing,
      );

  /// `.scr-title` — the big headline at the top of most onboarding/flow
  /// screens.
  static TextStyle screenTitle({double size = 25}) =>
      display(size: size, height: 1.12);

  /// `.scr-sub` — never below 12.5 in practice; premium pass floors body
  /// copy at 13.5-14 so cheap-device users never squint at money copy.
  static TextStyle screenSub() =>
      ui(size: 14, color: AppColors.ink2, height: 1.55);

  /// `.eyebrow` — mono, uppercase, wide tracking, dim.
  static TextStyle eyebrow() => mono(
        size: 11,
        weight: FontWeight.w500,
        color: AppColors.ink3,
        letterSpacing: 0.18 * 11,
      );

  /// `.bal` — the big dollar figure.
  static TextStyle balance({double size = 41, Color? color}) => TextStyle(
        fontFamily: _displayFamily,
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.035 * size,
        height: 1.05,
        color: color ?? AppColors.ink,
      );

  /// `.bal-lbl`
  static TextStyle balanceLabel({Color? color}) => mono(
        size: 11,
        color: color ?? AppColors.ink3,
        letterSpacing: 0.12 * 11,
      );

  /// `.bal-alt` — the KES-equivalent line under a dollar balance.
  static TextStyle balanceAlt() =>
      mono(size: 12, color: AppColors.ink2, weight: FontWeight.w400);

  /// `.timer` — the recovery countdown.
  static TextStyle timer() => mono(
        size: 33,
        weight: FontWeight.w700,
        color: AppColors.amber,
        letterSpacing: -0.02 * 33,
      );
}
