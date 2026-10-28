import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/escrow_claim.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/screen_nav.dart';
import '../widgets/skeleton.dart';

/// "N waiting to be claimed" — matches
/// `designs/jammii-pay-prototype.html`'s `SCR.pending` screen: one card
/// per held escrow, a countdown, and Remind/Cancel actions. "Remind" has
/// no real SMS/email nudge behind it — no messaging infra exists yet to
/// build one against — so it surfaces an honest "coming soon" notice
/// rather than claiming to have sent something it didn't.
class PendingClaimsScreen extends StatefulWidget {
  const PendingClaimsScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<PendingClaimsScreen> createState() => _PendingClaimsScreenState();
}

class _PendingClaimsScreenState extends State<PendingClaimsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await context.read<WalletStore>().refresh();
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<void> _cancel(EscrowClaim claim) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navy800,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Cancel and refund?',
            style: AppText.ui(size: 16, weight: FontWeight.w700)),
        content: Text(
          'This returns \$${claim.amountUsd.toStringAsFixed(2)} to your everyday balance immediately. The recipient will no longer be able to claim it.',
          style: AppText.ui(size: 13, color: AppColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep waiting',
                style: AppText.ui(
                    size: 14,
                    weight: FontWeight.w700,
                    color: AppColors.ink)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Cancel & refund',
                style: AppText.ui(
                    size: 14,
                    weight: FontWeight.w700,
                    color: AppColors.coral)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final store = context.read<WalletStore>();
    try {
      await store.cancelEscrow(claim.id);
      if (!mounted) return;
      AppSnackBar.show(
        context,
        icon: Icons.undo_rounded,
        message: '\$${claim.amountUsd.toStringAsFixed(2)} came back to you.',
        actionLabel: 'View',
        onAction: () {},
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackBar.showMoneyError(context, 'Could not cancel this claim');
    }
  }

  void _remind(EscrowClaim claim) {
    // Demoted: no messaging infra yet, so this shares the claim link
    // instead of pretending to send a nudge.
    AppSnackBar.show(context,
        message: 'Share your claim link again — auto-reminders coming soon.',
        tone: SnackTone.info);
  }

  String _timeLeft(Duration d) {
    if (d.isNegative) return 'expired';
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    return '${hours}h ${minutes}m left';
  }

  @override
  Widget build(BuildContext context) {
    final claims = context.watch<WalletStore>().escrowClaims;

    return AppScreen(
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Waiting to be claimed', onBack: widget.onBack),
          if (_loading)
            const Expanded(child: SkeletonCard(lines: 2))
          else if (claims.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('Nothing waiting right now.',
                    style: AppText.ui(size: 13, color: AppColors.ink3)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: claims.length,
                separatorBuilder: (_, __) => const SizedBox(height: 9),
                itemBuilder: (context, i) {
                  final claim = claims[i];
                  final left = claim.timeLeft;
                  final progress =
                      (left.inSeconds / (72 * 3600)).clamp(0.0, 1.0);
                  return AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(claim.recipientAddr,
                                  style: AppText.ui(
                                      size: 13, weight: FontWeight.w700)),
                            ),
                            Text('\$${claim.amountUsd.toStringAsFixed(2)}',
                                style: AppText.mono(
                                    size: 13, weight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(_timeLeft(left),
                            style: AppText.mono(
                                size: 10.5, color: AppColors.amber)),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 5,
                            backgroundColor: AppColors.navy600,
                            valueColor: AlwaysStoppedAnimation(AppColors.amber),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: AppButton(
                                label: 'Remind them',
                                variant: AppButtonVariant.outline,
                                onPressed: () => _remind(claim),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: AppButton(
                                label: 'Cancel & refund',
                                variant: AppButtonVariant.danger,
                                onPressed: () => _cancel(claim),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
