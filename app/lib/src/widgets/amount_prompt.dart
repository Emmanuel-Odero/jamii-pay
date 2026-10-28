import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// A reusable "enter a dollar amount" dialog — every flow that used to
/// hardcode a fixed amount (group contributions were stuck at a flat
/// $25) now goes through this instead, so the user picks how much
/// they're actually moving. Returns `null` on cancel, the amount in
/// whole-and-fractional USD (already validated `> 0` and `<= maxUsd`
/// when given) otherwise.
Future<double?> promptAmountUsd(
  BuildContext context, {
  required String title,
  String? subtitle,
  double? maxUsd,
  String confirmLabel = 'Continue',
}) async {
  final controller = TextEditingController();
  String? error;

  return showDialog<double>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void submit() {
          final amount = double.tryParse(controller.text);
          if (amount == null || amount <= 0) {
            setState(() => error = 'Enter an amount greater than \$0.');
            return;
          }
          if (maxUsd != null && amount > maxUsd) {
            setState(() => error =
                'That\'s more than the \$${maxUsd.toStringAsFixed(2)} available.');
            return;
          }
          Navigator.of(context).pop(amount);
        }

        return AlertDialog(
          backgroundColor: AppColors.navy800,
          title:
              Text(title, style: AppText.ui(size: 15, weight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null) ...[
                Text(subtitle,
                    style: AppText.ui(size: 12, color: AppColors.ink3)),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: AppText.balance(size: 22),
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  prefixStyle: AppText.balance(size: 22),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onSubmitted: (_) => submit(),
              ),
              if (error != null) ...[
                const SizedBox(height: 6),
                Text(error!,
                    style: AppText.ui(size: 11, color: AppColors.coral)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            TextButton(onPressed: submit, child: Text(confirmLabel)),
          ],
        );
      },
    ),
  );
}
