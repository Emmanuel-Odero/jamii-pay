import 'package:flutter/material.dart';

/// Colour tokens — mirrors the four themes in
/// `designs/jammii-pay-prototype.html`'s `THEMES` array (`classic-dark`,
/// `classic-light`, `ocean-dark`, `ocean-light`; `mockup.html`'s static
/// `:root` block is exactly `classic-dark`'s values, which is why this
/// used to be `const`). Fields are mutable and repointed by
/// [ThemeStore.setPreset] so every screen picks up a new palette on the
/// next rebuild — nothing here holds the *current* theme, it holds
/// whatever theme was last applied.
abstract final class AppColors {
  static Color navy900 = _classicDark.navy900;
  static Color navy800 = _classicDark.navy800;
  static Color navy700 = _classicDark.navy700;
  static Color navy600 = _classicDark.navy600;

  static Color line = _classicDark.line;
  static Color line2 = _classicDark.line2;

  static Color ink = _classicDark.ink;
  static Color ink2 = _classicDark.ink2;
  static Color ink3 = _classicDark.ink3;

  static Color blue = _classicDark.blue;
  static Color green = _classicDark.green;
  static Color coral = _classicDark.coral;
  static Color amber = _classicDark.amber;

  /// Text colour that sits on top of `green`-filled surfaces (buttons,
  /// check marks).
  static Color onGreen = _classicDark.onGreen;

  static Brightness brightness = _classicDark.brightness;

  static void apply(AppPalette palette) {
    brightness = palette.brightness;
    navy900 = palette.navy900;
    navy800 = palette.navy800;
    navy700 = palette.navy700;
    navy600 = palette.navy600;
    line = palette.line;
    line2 = palette.line2;
    ink = palette.ink;
    ink2 = palette.ink2;
    ink3 = palette.ink3;
    blue = palette.blue;
    green = palette.green;
    coral = palette.coral;
    amber = palette.amber;
    onGreen = palette.onGreen;
  }
}

enum AppThemePreset {
  classicDark('classic-dark', 'Classic Dark'),
  classicLight('classic-light', 'Classic Light'),
  oceanDark('ocean-dark', 'Ocean Dark'),
  oceanLight('ocean-light', 'Ocean Light');

  const AppThemePreset(this.id, this.label);
  final String id;
  final String label;

  AppPalette get palette => switch (this) {
        AppThemePreset.classicDark => _classicDark,
        AppThemePreset.classicLight => _classicLight,
        AppThemePreset.oceanDark => _oceanDark,
        AppThemePreset.oceanLight => _oceanLight,
      };

  static AppThemePreset fromId(String? id) => AppThemePreset.values
      .firstWhere((p) => p.id == id, orElse: () => AppThemePreset.classicDark);
}

/// One theme's full token set — field names match `AppColors` 1:1. `--surf`
/// / `--surf2` / `--surf3` in the prototype map to `navy800`/`navy700`/
/// `navy600`; `--bg` maps to `navy900`; `--good`/`--warn`/`--alert` map to
/// `green`/`amber`/`coral`. The prototype's `--info` (its "blue" role) maps
/// to `blue`, which is what this app actually uses for primary buttons —
/// the prototype's own `--pri` (green) is a different semantic than what
/// `mockup.html` implements, and this app follows the mockup for button
/// colour, not the prototype's `--pri` naming.
class AppPalette {
  const AppPalette({
    required this.navy900,
    required this.navy800,
    required this.navy700,
    required this.navy600,
    required this.line,
    required this.line2,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.blue,
    required this.green,
    required this.coral,
    required this.amber,
    required this.onGreen,
    required this.brightness,
  });

  final Color navy900, navy800, navy700, navy600;
  final Color line, line2;
  final Color ink, ink2, ink3;
  final Color blue, green, coral, amber;
  final Color onGreen;
  final Brightness brightness;
}

const _classicDark = AppPalette(
  navy900: Color(0xFF0B1224),
  navy800: Color(0xFF15213B),
  navy700: Color(0xFF1B2942),
  navy600: Color(0xFF243553),
  line: Color(0x17FFFFFF),
  line2: Color(0x2BFFFFFF),
  ink: Color(0xFFEEF3FB),
  ink2: Color(0xFFA4B3CE),
  ink3: Color(0xFF6E7F9F),
  blue: Color(0xFF2F80ED),
  green: Color(0xFF3ECF7E),
  coral: Color(0xFFFF5E3A),
  amber: Color(0xFFFFC53D),
  onGreen: Color(0xFF0A2419),
  brightness: Brightness.dark,
);

const _classicLight = AppPalette(
  navy900: Color(0xFFF4F6FA),
  navy800: Color(0xFFFFFFFF),
  navy700: Color(0xFFEDF1F7),
  navy600: Color(0xFFDFE5EF),
  line: Color(0x1A101B33),
  line2: Color(0x33101B33),
  ink: Color(0xFF101B33),
  ink2: Color(0xFF4C5B76),
  ink3: Color(0xFF8593AC),
  blue: Color(0xFF1E6FD9),
  green: Color(0xFF12945A),
  coral: Color(0xFFD93A18),
  amber: Color(0xFFA9760A),
  onGreen: Color(0xFFFFFFFF),
  brightness: Brightness.light,
);

const _oceanDark = AppPalette(
  navy900: Color(0xFF0D1B2B),
  navy800: Color(0xFF16293F),
  navy700: Color(0xFF1E3550),
  navy600: Color(0xFF284566),
  line: Color(0x1AFFFFFF),
  line2: Color(0x30FFFFFF),
  ink: Color(0xFFEAF3FC),
  ink2: Color(0xFF9DB6D2),
  ink3: Color(0xFF6883A3),
  blue: Color(0xFF4DA3FF),
  green: Color(0xFF3ECF7E),
  coral: Color(0xFFFF7050),
  amber: Color(0xFFFFC53D),
  onGreen: Color(0xFF06231A),
  brightness: Brightness.dark,
);

const _oceanLight = AppPalette(
  navy900: Color(0xFFEDF4FC),
  navy800: Color(0xFFFFFFFF),
  navy700: Color(0xFFDEEBF9),
  navy600: Color(0xFFC9DEF4),
  line: Color(0x1A0D2033),
  line2: Color(0x330D2033),
  ink: Color(0xFF0D2033),
  ink2: Color(0xFF42607E),
  ink3: Color(0xFF7A93AE),
  blue: Color(0xFF1E6FD9),
  green: Color(0xFF12945A),
  coral: Color(0xFFD93A18),
  amber: Color(0xFFA9760A),
  onGreen: Color(0xFFFFFFFF),
  brightness: Brightness.light,
);
