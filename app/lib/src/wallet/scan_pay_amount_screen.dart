import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_screen.dart';
import '../widgets/handle_chip.dart';
import '../widgets/screen_nav.dart';

/// Second step of Scan-to-pay when the scanned QR didn't already embed an
/// amount (see `ReceiveScreen`'s "Request a specific amount" field) — the
/// sender picks how much to pay before moving on to PIN approval. Same
/// centered big-number field as `SendScreen`/`CashOutScreen`'s amount
/// entry, kept consistent rather than inventing a new layout for what's
/// functionally the same input.
class ScanPayAmountScreen extends StatefulWidget {
  const ScanPayAmountScreen({
    super.key,
    required this.fullHandle,
    required this.onBack,
    required this.onContinue,
  });

  final String fullHandle;
  final VoidCallback onBack;
  final ValueChanged<double> onContinue;

  @override
  State<ScanPayAmountScreen> createState() => _ScanPayAmountScreenState();
}

class _ScanPayAmountScreenState extends State<ScanPayAmountScreen> {
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountController.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    final base = widget.fullHandle.substring(0, widget.fullHandle.length - 1);
    final checkDigit =
        widget.fullHandle.substring(widget.fullHandle.length - 1);

    return AppScreen(
      footer: AppButton(
        label: 'Continue',
        onPressed: _amount > 0 ? () => widget.onContinue(_amount) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Pay', onBack: widget.onBack),
          Center(child: HandleChip(base: base, checkDigit: checkDigit)),
          const SizedBox(height: 26),
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
                    autofocus: true,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
