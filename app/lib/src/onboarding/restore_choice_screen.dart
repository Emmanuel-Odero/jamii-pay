import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_screen.dart';
import '../widgets/option_card.dart';
import '../widgets/screen_nav.dart';

/// Reached from Welcome's "I already have one" — the fork between the two
/// ways to get back into an existing wallet: the guardian-approval flow
/// (R1-R4, `recovery_flow.dart`) or a wallet key downloaded during
/// onboarding (`RestoreFromKeyScreen`). Neither is presented as the
/// "real" path — whichever the person actually set up is the right one.
///
/// Visual language matches the premium `WalletKeyBackupScreen`
/// certificate: the wallet-key option is a navy + gold card that looks
/// like the backup it asks for, so people recognise it instantly.
class RestoreChoiceScreen extends StatelessWidget {
  const RestoreChoiceScreen({
    super.key,
    required this.onBack,
    required this.onRestoreFromKey,
    required this.onGuardianRecovery,
  });

  final VoidCallback onBack;
  final VoidCallback onRestoreFromKey;
  final VoidCallback onGuardianRecovery;

  static const _gold = Color(0xFFC8A96A);

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Restore your wallet', onBack: onBack),
          Text('JAMIIPAY • ACCOUNT RECOVERY',
              style: AppText.mono(
                  size: 11,
                  weight: FontWeight.w700,
                  color: _gold,
                  letterSpacing: 1.8)),
          const SizedBox(height: 8),
          Text('How do you want to get back in?',
              style: AppText.screenTitle(size: 22)),
          const SizedBox(height: 8),
          Text('Pick whichever you set up when you first created this wallet.',
              style: AppText.screenSub()),
          const SizedBox(height: 16),
          // Hero option — mirrors the backup certificate (navy gradient,
          // gold hairline, QR medallion) so the person recognises the
          // file they saved or printed.
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onRestoreFromKey,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.navy800, AppColors.navy900],
                  ),
                  border: Border.all(color: _gold.withValues(alpha: 0.55)),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _gold.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.qr_code_2,
                          size: 20, color: _gold),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Restore from wallet key',
                              style: AppText.ui(
                                  size: 13.5, weight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                              'Upload the navy + gold QR certificate you saved, then enter its key PIN and your wallet PIN.',
                              style: AppText.ui(
                                  size: 11.5,
                                  color: AppColors.ink2,
                                  height: 1.45)),
                          const SizedBox(height: 8),
                          Text('NEEDS: BACKUP IMAGE + KEY PIN',
                              style: AppText.mono(
                                  size: 10,
                                  weight: FontWeight.w700,
                                  color: _gold,
                                  letterSpacing: 1.2)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(Icons.chevron_right,
                          size: 20, color: _gold),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          OptionCard(
            icon: Icons.shield_outlined,
            iconBackground: AppColors.green.withValues(alpha: 0.18),
            iconColor: AppColors.green,
            title: 'Use recovery guardians',
            description:
                'Get approval from two of the three recovery methods you set up.',
            selected: false,
            onTap: onGuardianRecovery,
          ),
        ],
      ),
    );
  }
}
