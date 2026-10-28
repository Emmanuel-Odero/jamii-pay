import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/money_math.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/row_line.dart';
import '../widgets/screen_nav.dart';

/// Wallet → "Cash out to M-Pesa". Real number/amount entry against the
/// live everyday balance, matching `designs/jammii-pay-prototype.html`'s
/// `cashOut` screen: live validation on both fields, and the spread
/// disclosed inline — "Our spread · 0.8% · shown openly" — rather than
/// hidden behind a "continue" tap. Previously this was reachable only via
/// an `onComingSoon` snackbar with no screen behind it at all.
class CashOutScreen extends StatefulWidget {
  const CashOutScreen(
      {super.key, required this.onBack, required this.onContinue});

  final VoidCallback onBack;
  final ValueChanged<(String mpesaNumber, double amountUsd)> onContinue;

  static const spread = 0.008;
  static const rate = 129.25;

  @override
  State<CashOutScreen> createState() => _CashOutScreenState();
}

class _CashOutScreenState extends State<CashOutScreen> {
  final _numberController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _numberController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  double get _amount => MoneyMath.parseAmount(_amountController.text) ?? 0;
  bool get _numberValid =>
      MoneyMath.isValidMpesaNumber(_numberController.text);

  @override
  Widget build(BuildContext context) {
    final everydayUsd =
        context.watch<WalletStore>().wallet?.everydayBalanceUsd ?? 0;
    const effectiveRate = CashOutScreen.rate * (1 - CashOutScreen.spread);
    final overBalance = _amount > everydayUsd;
    final canContinue = _numberValid && _amount > 0 && !overBalance;

    return AppScreen(
      footer: AppButton(
        label: 'Continue',
        onPressed: canContinue
            ? () => widget.onContinue((_numberController.text.trim(), _amount))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Cash out to M-Pesa', onBack: widget.onBack),
          Text('M-Pesa number',
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
                hintText: '+254 7xx xxx xxx',
                hintStyle: AppText.mono(size: 15, color: AppColors.ink3),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            child: Text(
              _numberController.text.isEmpty
                  ? 'Use a Safaricom M-Pesa number: +254 7xx xxx xxx.'
                  : (_numberValid
                      ? '✓ ${MoneyMath.formatMpesaNumber(_numberController.text)}'
                      : 'Enter a full Safaricom number (+254 7xx / 01xx)'),
              style: AppText.ui(
                  size: 12,
                  color:
                      _numberValid ? AppColors.green : AppColors.ink3),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Text('Amount',
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
                  '≈ KSh ${(_amount * effectiveRate).toStringAsFixed(0)}'
                  '${overBalance ? ' · more than your ${MoneyMath.usd(everydayUsd)} balance' : ''}',
                  style: AppText.ui(
                      size: 12,
                      color: overBalance ? AppColors.coral : AppColors.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              children: [
                RowLine(
                    label: 'Available',
                    value: '\$${everydayUsd.toStringAsFixed(2)}'),
                RowLine(
                    label: 'Rate',
                    value:
                        '${CashOutScreen.rate.toStringAsFixed(2)} KES/\$ · live, locked at confirm'),
                RowLine(
                    label: 'Our spread',
                    value: '0.8% · shown openly',
                    valueColor: AppColors.ink2,
                    showBorder: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
