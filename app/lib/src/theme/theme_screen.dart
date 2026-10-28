import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/screen_nav.dart';
import 'app_colors.dart';
import 'app_text.dart';
import 'theme_store.dart';

/// Settings → "Appearance" — the theme picker from
/// `designs/jammii-pay-prototype.html`'s `SCR.setTheme` (four themes:
/// Classic Dark/Light, Ocean Dark/Light), which had no equivalent anywhere
/// in this app before. Each card previews the theme's own two-swatch
/// background/surface pair before it's selected, the same way the
/// prototype's `.sw` swatch does.
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ThemeStore>();

    return AppScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Appearance', onBack: onBack),
          Text('Pick a look', style: AppText.screenTitle(size: 22)),
          const SizedBox(height: 8),
          Text('Change it any time in Settings.', style: AppText.screenSub()),
          const SizedBox(height: 14),
          for (final preset in AppThemePreset.values) ...[
            _ThemeCard(
              preset: preset,
              selected: preset == store.preset,
              onTap: () => store.setPreset(preset),
            ),
            const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard(
      {required this.preset, required this.selected, required this.onTap});

  final AppThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = preset.palette;
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        variant: selected ? AppCardVariant.selected : AppCardVariant.plain,
        child: Row(
          children: [
            // The two-swatch preview — background colour with a smaller
            // surface-colour chip and the theme's accent colour on top,
            // matching the prototype's `.sw`/`i` swatch markup.
            Container(
              width: 48,
              height: 48,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: palette.navy900,
                  borderRadius: BorderRadius.circular(10)),
              child: Stack(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                        color: palette.navy600,
                        borderRadius: BorderRadius.circular(5)),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                          color: palette.blue, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(preset.label,
                  style: AppText.ui(size: 13.5, weight: FontWeight.w700)),
            ),
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.green : Colors.transparent,
                border: Border.all(
                    color: selected ? AppColors.green : AppColors.line2,
                    width: 1.5),
                shape: BoxShape.circle,
              ),
              child: selected
                  ? Icon(Icons.check, size: 14, color: AppColors.onGreen)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
