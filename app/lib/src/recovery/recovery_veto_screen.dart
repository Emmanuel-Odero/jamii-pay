import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/row_line.dart';

/// Recovery R4 — the veto, seen by the real owner. Sent to every registered
/// channel — push, SMS, and email — ignoring quiet hours. This is the one
/// notification that overrides user preferences, deliberately.
class RecoveryVetoScreen extends StatelessWidget {
  const RecoveryVetoScreen({
    super.key,
    required this.startedLabel,
    required this.completesLabel,
    required this.onStopRecovery,
    required this.onThisWasMe,
  });

  final String startedLabel;
  final String completesLabel;
  final VoidCallback onStopRecovery;
  final VoidCallback onThisWasMe;

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      scrollable: false,
      footer: Column(
        children: [
          AppButton(
              label: 'Stop this recovery',
              variant: AppButtonVariant.danger,
              onPressed: onStopRecovery),
          const SizedBox(height: 9),
          AppButton(
              label: 'This was me',
              variant: AppButtonVariant.outline,
              onPressed: onThisWasMe),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.coral.withValues(alpha: 0.149),
                border:
                    Border.all(color: AppColors.coral.withValues(alpha: 0.502)),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_amber_rounded,
                  size: 38, color: AppColors.coral),
            ),
            const SizedBox(height: 22),
            Text(
              'Someone is trying to recover your wallet',
              textAlign: TextAlign.center,
              style: AppText.screenTitle(size: 24)
                  .copyWith(color: AppColors.coral),
            ),
            const SizedBox(height: 12),
            Text(
              'A recovery request was started at 11:32 today from a device in Nairobi. If this wasn\'t you, '
              'stop it now.',
              textAlign: TextAlign.center,
              style: AppText.screenSub(),
            ),
            const SizedBox(height: 16),
            AppCard(
              variant: AppCardVariant.coral,
              child: Column(
                children: [
                  RowLine(label: 'Started', value: startedLabel),
                  const RowLine(label: 'Approved by', value: '2 of 3'),
                  RowLine(
                      label: 'Completes',
                      value: completesLabel,
                      valueColor: AppColors.amber,
                      showBorder: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
