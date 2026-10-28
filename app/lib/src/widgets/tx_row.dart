import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../models/transaction.dart';

/// `.tx` — one line in a transaction list: avatar glyph, counterparty +
/// timestamp, amount with the KES-equivalent underneath.
/// Tappable -> detail bottom sheet (rate, receipt ID); amount no longer
/// color-only (includes +/- prefix + icon semantics).
class TxRow extends StatelessWidget {
  const TxRow({super.key, required this.tx, this.showBorder = true, this.onTap});

  final Transaction tx;
  final bool showBorder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final positive = tx.amountUsd > 0;
    final amountColor = positive ? AppColors.green : AppColors.ink;

    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: showBorder
            ? Border(bottom: BorderSide(color: AppColors.line))
            : null,
      ),
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
                Text(tx.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.ui(size: 14, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(tx.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono(size: 12, color: AppColors.ink3)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    positive ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 13,
                    color: amountColor,
                    semanticLabel:
                        positive ? 'Received' : 'Sent',
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${positive ? '+' : '-'}\$${tx.amountUsd.abs().toStringAsFixed(2)}',
                    style: AppText.mono(
                        size: 14, weight: FontWeight.w700, color: amountColor),
                  ),
                ],
              ),
              if (tx.amountLocal != null)
                Text(tx.amountLocal!,
                    style: AppText.mono(
                        size: 12,
                        weight: FontWeight.w400,
                        color: AppColors.ink3)),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: '${tx.title}, ${positive ? 'received' : 'sent'} '
          '\$${tx.amountUsd.abs().toStringAsFixed(2)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: row,
      ),
    );
  }
}
