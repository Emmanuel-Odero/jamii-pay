import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api_client.dart';
import '../data/money_math.dart';
import '../data/session_storage.dart';
import '../security/pin_hash.dart';
import '../state/wallet_store.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/pin_entry_screen.dart';
import '../widgets/review_sheet.dart';
import '../widgets/row_line.dart';
import 'cash_out_done_screen.dart';
import 'cash_out_screen.dart';

/// Chains Cash-out's three steps: amount/number entry → PIN approval (a
/// spend-approval gate, matching the prototype's `cashPin` screen — not
/// the app-unlock PIN check, though it's the same PIN) → the real
/// `POST /wallets/:id/cash-out` call → success.
void pushCashOutFlow(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (context) => _buildAmount(context)));
}

Widget _buildAmount(BuildContext context) {
  return CashOutScreen(
    onBack: () => Navigator.of(context).pop(),
    onContinue: (details) => _pushPin(context, details.$1, details.$2),
  );
}

void _pushPin(BuildContext context, String mpesaNumber, double amountUsd) {
  _reviewThenPin(context, mpesaNumber, amountUsd);
}

/// Cash-out review BEFORE the PIN: formatted number + KES + frozen rate +
/// idempotency key. Wrong-number cash-out is irreversible.
Future<void> _reviewThenPin(
    BuildContext context, String mpesaNumber, double amountUsd) async {
  final store = context.read<WalletStore>();
  final fx = await store.getFxRate();
  if (!context.mounted) return;
  final formatted = MoneyMath.formatMpesaNumber(mpesaNumber);
  final confirmed = await MoneyReviewSheet.show(
    context: context,
    title: 'Review cash-out',
    quote: MoneyQuote(
      amountUsd: amountUsd,
      feeUsd: amountUsd * fx.spread,
      totalDebitUsd: amountUsd,
      theyReceiveUsd: amountUsd,
      rateKesPerUsd: fx.effectiveCashoutRate,
      rateUpdatedAt: fx.updatedAt,
      arrivalLabel: 'M-Pesa ~1 min',
    ),
    recipientFallback: formatted,
    extraRows: [
      RowLine(
          label: 'They get',
          value:
              '≈ KSh ${(amountUsd * fx.effectiveCashoutRate).toStringAsFixed(0)}'),
      RowLine(
          label: 'Rate locked',
          value:
              '${fx.effectiveCashoutRate.toStringAsFixed(2)} KES/\$ (0.8% spread incl.)',
          showBorder: false),
    ],
    confirmLabel: 'Continue to PIN',
  );
  if (!confirmed || !context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => _buildPin(context, formatted, amountUsd)));
}

Widget _buildPin(BuildContext context, String mpesaNumber, double amountUsd) {
  return PinEntryScreen(
    title: 'Approve',
    subtitle:
        'Enter your PIN to send \$${amountUsd.toStringAsFixed(2)} to $mpesaNumber.',
    onBack: () => Navigator.of(context).pop(),
    onComplete: (pin) async {
      final storedHash = await const SessionStorage().readPinHash();
      if (storedHash != hashPin(pin)) return 'Incorrect PIN.';
      if (!context.mounted) return null;
      return _submit(context, mpesaNumber, amountUsd);
    },
  );
}

/// Returns an error message to keep the user on the PIN screen (cleared,
/// shaken in place), or `null` on success — see `PinEntryScreen.onComplete`.
Future<String?> _submit(
    BuildContext context, String mpesaNumber, double amountUsd) async {
  final store = context.read<WalletStore>();
  final idempotencyKey = newIdempotencyKey();
  showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingVeil(message: 'Sending to M-Pesa…'));
  try {
    final result = await store.cashOut(
        mpesaNumber: mpesaNumber,
        amountUsdCents: (amountUsd * 100).round(),
        idempotencyKey: idempotencyKey);
    if (!context.mounted) return null;
    Navigator.of(context).pop(); // dismiss veil
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (context) => CashOutDoneScreen(
        amountKes: result.amountKes,
        mpesaNumber: mpesaNumber,
        newBalanceUsd: result.everydayBalanceUsd,
        rate: result.rate,
        onDone: () => Navigator.of(context).popUntil((route) => route.isFirst),
      ),
    ));
    return null;
  } on ApiException catch (e) {
    if (!context.mounted) return null;
    Navigator.of(context).pop(); // dismiss veil
    return e.message;
  } catch (_) {
    if (!context.mounted) return null;
    Navigator.of(context).pop();
    return 'Could not cash out. Please try again.';
  }
}
