import 'package:flutter/material.dart';

import '../data/session_storage.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_screen.dart';
import '../widgets/option_card.dart';
import '../widgets/screen_nav.dart';

class _Language {
  const _Language(this.code, this.name, this.nativeName);
  final String code;
  final String name;
  final String nativeName;
}

/// Onboarding 2/7 — "Choose a language". Kiswahili, Somali, and Arabic are
/// launch languages (not translations bolted on later) — they map to the
/// largest refugee populations in Kenya.
class LanguageScreen extends StatefulWidget {
  const LanguageScreen(
      {super.key,
      required this.onBack,
      required this.onContinue,
      this.onLanguageSelected,
      this.initialCode = 'EN',
      this.continueLabel = 'Continue',
      this.showStep = true});

  final VoidCallback onBack;
  final ValueChanged<String>? onLanguageSelected;
  final VoidCallback onContinue;

  /// Preselects the saved choice when opened from Settings (rather than
  /// always defaulting to English mid-onboarding).
  final String initialCode;

  /// Settings uses a softer commit label than onboarding's march forward.
  final String continueLabel;

  /// Hidden when reused outside onboarding (no "step 1 of 5" there).
  final bool showStep;

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  static const _languages = [
    _Language('EN', 'English', 'English'),
    _Language('SW', 'Kiswahili', 'Kiswahili'),
    _Language('SO', 'Soomaali', 'Af-Soomaali'),
    _Language('AR', 'Arabic', 'العربية'),
    _Language('FR', 'French', 'Français'),
  ];

  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialCode;
  }

  Future<void> _select(String code) async {
    setState(() => _selected = code);
    // Persist immediately — previously discarded (dead selection).
    await const SessionStorage().saveLanguage(code);
    await const SessionStorage().saveOnboardingStep('language:$code');
    widget.onLanguageSelected?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      footer: AppButton(
          label: widget.continueLabel, onPressed: widget.onContinue),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showStep)
            ScreenNav(onBack: widget.onBack, step: 1, totalSteps: 5)
          else
            ScreenNav(title: 'Language', onBack: widget.onBack),
          Text('Your language', style: AppText.screenTitle()),
          const SizedBox(height: 8),
          Text(
            widget.showStep
                ? 'You can change this any time from Settings → Language.'
                : 'Applies across JamiiPay immediately.',
            style: AppText.screenSub(),
          ),
          for (final language in _languages) ...[
            OptionCard(
              badgeText: language.code,
              iconBackground: language.code == _selected
                  ? AppColors.blue.withValues(alpha: 0.2)
                  : AppColors.navy600,
              iconColor:
                  language.code == _selected ? AppColors.blue : AppColors.ink2,
              title: language.name,
              description: language.nativeName,
              selected: language.code == _selected,
              onTap: () => _select(language.code),
            ),
            const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}
