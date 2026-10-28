import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/transaction.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_card.dart';
import '../widgets/row_line.dart';

/// Receipt bottom sheet — same shape as `MoneyReviewSheet` but for
/// completed history: amount + KES + exact server `fx_rate` + ID +
/// timestamp + pending state. Fulfills `ActivityScreen`'s promise that
/// "every converted transaction shows the exact rate used".
class TxDetailSheet extends StatelessWidget {
  const TxDetailSheet({super.key, required this.tx});

  final Transaction tx;

  static Future<void> show(BuildContext context, Transaction tx) {
    HapticFeedback.selectionClick();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.navy800,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(child: TxDetailSheet(tx: tx)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final positive = tx.amountUsd > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line2,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: tx.glyphBackground,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(tx.glyph, size: 20, color: tx.glyphColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.title,
                        style: AppText.ui(
                            size: 16, weight: FontWeight.w700)),
                    Text(tx.subtitle,
                        style: AppText.mono(
                            size: 12, color: AppColors.ink3)),
                  ],
                ),
              ),
              if (tx.pending)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('PENDING',
                      style: AppText.mono(
                          size: 11,
                          weight: FontWeight.w700,
                          color: AppColors.amber)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: Column(
              children: [
                Text(
                  '${positive ? '+' : '-'}\$${tx.amountUsd.abs().toStringAsFixed(2)}',
                  style: AppText.balance(size: 36),
                ),
                if (tx.amountLocal != null)
                  Text(tx.amountLocal!,
                      style: AppText.ui(
                          size: 13, color: AppColors.ink3)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              children: [
                RowLine(
                    label: 'Rate used',
                    value: tx.fxRate ?? '—',
                    valueColor: AppColors.ink),
                RowLine(
                    label: 'Receipt ID',
                    value:
                        tx.id.length > 8 ? '${tx.id.substring(0, 8)}…' : tx.id),
                RowLine(
                  label: 'Date',
                  value:
                      '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year} ${tx.createdAt.hour.toString().padLeft(2, '0')}:${tx.createdAt.minute.toString().padLeft(2, '0')}',
                  showBorder: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: tx.id));
                Navigator.of(context).pop();
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.line2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Copy receipt ID',
                  style: AppText.ui(
                      size: 14,
                      weight: FontWeight.w700,
                      color: AppColors.ink)),
            ),
          ),
        ],
      ),
    );
  }
}
