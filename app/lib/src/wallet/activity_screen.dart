import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transaction.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_card.dart';
import '../widgets/eternity_refresh.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/pill.dart';
import '../widgets/tx_detail_sheet.dart';
import '../widgets/tx_row.dart';

/// Wallet → "Activity" tab. Every converted transaction shows the exact
/// rate used — users who can audit the spread will trust it, users who
/// can't will assume the worst.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _filter = 'All';

  List<Transaction> _apply(List<Transaction> all) {
    return switch (_filter) {
      'In' => all.where((t) => t.amountUsd > 0).toList(),
      'Out' => all.where((t) => t.amountUsd < 0).toList(),
      'Pending' => all.where((t) => t.pending).toList(),
      _ => all,
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WalletStore>();
    final pending = store.transactions.where((t) => t.pending).toList();
    final settled =
        _apply(store.transactions.where((t) => !t.pending).toList());
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    bool isToday(Transaction t) => !t.createdAt.isBefore(todayStart);
    bool isYesterday(Transaction t) =>
        !t.createdAt.isBefore(yesterdayStart) && t.createdAt.isBefore(todayStart);
    final today = settled.where(isToday).toList();
    final yesterday = settled.where(isYesterday).toList();
    final earlier = settled
        .where((t) => t.createdAt.isBefore(yesterdayStart))
        .toList();

    return EternityRefresh(
      onRefresh: () async {
        try {
          await store.refresh();
        } catch (e) {
          // Refresh failures used to be invisible — pull-to-refresh would
          // just spin, settle, and leave the list unchanged with no sign
          // anything went wrong.
          if (!mounted) return;
          AppSnackBar.show(context,
              message: 'Could not refresh: $e', tone: SnackTone.danger);
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text('Activity',
                style: AppText.ui(size: 15, weight: FontWeight.w600)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              children: [
                for (final label in ['All', 'In', 'Out', 'Pending'])
                  AppPill(
                      label: label,
                      selected: label == _filter,
                      onTap: () => setState(() => _filter = label)),
              ],
            ),
            const SizedBox(height: 12),
            for (final tx in pending) ...[
              AppCard(
                variant: AppCardVariant.amber,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: tx.glyphBackground,
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(tx.glyph, size: 18, color: tx.glyphColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(tx.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.ui(
                                        size: 14,
                                        weight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 6),
                              _PendingPulse(),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(tx.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.mono(
                                  size: 12, color: AppColors.ink3)),
                        ],
                      ),
                    ),
                    Text(
                      '${tx.amountUsd >= 0 ? '+' : ''}\$${tx.amountUsd.abs().toStringAsFixed(2)}',
                      style: AppText.mono(
                          size: 14,
                          weight: FontWeight.w700,
                          color: AppColors.amber),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (settled.isEmpty && pending.isEmpty)
              const _EmptyActivity()
            else ...[
              if (today.isNotEmpty) ...[
                _DayHeader('Today'),
                for (final tx in today)
                  TxRow(
                      tx: tx,
                      showBorder: tx != today.last,
                      onTap: () => TxDetailSheet.show(context, tx)),
              ],
              if (yesterday.isNotEmpty) ...[
                _DayHeader('Yesterday'),
                for (final tx in yesterday)
                  TxRow(
                      tx: tx,
                      showBorder: tx != yesterday.last,
                      onTap: () => TxDetailSheet.show(context, tx)),
              ],
              if (earlier.isNotEmpty) ...[
                _DayHeader('Earlier'),
                for (final tx in earlier)
                  TxRow(
                      tx: tx,
                      showBorder: tx != earlier.last,
                      onTap: () => TxDetailSheet.show(context, tx)),
              ],
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.receipt_long_outlined, size: 28, color: AppColors.ink3),
            ),
            const SizedBox(height: 16),
            Text('No transactions yet',
                style: AppText.ui(
                    size: 15,
                    weight: FontWeight.w700,
                    color: AppColors.ink)),
            const SizedBox(height: 6),
            Text('Receive your first payment to see it here.',
                textAlign: TextAlign.center,
                style: AppText.ui(size: 13.5, color: AppColors.ink3)),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(label,
          style: AppText.ui(
              size: 13, weight: FontWeight.w700, color: AppColors.ink3)),
    );
  }
}

class _PendingPulse extends StatefulWidget {
  @override
  State<_PendingPulse> createState() => _PendingPulseState();
}

class _PendingPulseState extends State<_PendingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Opacity(
        opacity: 0.5 + 0.5 * _c.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: AppColors.amber, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
