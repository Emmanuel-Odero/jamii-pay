import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_screen.dart';
import '../widgets/screen_nav.dart';

/// Onboarding 4/7 — "Add your fingerprint". Genuinely skippable: shared
/// devices and worn fingerprints from manual work would be silently
/// excluded by a hard requirement here.
class BiometricScreen extends StatelessWidget {
  const BiometricScreen(
      {super.key,
      required this.onBack,
      required this.onEnable,
      required this.onSkip});

  final VoidCallback onBack;
  final VoidCallback onEnable;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      scrollable: false,
      footer: Column(
        children: [
          AppButton(label: 'Enable fingerprint', onPressed: onEnable),
          const SizedBox(height: 9),
          AppButton(
              label: 'Not now',
              variant: AppButtonVariant.outline,
              onPressed: onSkip),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(onBack: onBack, step: 3, totalSteps: 5),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 98,
                    height: 98,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.129),
                      border: Border.all(
                          color: AppColors.blue.withValues(alpha: 0.4)),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.fingerprint,
                        size: 46, color: AppColors.blue),
                  ),
                  const SizedBox(height: 22),
                  Text('Faster unlocking',
                      style: AppText.screenTitle(),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Text(
                      'Use your fingerprint instead of typing your PIN each time. Your PIN still works as a backup.',
                      textAlign: TextAlign.center,
                      style: AppText.screenSub(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
