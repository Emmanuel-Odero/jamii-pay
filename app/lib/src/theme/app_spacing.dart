/// Spacing tokens — the layout-rhythm equivalent of [AppColors]/[AppText].
///
/// Before this existed, every screen picked its own `SizedBox`/padding
/// values freehand (8, 9, 11, 12, 14, 16, 18, 20, 24 all showed up across
/// the app with no shared scale), so vertical rhythm drifted screen to
/// screen for no reason other than which value a given screen happened to
/// reach for. This is a standard 4px-based scale — new screens should pick
/// from here rather than a fresh literal; existing screens can be migrated
/// opportunistically without a single disruptive rewrite.
abstract final class AppSpacing {
  /// Tightest gap — between an icon and its adjacent label, for example.
  static const double xs = 4;

  /// Default gap between closely related elements (a row's internal gap).
  static const double sm = 8;

  /// Gap between a label and the control it describes.
  static const double md = 12;

  /// Standard gap between stacked sections within a card or list.
  static const double lg = 16;

  /// Gap above a screen's primary call-to-action or footer.
  static const double xl = 20;

  /// Gap between distinct sections of a screen (e.g. header → body).
  static const double xxl = 24;

  /// Largest gap — above a screen's primary call-to-action, or separating
  /// unrelated blocks entirely.
  static const double xxxl = 32;
}
