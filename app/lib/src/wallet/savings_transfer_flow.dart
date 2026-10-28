import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api_client.dart';
import '../data/session_storage.dart';
import '../security/pin_hash.dart';
import '../state/wallet_store.dart';
import '../widgets/amount_prompt.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/pin_entry_screen.dart';

/// "Move to savings" / "Withdraw from savings" — custom amount, then a
/// PIN re-confirmation (the same spend-approval gate `cash_out_flow.dart`
/// uses, not the app-unlock check) before it actually moves. Both
/// directions are between the wallet's own two balances — no
/// counterparty, so unlike a group withdrawal there's no vote to open.
void pushSavingsTransferFlow(BuildContext context,
    {required bool toSavings}) async {
  final wallet = context.read<WalletStore>().wallet;
  if (wallet == null) return;

  final fromLabel = toSavings ? 'everyday balance' : 'savings';
  final maxUsd =
      toSavings ? wallet.everydayBalanceUsd : wallet.savingsBalanceUsd;

  final amount = await promptAmountUsd(
    context,
    title: toSavings ? 'Move to savings' : 'Withdraw from savings',
    subtitle:
        'How much from your $fromLabel? (\$${maxUsd.toStringAsFixed(2)} available)',
    maxUsd: maxUsd,
    confirmLabel: 'Next',
  );
  if (amount == null || !context.mounted) return;

  _pushPin(context, toSavings, (amount * 100).round());
}

void _pushPin(BuildContext context, bool toSavings, int amountUsdCents) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => _buildPin(context, toSavings, amountUsdCents)));
}

Widget _buildPin(BuildContext context, bool toSavings, int amountUsdCents) {
  final amountUsd = amountUsdCents / 100;
  return PinEntryScreen(
    title: 'Approve',
    subtitle: toSavings
        ? 'Enter your PIN to move \$${amountUsd.toStringAsFixed(2)} to savings.'
        : 'Enter your PIN to withdraw \$${amountUsd.toStringAsFixed(2)} from savings.',
    onBack: () => Navigator.of(context).pop(),
    onComplete: (pin) async {
      final storedHash = await const SessionStorage().readPinHash();
      if (storedHash != hashPin(pin)) return 'Incorrect PIN.';
      if (!context.mounted) return null;
      return _submit(context, toSavings, amountUsdCents);
    },
  );
}

/// Returns an error message to keep the user on the PIN screen (cleared,
/// shaken in place), or `null` on success.
Future<String?> _submit(
    BuildContext context, bool toSavings, int amountUsdCents) async {
  final store = context.read<WalletStore>();
  final amountUsd = amountUsdCents / 100;
  showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingVeil(message: 'Moving money…'));
  try {
    if (toSavings) {
      await store.moveToSavings(amountUsdCents);
    } else {
      await store.withdrawFromSavings(amountUsdCents);
    }
    if (!context.mounted) return null;
    Navigator.of(context).pop(); // dismiss veil
    Navigator.of(context).pop(); // dismiss the PIN screen, back to Savings
    AppSnackBar.show(
      context,
      message: toSavings
          ? 'Moved \$${amountUsd.toStringAsFixed(2)} to savings.'
          : 'Withdrew \$${amountUsd.toStringAsFixed(2)} from savings.',
    );
    return null;
  } on ApiException catch (e) {
    if (!context.mounted) return null;
    Navigator.of(context).pop(); // dismiss veil
    return e.message;
  } catch (e) {
    if (!context.mounted) return null;
    Navigator.of(context).pop();
    AppSnackBar.show(context,
        message: 'Could not complete the transfer: $e', tone: SnackTone.danger);
    return 'Could not complete the transfer.';
  }
}
