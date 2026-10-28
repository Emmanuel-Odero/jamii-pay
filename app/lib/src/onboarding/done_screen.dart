import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_screen.dart';
import '../widgets/handle_chip.dart';

/// Onboarding 7/7 — "Ready". The first action offered is sharing, not
/// exploring: a wallet with nothing in it has one job, which is getting
/// somebody to send something to it.
class DoneScreen extends StatelessWidget {
  const DoneScreen(
      {super.key,
      required this.handleBase,
      required this.handleCheckDigit,
      required this.onShare,
      required this.onGoToWallet});

  final String handleBase;
  final String handleCheckDigit;
  final VoidCallback onShare;
  final VoidCallback onGoToWallet;

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      scrollable: false,
      footer: Column(
        children: [
          AppButton(
              label: 'Go to my wallet',
              variant: AppButtonVariant.green,
              onPressed: onGoToWallet),
          const SizedBox(height: 8),
          AppButton(
              label: 'Share my payment name',
              variant: AppButtonVariant.outline,
              onPressed: onShare),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 86,
              height: 86,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.149),
                border:
                    Border.all(color: AppColors.green.withValues(alpha: 0.451)),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check, size: 40, color: AppColors.green),
            ),
            const SizedBox(height: 22),
            Text("You're set up",
                style: AppText.screenTitle(), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                'Your payment name is ready. Fund it with M-Pesa to bring your wallet to life — money arrives in ~15 seconds.',
                textAlign: TextAlign.center,
                style: AppText.screenSub(),
              ),
            ),
            const SizedBox(height: 12),
            HandleChip(
                base: handleBase,
                checkDigit: handleCheckDigit,
                size: HandleChipSize.large,
                copyable: true),
          ],
        ),
      ),
    );
  }
}
