import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';

/// Recovery R3 — "The wait, explained". The six-hour partial unlock is what
/// makes the 48-hour safety wait survivable: someone who lost everything
/// gets grocery money today and the rest on the day the wait completes.
class RecoveryWaitingScreen extends StatefulWidget {
  const RecoveryWaitingScreen({
    super.key,
    required this.startedAt,
    required this.waitCompletesAt,
    required this.onCancelledRecovery,
  });

  final DateTime startedAt;
  final DateTime waitCompletesAt;
  final VoidCallback onCancelledRecovery;

  @override
  State<RecoveryWaitingScreen> createState() => _RecoveryWaitingScreenState();
}

class _RecoveryWaitingScreenState extends State<RecoveryWaitingScreen> {
  late Timer _ticker;
  late Duration _remaining;
  late final Duration _totalWait =
      widget.waitCompletesAt.difference(widget.startedAt);

  @override
  void initState() {
    super.initState();
    _remaining = _computeRemaining();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _remaining = _computeRemaining());
    });
  }

  Duration _computeRemaining() {
    final remaining = widget.waitCompletesAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final hours = _remaining.inHours;
    final minutes = _remaining.inMinutes % 60;
    final seconds = _remaining.inSeconds % 60;
    final totalSeconds = _totalWait.inSeconds == 0 ? 1 : _totalWait.inSeconds;
    final elapsedFraction = 1 - (_remaining.inSeconds / totalSeconds);
    final partialUnlockAt = widget.startedAt.add(const Duration(hours: 6));
    final partialPassed = DateTime.now().isAfter(partialUnlockAt);

    return AppScreen(
      footer: AppButton(
        label: "This wasn't me — stop it",
        variant: AppButtonVariant.dangerOutline,
        onPressed: widget.onCancelledRecovery,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 16),
            child: Text('Recovery in progress',
                style: AppText.ui(size: 15, weight: FontWeight.w600)),
          ),
          AppCard(
            variant: AppCardVariant.amber,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 15),
            child: Column(
              children: [
                Text('Full access in',
                    style: AppText.balanceLabel(color: AppColors.amber)),
                Text(
                    '${_twoDigits(hours)}:${_twoDigits(minutes)}:${_twoDigits(seconds)}',
                    style: AppText.timer()),
                Container(
                  height: 5,
                  margin: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                      color: AppColors.navy600,
                      borderRadius: BorderRadius.circular(99)),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: elapsedFraction.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [AppColors.coral, AppColors.amber]),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
                Text('Started ${_formatStart(widget.startedAt)}',
                    style: AppText.ui(size: 10.5, color: AppColors.ink3)),
              ],
            ),
          ),
          const SizedBox(height: 11),
          AppCard(
            variant: AppCardVariant.green,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.payments_outlined, size: 19, color: AppColors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // No real figure to show here — this device lost its
                      // session (that's what recovery is for), so it has no
                      // wallet data to compute a partial-unlock amount from.
                      // A specific dollar figure ("$40 available now") used
                      // to be hardcoded here, which a user could easily
                      // mistake for their real balance.
                      Text('Your everyday balance unlocks first',
                          style: AppText.ui(size: 13, weight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(
                        partialPassed
                            ? 'The 6-hour mark has passed — your everyday balance should now be available. The rest unlocks when the full wait completes.'
                            : "Available at ${_twoDigits(partialUnlockAt.hour)}:${_twoDigits(partialUnlockAt.minute)} on ${partialUnlockAt.day} ${_monthName(partialUnlockAt.month)} (6h after start), so you're not left with nothing while the rest completes.",
                        style: AppText.ui(
                            size: 12, color: AppColors.ink2, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Why the wait?',
                    style: AppText.ui(size: 12, color: AppColors.ink3)),
                const SizedBox(height: 7),
                Text(
                  "If someone else started this, you'll get a warning on every device and phone number "
                  'you registered — via push and SMS, even in quiet hours — and you can stop it instantly below.',
                  style: AppText.ui(
                      size: 12, color: AppColors.ink2, height: 1.55),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatStart(DateTime dt) {
    final h = _twoDigits(dt.hour);
    final m = _twoDigits(dt.minute);
    return '$h:$m · ${dt.day} ${_monthName(dt.month)}';
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }
}
