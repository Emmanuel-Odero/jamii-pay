import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/row_line.dart';

/// Cash-out success — mirrors `done_screen.dart`'s ring+copy pattern and
/// the prototype's `cashDone` screen exactly.
class CashOutDoneScreen extends StatelessWidget {
  const CashOutDoneScreen({
    super.key,
    required this.amountKes,
    required this.mpesaNumber,
    required this.newBalanceUsd,
    required this.rate,
    required this.onDone,
  });

  final double amountKes;
  final String mpesaNumber;
  final double newBalanceUsd;
  final double rate;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      scrollable: false,
      footer: AppButton(label: 'Done', onPressed: onDone),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 86,
            height: 86,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.149),
              border:
                  Border.all(color: AppColors.green.withValues(alpha: 0.451)),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.sync_alt, size: 34, color: AppColors.green),
          ),
          const SizedBox(height: 22),
          Text('Cashing out',
              style: AppText.screenTitle(), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              'KSh ${amountKes.toStringAsFixed(0)} is on its way to $mpesaNumber.',
              textAlign: TextAlign.center,
              style: AppText.screenSub(),
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              children: [
                RowLine(
                    label: 'New balance',
                    value: '\$${newBalanceUsd.toStringAsFixed(2)}'),
                RowLine(
                    label: 'Rate used',
                    value: '${rate.toStringAsFixed(2)} KES/\$',
                    showBorder: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
