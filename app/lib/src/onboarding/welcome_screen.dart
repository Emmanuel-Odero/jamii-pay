import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_screen.dart';
import '../widgets/jamii_logo.dart';

/// Onboarding 1/7 — "Welcome". No mention of crypto, blockchain, or
/// wallets-as-technology: the product is presented as dollars you control.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen(
      {super.key, required this.onCreateWallet, required this.onHaveWallet});

  final VoidCallback onCreateWallet;
  final VoidCallback onHaveWallet;

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      scrollable: false,
      footer: Column(
        children: [
          AppButton(label: 'Create my wallet', onPressed: onCreateWallet),
          const SizedBox(height: 9),
          AppButton(
              label: 'I already have one',
              variant: AppButtonVariant.outline,
              onPressed: onHaveWallet),
          const SizedBox(height: 13),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 14, color: AppColors.ink3),
              const SizedBox(width: 6),
              Text(
                'Takes about two minutes · No ID needed',
                textAlign: TextAlign.center,
                style: AppText.ui(size: 12.5, color: AppColors.ink3),
              ),
            ],
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const JamiiLogo(size: 76),
            const SizedBox(height: 24),
            Text(
              'Pay simple.\nLive easy.',
              textAlign: TextAlign.center,
              style: AppText.screenTitle(size: 29),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                'Hold your money in US dollars. Send and receive anywhere. Only you hold the keys.',
                textAlign: TextAlign.center,
                style: AppText.screenSub(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
