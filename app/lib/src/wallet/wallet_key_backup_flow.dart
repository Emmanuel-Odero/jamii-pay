import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/api.dart' as bridge;
import '../state/wallet_store.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/pin_entry_screen.dart';
import 'wallet_key_backup_screen.dart';

/// Settings → "Download wallet key". Two steps before the code ever
/// renders: set a PIN, then confirm it by retyping — this PIN wraps the
/// QR-side share of a v2 split backup (see `WalletStore.exportSplitBackup`),
/// so a typo here would silently produce a backup nobody can ever open
/// again. Trivially guessable PINs are refused in Rust, not just in the UI.
void pushWalletKeyBackupFlow(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (context) => _buildSetPin(context)));
}

Widget _buildSetPin(BuildContext context) {
  return PinEntryScreen(
    title: 'Set a key PIN',
    subtitle:
        "This is separate from your wallet PIN — you'll need it plus this app to restore from this backup later.",
    bannerText:
        "Choose something you'll remember but others can't guess — no 123456, no repeats. There's no way to reset this PIN.",
    onBack: () => Navigator.of(context).pop(),
    onComplete: (pin) async {
      if (!bridge.isBackupPinAllowed(pin: pin)) {
        return 'That PIN is too easy to guess. Try something less predictable.';
      }
      _pushConfirm(context, pin);
      return null;
    },
  );
}

void _pushConfirm(BuildContext context, String pin) {
  Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => _buildConfirm(context, pin)));
}

Widget _buildConfirm(BuildContext context, String pin) {
  return PinEntryScreen(
    title: 'Confirm your key PIN',
    subtitle: 'Type it once more.',
    onBack: () => Navigator.of(context).pop(),
    onComplete: (confirm) async {
      if (confirm != pin) return "That didn't match. Try again.";
      await _generateAndShow(context, pin);
      return null;
    },
  );
}

Future<void> _generateAndShow(BuildContext context, String pin) async {
  final store = context.read<WalletStore>();
  showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingVeil(message: 'Preparing backup…'));
  try {
    // v2: splits the key and escrows the server share *before* the QR is
    // ever shown. Throws if the upload fails — in that case there is no
    // restorable backup, so no QR is displayed.
    final material = await store.exportSplitBackup(pin);
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss the veil
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      // `pushReplacement` above only swaps out the Confirm-PIN screen —
      // "Set a key PIN" is still underneath on the stack, so `onDone` has
      // to pop twice to actually reach Settings. A single pop left people
      // stranded back on the PIN flow with no way forward but "back" again.
      builder: (context) => WalletKeyBackupScreen(
          qrPayload: material.qrPayload,
          addressHex: material.addressHex,
          onDone: () => Navigator.of(context)
            ..pop()
            ..pop()),
    ));
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss the veil
    AppSnackBar.show(context,
        message: 'Could not prepare your wallet key: $e',
        tone: SnackTone.danger);
  }
}
