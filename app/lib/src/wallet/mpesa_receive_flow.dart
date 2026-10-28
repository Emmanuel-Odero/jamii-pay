import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api_client.dart';
import '../data/money_math.dart';
import '../state/wallet_store.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_snackbar.dart';
import 'mpesa_receive_pending_screen.dart';
import 'mpesa_receive_screen.dart';

/// "Prompt their phone to pay" — amount/number entry → initiate STK
/// Push → poll for the (asynchronous) result. See
/// `crates/server/src/daraja.rs`'s doc comment for what has to be
/// configured server-side before this can do anything beyond a clear
/// error message.
void pushMpesaReceiveFlow(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (context) => _buildAmount(context)));
}

Widget _buildAmount(BuildContext context) {
  return MpesaReceiveScreen(
    onBack: () => Navigator.of(context).pop(),
    onContinue: (details) => _initiate(context, details.$1, details.$2),
  );
}

Future<void> _initiate(
    BuildContext context, String phone, double amountUsd) async {
  final store = context.read<WalletStore>();
  // Idempotency per prompt: double-tap "Send the prompt" reuses the same
  // checkout instead of double-pushing. Button is disabled while
  // in-flight by the dialog barrier; key guards retry-after-timeout.
  final idempotencyKey = newIdempotencyKey();
  showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingVeil(message: 'Sending M-Pesa prompt…'));
  try {
    final result = await store.initiateMpesaStkPush(
        phone: phone,
        amountUsdCents: (amountUsd * 100).round(),
        idempotencyKey: idempotencyKey);
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss veil
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => MpesaReceivePendingScreen(
        phone: phone,
        amountKes: result.amountKes,
        poll: () => context
            .read<WalletStore>()
            .pollMpesaDeposit(result.checkoutRequestId),
        onDone: () => Navigator.of(context).popUntil((route) => route.isFirst),
        onBack: () => Navigator.of(context).pop(),
      ),
    ));
  } on ApiException catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss veil
    AppSnackBar.show(context, message: e.message, tone: SnackTone.danger);
  } catch (_) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    AppSnackBar.showMoneyError(context, 'Could not send the prompt');
  }
}
