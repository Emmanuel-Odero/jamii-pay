import 'dart:async';

import 'package:flutter/material.dart';

import '../models/wallet.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_loading.dart';
import '../widgets/info_banner.dart';
import '../widgets/screen_nav.dart';

/// STK Push is asynchronous — Safaricom doesn't tell us the outcome
/// until the person actually responds on their phone (approve, cancel,
/// or time out), which can take anywhere from a few seconds to a couple
/// of minutes. This screen polls [poll] every few seconds and reacts the
/// moment the status stops being "pending".
class MpesaReceivePendingScreen extends StatefulWidget {
  const MpesaReceivePendingScreen(
      {super.key,
      required this.phone,
      required this.amountKes,
      required this.poll,
      required this.onDone,
      required this.onBack});

  final String phone;
  final double amountKes;
  final Future<MpesaDepositStatus> Function() poll;
  final VoidCallback onDone;

  /// Always available, not just after the request settles — this screen
  /// used to have no back button at all, so a stuck poll (dead network,
  /// server never learns the outcome) left the user on an infinite
  /// spinner with no way out except force-quitting the app.
  final VoidCallback onBack;

  @override
  State<MpesaReceivePendingScreen> createState() =>
      _MpesaReceivePendingScreenState();
}

class _MpesaReceivePendingScreenState extends State<MpesaReceivePendingScreen> {
  Timer? _poll;
  Timer? _timeout;
  MpesaDepositStatus? _status;
  int _consecutiveFailures = 0;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    // 2-minute cap: patchy networks used to poll forever, draining
    // battery/data. After this, offer Retry now instead of silent polling.
    _timeout = Timer(const Duration(minutes: 2), () {
      if (!mounted) return;
      final s = _status?.status ?? 'pending';
      if (s == 'pending') {
        _poll?.cancel();
        setState(() => _timedOut = true);
      }
    });
    _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _timeout?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_timedOut) return;
    try {
      final status = await widget.poll();
      if (!mounted) return;
      setState(() {
        _status = status;
        _consecutiveFailures = 0;
      });
      if (status.status != 'pending') {
        _poll?.cancel();
        _timeout?.cancel();
      }
    } catch (_) {
      // Transient — keep polling on the same timer rather than giving up
      // on one failed request. After several in a row, surface it — a
      // silently-stuck poll used to look identical to a legitimately slow
      // approval, with no hint anything was actually wrong.
      if (!mounted) return;
      setState(() => _consecutiveFailures++);
    }
  }

  void _retryNow() {
    setState(() {
      _timedOut = false;
      _consecutiveFailures = 0;
    });
    _timeout?.cancel();
    _timeout = Timer(const Duration(minutes: 2), () {
      if (!mounted) return;
      if ((_status?.status ?? 'pending') == 'pending') {
        _poll?.cancel();
        setState(() => _timedOut = true);
      }
    });
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    _check();
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
              ScreenNav(title: 'Waiting for approval', onBack: widget.onBack),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status == 'pending') ...[
                        const AppLoading(
                            label: 'Waiting for M-Pesa payment…'),
                        const SizedBox(height: 20),
                        Text('Check ${widget.phone}\'s phone',
                            style:
                                AppText.ui(size: 15, weight: FontWeight.w700)),
                        const SizedBox(height: 7),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(
                            'They should see a prompt to pay KSh ${widget.amountKes.toStringAsFixed(0)} via M-Pesa. '
                            'This updates automatically once they respond.',
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
                                "Having trouble checking status. You can go back and try again — this won't cancel a payment they already approved.",
                          ),
                        ],
                        if (_timedOut) ...[
                          const SizedBox(height: 16),
                          const InfoBanner(
                            icon: Icons.timer_off_outlined,
                            tone: BannerTone.warning,
                            text:
                                'Still no answer after 2 minutes. They may have missed the prompt — retry, or go back and check the number.',
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: 240,
                            height: 52,
                            child: OutlinedButton(
                              onPressed: _retryNow,
                              child: const Text('Retry now',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Wrong number? Go back to fix it.',
                              style: AppText.ui(
                                  size: 12, color: AppColors.ink3)),
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
                        Text('Payment received',
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
                        Text('Payment not completed',
                            style:
                                AppText.ui(size: 15, weight: FontWeight.w700)),
                        const SizedBox(height: 7),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(
                            _status?.resultDesc ??
                                'They may have cancelled or the request timed out.',
                            textAlign: TextAlign.center,
                            style: AppText.screenSub(),
                          ),
                        ),
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
