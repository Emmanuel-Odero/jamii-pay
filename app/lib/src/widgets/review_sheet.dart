import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/money_math.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_card.dart';
import '../widgets/handle_chip.dart';
import '../widgets/row_line.dart';

/// Bottom-sheet money review — the 2026 Wise/Revolut standard:
/// Recipient (verified) / Amount / Fee / Total debit / Arrival /
/// Reversibility, on ONE screen before any hold/tap commits.
///
/// Replaces the old pattern where `HoldToConfirm` was the *only* review
/// (motor friction prevents slips, not mistakes). Every irreversible
/// flow (Send, Scan-Pay, Cash-out, Broadcast) must present this sheet
/// and only fire on explicit confirmation inside it.
class MoneyReviewSheet extends StatelessWidget {
  const MoneyReviewSheet({
    super.key,
    required this.title,
    required this.quote,
    this.recipientBase,
    this.recipientCheckDigit,
    this.recipientFallback,
    this.extraRows = const [],
    required this.confirmLabel,
    this.isDanger = false,
  });

  final String title;
  final MoneyQuote quote;
  final String? recipientBase;
  final String? recipientCheckDigit;
  final String? recipientFallback;
  final List<RowLine> extraRows;
  final String confirmLabel;
  final bool isDanger;

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required MoneyQuote quote,
    String? recipientBase,
    String? recipientCheckDigit,
    String? recipientFallback,
    List<RowLine> extraRows = const [],
    required String confirmLabel,
    bool isDanger = false,
  }) async {
    HapticFeedback.selectionClick();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navy800,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: MoneyReviewSheet(
          title: title,
          quote: quote,
          recipientBase: recipientBase,
          recipientCheckDigit: recipientCheckDigit,
          recipientFallback: recipientFallback,
          extraRows: extraRows,
          confirmLabel: confirmLabel,
          isDanger: isDanger,
        ),
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
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
          const SizedBox(height: 16),
          Text(title, style: AppText.ui(size: 18, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            "Check this is right — payments can't be reversed.",
            style: AppText.ui(size: 13, color: AppColors.ink3),
          ),
          const SizedBox(height: 16),
          if (recipientBase != null && recipientCheckDigit != null)
            Center(
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.blue.withValues(alpha: 0.25),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: HandleChip(
                  base: recipientBase!,
                  checkDigit: recipientCheckDigit!,
                  size: HandleChipSize.large,
                ),
              ),
            )
          else if (recipientFallback != null)
            AppCard(
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 18, color: AppColors.ink2),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(recipientFallback!,
                        style: AppText.mono(size: 14)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Center(
            child: Column(
              children: [
                Text(MoneyMath.usd(quote.amountUsd),
                    style: AppText.balance(size: 40).copyWith(
                      fontFeatures: const [
                        FontFeature.tabularFigures()
                      ],
                    )),
                Text(
                  '≈ ${MoneyMath.kes(quote.theyReceiveUsd, quote.rateKesPerUsd)}'
                  ' @ ${quote.rateKesPerUsd.toStringAsFixed(2)} (${quote.rateAgeLabel})',
                  style: AppText.ui(size: 12.5, color: AppColors.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              children: [
                RowLine(
                    label: 'They receive',
                    value: MoneyMath.usd(quote.theyReceiveUsd)),
                _FeeRow(feeUsd: quote.feeUsd),
                RowLine(
                  label: 'Total debited',
                  value: MoneyMath.usd(quote.totalDebitUsd),
                  valueColor: AppColors.ink,
                ),
                RowLine(
                  label: 'Arrives',
                  value: quote.arrivalLabel,
                  valueColor: AppColors.amber,
                  showBorder: extraRows.isEmpty,
                ),
                ...extraRows,
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    side: BorderSide(color: AppColors.line2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Cancel',
                      style: AppText.ui(
                          size: 14.5,
                          weight: FontWeight.w700,
                          color: AppColors.ink)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    Navigator.of(context).pop(true);
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    backgroundColor:
                        isDanger ? AppColors.coral : AppColors.green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(confirmLabel,
                      style: AppText.ui(
                          size: 14.5,
                          weight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fee row with `?` explainer — flat fee, never a surprise.
class _FeeRow extends StatelessWidget {
  const _FeeRow({required this.feeUsd});
  final double feeUsd;

  @override
  Widget build(BuildContext context) {
    return RowLine(
      label: 'Fee ⓘ',
      value: MoneyMath.usd(feeUsd),
      valueColor: AppColors.green,
    );
  }
}
