import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/row_line.dart';
import '../widgets/screen_nav.dart';

/// "Prompt their phone to pay" — enter the payer's number and how much,
/// then M-Pesa itself pops a PIN prompt on *their* phone (STK Push).
/// Mirrors `CashOutScreen`'s field layout for the reverse direction.
class MpesaReceiveScreen extends StatefulWidget {
  const MpesaReceiveScreen(
      {super.key, required this.onBack, required this.onContinue});

  final VoidCallback onBack;
  final ValueChanged<(String phone, double amountUsd)> onContinue;

  static const rate = 129.25;

  @override
  State<MpesaReceiveScreen> createState() => _MpesaReceiveScreenState();
}

class _MpesaReceiveScreenState extends State<MpesaReceiveScreen> {
  final _numberController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _numberController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  int get _digitCount =>
      _numberController.text.replaceAll(RegExp(r'\D'), '').length;
  double get _amount => double.tryParse(_amountController.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    final canContinue = _digitCount >= 9 && _amount > 0;

    return AppScreen(
      footer: AppButton(
        label: 'Send the prompt',
        onPressed: canContinue
            ? () => widget.onContinue((_numberController.text.trim(), _amount))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Prompt their phone', onBack: widget.onBack),
          Text('Their M-Pesa number',
              style: AppText.ui(size: 12, color: AppColors.ink3)),
          const SizedBox(height: 8),
          AppCard(
            variant: AppCardVariant.selected,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _numberController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.phone,
              style: AppText.mono(size: 15),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: '07xx xxx xxx',
                hintStyle: AppText.mono(size: 15, color: AppColors.ink3),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _numberController.text.isEmpty
                ? ''
                : (_digitCount >= 9
                    ? '✓ Looks like a valid M-Pesa number'
                    : 'Enter a full number'),
            style: AppText.ui(
                size: 11,
                color: _digitCount >= 9 ? AppColors.green : AppColors.ink3),
          ),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Text('Amount to request',
                    style: AppText.ui(size: 12, color: AppColors.ink3)),
                const SizedBox(height: 6),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _amountController,
                    onChanged: (_) => setState(() {}),
                    textAlign: TextAlign.center,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: AppText.balance(size: 40),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      prefixText: '\$',
                      prefixStyle: AppText.balance(size: 25),
                      hintText: '0.00',
                      hintStyle:
                          AppText.balance(size: 40, color: AppColors.ink3),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '≈ KSh ${(_amount * MpesaReceiveScreen.rate).toStringAsFixed(0)}',
                  style: AppText.ui(size: 11, color: AppColors.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              children: [
                RowLine(
                    label: 'Rate today',
                    value:
                        '${MpesaReceiveScreen.rate.toStringAsFixed(2)} KES/\$'),
                RowLine(
                  label: 'What happens next',
                  value: 'They approve on their phone',
                  valueColor: AppColors.green,
                  showBorder: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
