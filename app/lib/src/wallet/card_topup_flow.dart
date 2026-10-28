import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api_client.dart';
import '../models/wallet.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/amount_prompt.dart';
import '../widgets/app_button.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/info_banner.dart';
import '../widgets/screen_nav.dart';

/// "Top up with card" — amount entry → Stripe Checkout (opened in the
/// system browser, not embedded — see `crates/server/src/routes/
/// card_topup.rs`'s doc comment for why a hosted page beats a native
/// card form here) → poll for the result once they're done. Same shape
/// as `mpesa_receive_flow.dart` for the M-Pesa direction.
void pushCardTopupFlow(BuildContext context) async {
  final amount = await promptAmountUsd(context,
      title: 'Top up with card',
      subtitle: 'How much do you want to add?',
      confirmLabel: 'Continue');
  if (amount == null || !context.mounted) return;
  await _createAndOpenCheckout(context, (amount * 100).round());
}

Future<void> _createAndOpenCheckout(
    BuildContext context, int amountUsdCents) async {
  final store = context.read<WalletStore>();
  showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingVeil(message: 'Opening secure checkout…'));
  try {
    final checkout = await store.createCardTopupCheckout(amountUsdCents);
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss veil

    final opened = await launchUrl(Uri.parse(checkout.checkoutUrl),
        mode: LaunchMode.externalApplication);
    if (!opened) {
      if (!context.mounted) return;
      AppSnackBar.show(context,
          message: "Couldn't open the payment page.", tone: SnackTone.danger);
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => _CardTopupPendingScreen(
        topupId: checkout.topupId,
        poll: () => context.read<WalletStore>().pollCardTopup(checkout.topupId),
        onDone: () => Navigator.of(context).popUntil((route) => route.isFirst),
        onBack: () => Navigator.of(context).pop(),
      ),
    ));
  } on ApiException catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    AppSnackBar.show(context, message: e.message, tone: SnackTone.danger);
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    AppSnackBar.show(context,
        message: 'Could not start checkout: $e', tone: SnackTone.danger);
  }
}

/// Stripe Checkout completes in the *browser*, not this app, so — same
/// as the M-Pesa STK flow — there's no synchronous result to react to
/// here, only a webhook that lands later. This polls for it.
class _CardTopupPendingScreen extends StatefulWidget {
  const _CardTopupPendingScreen(
      {required this.topupId,
      required this.poll,
      required this.onDone,
      required this.onBack});

  final String topupId;
  final Future<CardTopupStatus> Function() poll;
  final VoidCallback onDone;

  /// Always available, not just after the request settles — see the
  /// matching note on `MpesaReceivePendingScreen.onBack`; a stuck poll
  /// here used to leave the user on an infinite spinner with no way out.
  final VoidCallback onBack;

  @override
  State<_CardTopupPendingScreen> createState() =>
      _CardTopupPendingScreenState();
}

class _CardTopupPendingScreenState extends State<_CardTopupPendingScreen> {
  Timer? _poll;
  CardTopupStatus? _status;
  int _consecutiveFailures = 0;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final status = await widget.poll();
      if (!mounted) return;
      setState(() {
        _status = status;
        _consecutiveFailures = 0;
      });
      if (status.status != 'pending') _poll?.cancel();
    } catch (_) {
      if (!mounted) return;
      setState(() => _consecutiveFailures++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status?.status ?? 'pending';

    return Scaffold(
      backgroundColor: AppColors.navy900,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScreenNav(title: 'Waiting for payment', onBack: widget.onBack),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status == 'pending') ...[
                        const AppLoading(label: 'Waiting for payment…'),
                        const SizedBox(height: 20),
                        Text('Finish payment in your browser',
                            style:
                                AppText.ui(size: 15, weight: FontWeight.w700)),
                        const SizedBox(height: 7),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(
                            'This updates automatically once you complete or cancel checkout.',
                            textAlign: TextAlign.center,
                            style: AppText.screenSub(),
                          ),
                        ),
                        if (_consecutiveFailures >= 5) ...[
                          const SizedBox(height: 16),
                          InfoBanner(
                            icon: Icons.wifi_off_rounded,
                            tone: BannerTone.warning,
                            text:
                                "Having trouble checking status. You can go back and try again — this won't cancel a payment you already made.",
                          ),
                        ],
                      ] else if (status == 'completed') ...[
                        Container(
                          width: 74,
                          height: 74,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.green.withValues(alpha: 0.129),
                            border: Border.all(
                                color:
                                    AppColors.green.withValues(alpha: 0.349)),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.check,
                              size: 31, color: AppColors.green),
                        ),
                        const SizedBox(height: 16),
                        Text('Top-up received',
                            style:
                                AppText.ui(size: 15, weight: FontWeight.w700)),
                        const SizedBox(height: 7),
                        Text(
                          'Your everyday balance is now \$${((_status!.everydayBalanceUsdCents ?? 0) / 100).toStringAsFixed(2)}.',
                          style: AppText.screenSub(),
                        ),
                      ] else ...[
                        Container(
                          width: 74,
                          height: 74,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.coral.withValues(alpha: 0.129),
                            border: Border.all(
                                color:
                                    AppColors.coral.withValues(alpha: 0.349)),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close,
                              size: 31, color: AppColors.coral),
                        ),
                        const SizedBox(height: 16),
                        Text('Top-up not completed',
                            style:
                                AppText.ui(size: 15, weight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ),
              ),
              if (status != 'pending')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: AppButton(label: 'Done', onPressed: widget.onDone),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
