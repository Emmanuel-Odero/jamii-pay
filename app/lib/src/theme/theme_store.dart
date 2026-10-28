import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

/// Owns the active [AppThemePreset], applies it to [AppColors] (which every
/// screen reads directly, statically — see that file's doc comment), and
/// persists the choice. Deliberately separate from `SessionStorage`:
/// appearance is a device preference, not wallet-session data, so it must
/// survive sign-out.
class ThemeStore extends ChangeNotifier {
  ThemeStore([SharedPreferencesAsync? prefs])
      : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;
  static const _key = 'jamiipay.theme_preset';

  AppThemePreset preset = AppThemePreset.classicDark;

  /// Reads the persisted preset (if any) and applies it. Call once, before
  /// `runApp`, so the very first frame is already in the right theme rather
  /// than flashing classic-dark and then switching.
  Future<void> load() async {
    final id = await _prefs.getString(_key);
    preset = AppThemePreset.fromId(id);
    AppColors.apply(preset.palette);
  }

  Future<void> setPreset(AppThemePreset next) async {
    if (next == preset) return;
    preset = next;
    AppColors.apply(next.palette);
    notifyListeners();
    await _prefs.setString(_key, next.id);
  }
}
