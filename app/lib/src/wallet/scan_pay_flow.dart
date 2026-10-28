import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api_client.dart';
import '../data/money_math.dart';
import '../data/pay_uri.dart';
import '../data/session_storage.dart';
import '../security/pin_hash.dart';
import '../state/wallet_store.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/motion.dart';
import '../widgets/pin_entry_screen.dart';
import '../widgets/review_sheet.dart';
import '../widgets/row_line.dart';
import '../widgets/success_sheet.dart';
import 'scan_pay_amount_screen.dart';
import 'scan_pay_screen.dart';

/// Chains Scan-to-pay's steps: camera scan → (amount entry, only if the
/// scanned QR didn't already have one baked in) → PIN approval → the same
/// `POST /wallets/:id/transfers` call `SendScreen` uses. Two ways to skip
/// the amount step, matching the brief: the *receiver* can request a
/// specific amount before showing their QR (`ReceiveScreen`), or the
/// *sender* can type it in after scanning — either way, the last step is
/// always the same PIN approval, not a bare tap, since this is real money
/// moving to whoever's QR happened to be in front of the camera.
void pushScanPayFlow(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (context) => _buildScan(context)));
}

Widget _buildScan(BuildContext context) {
  return ScanPayScreen(
    onBack: () => Navigator.of(context).pop(),
    onScanned: (parsed) => _handleScanned(context, parsed),
  );
}

void _handleScanned(BuildContext context, ParsedPayUri parsed) {
  if (parsed.amountTampered && context.mounted) {
    AppSnackBar.show(context,
        message:
            'That QR amount looked tampered — please confirm the amount carefully.',
        tone: SnackTone.warning);
  }
  if (parsed.amountUsd != null) {
    _reviewThenPin(context, parsed.fullHandle, parsed.amountUsd!);
  } else {
    _pushAmount(context, parsed.fullHandle);
  }
}

void _pushAmount(BuildContext context, String fullHandle) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (context) => ScanPayAmountScreen(
      fullHandle: fullHandle,
      onBack: () => Navigator.of(context).pop(),
      onContinue: (amountUsd) =>
          _reviewThenPin(context, fullHandle, amountUsd),
    ),
  ));
}

/// QR-swap guard: review sheet with amber check-digit BEFORE the PIN,
/// matching Send's two-stage commit (cognitive friction, not just PIN).
Future<void> _reviewThenPin(
    BuildContext context, String fullHandle, double amountUsd) async {
  final store = context.read<WalletStore>();
  final fx = await store.getFxRate();
  final fee = fx.handleFeeUsdCents / 100;
  final clean = fullHandle.trim().toLowerCase();
  if (!context.mounted) return;
  final confirmed = await MoneyReviewSheet.show(
    context: context,
    title: 'Review scanned payment',
    quote: MoneyQuote(
      amountUsd: amountUsd,
      feeUsd: fee,
      totalDebitUsd: amountUsd + fee,
      theyReceiveUsd: amountUsd,
      rateKesPerUsd: fx.rate,
      rateUpdatedAt: fx.updatedAt,
      arrivalLabel: '~15 seconds',
    ),
    recipientBase:
        clean.length >= 4 ? clean.substring(0, clean.length - 1) : null,
    recipientCheckDigit:
        clean.length >= 4 ? clean.substring(clean.length - 1) : null,
    recipientFallback: clean.length >= 4 ? null : clean,
    extraRows: [
      const RowLine(
        label: 'Scanned',
        value: 'Verify this name in person',
        showBorder: false,
      ),
    ],
    confirmLabel: 'Continue to PIN',
  );
  if (!confirmed || !context.mounted) return;
  _pushPin(context, clean, amountUsd);
}

void _pushPin(BuildContext context, String fullHandle, double amountUsd) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => _buildPin(context, fullHandle, amountUsd)));
}

Widget _buildPin(BuildContext context, String fullHandle, double amountUsd) {
  return PinEntryScreen(
    title: 'Approve',
    subtitle:
        'Enter your PIN to send \$${amountUsd.toStringAsFixed(2)} to $fullHandle.',
    onBack: () => Navigator.of(context).pop(),
    onComplete: (pin) async {
      final storedHash = await const SessionStorage().readPinHash();
      if (storedHash != hashPin(pin)) return 'Incorrect PIN.';
      if (!context.mounted) return null;
      return _submit(context, fullHandle, amountUsd);
    },
  );
}

/// Returns an error message to keep the user on the PIN screen (cleared,
/// shaken in place), or `null` on success — see
/// `PinEntryScreen.onComplete`.
Future<String?> _submit(
    BuildContext context, String fullHandle, double amountUsd) async {
  final store = context.read<WalletStore>();
  final idempotencyKey = newIdempotencyKey();
  showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingVeil(message: 'Sending…'));
  try {
    await store.sendMoney(
        recipientFullHandle: fullHandle,
        amountUsdCents: (amountUsd * 100).round(),
        idempotencyKey: idempotencyKey);
    if (!context.mounted) return null;
    Navigator.of(context).pop(); // dismiss veil
    Navigator.of(context)
        .popUntil((route) => route.isFirst); // back to wallet home
    final clean = fullHandle.trim().toLowerCase();
    await SuccessSheet.show(
      context,
      amountUsd: amountUsd,
      recipientLabel: clean,
      base: clean.length >= 4 ? clean.substring(0, clean.length - 1) : null,
      checkDigit:
          clean.length >= 4 ? clean.substring(clean.length - 1) : null,
      onShare: () {},
      onDone: () {},
    );
    return null;
  } on ApiException catch (e) {
    if (!context.mounted) return null;
    Navigator.of(context).pop(); // dismiss veil
    Haptics.error();
    return e.message;
  } catch (_) {
    if (!context.mounted) return null;
    Navigator.of(context).pop();
    return 'Could not send. Please try again.';
  }
}
