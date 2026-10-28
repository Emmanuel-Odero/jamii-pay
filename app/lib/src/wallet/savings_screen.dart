import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/eternity_refresh.dart';
import '../widgets/app_screen.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/jamii_logo.dart';
import '../widgets/screen_nav.dart';

/// Wallet → "Savings". Locked by design: every move in or out re-asks for
/// the app PIN as a separate, deliberate step — so if someone forces you
/// to open the app under coercion, the savings balance isn't one tap away.
/// That rationale is stated plainly on screen rather than hidden.
class SavingsScreen extends StatelessWidget {
  const SavingsScreen({
    super.key,
    required this.onBack,
    required this.onMoveToSavings,
    required this.onRequestWithdrawal,
    required this.onHideSavings,
  });

  final VoidCallback onBack;
  final VoidCallback onMoveToSavings;
  final VoidCallback onRequestWithdrawal;
  final VoidCallback onHideSavings;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WalletStore>();
    final wallet = store.wallet;

    // Matches the branded loader used at bootstrap and on Home's own
    // first-load state — a bare number defaulting to "$0.00" before the
    // wallet finishes loading used to read as "you have nothing saved"
    // for a beat, which is the wrong thing to imply even briefly on a
    // screen whose whole point is showing how much is protected.
    if (wallet == null) {
      return Container(
          color: AppColors.navy900,
          child: const Center(child: JamiiLogo(size: 64)));
    }

    final savingsUsd = wallet.savingsBalanceUsd;
    final rate = store.fxCache?.rate ?? 129.25;
    final canWithdraw = savingsUsd > 0;

    return AppScreen(
      scrollable: false,
      footer: Column(
        children: [
          AppButton(
              label: 'Move money to savings',
              variant: AppButtonVariant.green,
              onPressed: onMoveToSavings),
          const SizedBox(height: 8),
          AppButton(
              label: 'Request a withdrawal',
              variant: AppButtonVariant.dangerOutline,
              onPressed: canWithdraw ? onRequestWithdrawal : null),
        ],
      ),
      child: EternityRefresh(
        onRefresh: () async {
          try {
            await store.refresh();
          } catch (_) {
            // Refresh failures used to be invisible — pull-to-refresh would
            // just spin, settle, and leave the numbers unchanged with no
            // sign anything went wrong. Never leak raw exceptions here.
            if (!context.mounted) return;
            AppSnackBar.showMoneyError(context, 'Could not refresh');
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScreenNav(title: 'Savings', onBack: onBack),
              // Hero — left-aligned like Home's total card so the two
              // money screens share one reading rhythm. Single-size
              // amount in tabular figures (the old \$22 + digits-41
              // Text.rich floated the dollar sign off-baseline).
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.07),
                  border: Border.all(
                      color: AppColors.green.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.green.withValues(alpha: 0.12),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 14, color: AppColors.green),
                              const SizedBox(width: 6),
                              Text('SAVINGS · LOCKED',
                                  style: AppText.balanceLabel(
                                      color: AppColors.green)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '\$${savingsUsd.toStringAsFixed(2)}',
                            style: AppText.balance(size: 44).copyWith(
                              color: AppColors.ink,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '≈ KSh ${(savingsUsd * rate).toStringAsFixed(0)} · grows only when you move money in',
                            style: AppText.balanceAlt(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            AppColors.green.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.lock_outline,
                          size: 22, color: AppColors.green),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Protection — calm green/info row, not the old coral
              // "danger" circle: a locked vault is reassurance, and coral
              // reads as something going wrong.
              AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            AppColors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.shield_outlined,
                          size: 20, color: AppColors.green),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Protected by your app PIN',
                              style: AppText.ui(
                                  size: 14, weight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            'Every move in or out re-asks for your PIN — a separate, deliberate step from just having the app open.',
                            style: AppText.ui(
                                size: 12.5,
                                color: AppColors.ink2,
                                height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Why it works this way',
                        style: AppText.ui(
                            size: 13,
                            weight: FontWeight.w700,
                            color: AppColors.ink)),
                    const SizedBox(height: 8),
                    Text(
                      'Everyday spending never touches this balance automatically. Under pressure, anyone opening the app only reaches everyday money.',
                      style: AppText.ui(
                          size: 13,
                          color: AppColors.ink2,
                          height: 1.55),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Tertiary, not a third full-width button: hiding is a
              // device setting, not a money move, so it must not compete
              // with the two footer actions above.
              Center(
                child: TextButton.icon(
                  onPressed: onHideSavings,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: Icon(Icons.visibility_off_outlined,
                      size: 16, color: AppColors.ink3),
                  label: Text('Hide savings on this device',
                      style: AppText.ui(
                          size: 13,
                          weight: FontWeight.w600,
                          color: AppColors.ink3)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
