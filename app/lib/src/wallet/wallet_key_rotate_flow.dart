import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../security/pin_hash.dart';
import '../state/wallet_store.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/pin_entry_screen.dart';
import 'wallet_key_backup_flow.dart';

/// Settings → "Rotate wallet key". For wallets whose key predates the
/// split-backup upgrade (v1 whole-key QRs in the wild) or any suspected
/// exposure: a fresh device key, old backups revoked server-side, session
/// re-saved.
///
/// Two confirmations before anything happens (dialog + wallet PIN), then a
/// veil while rotating. Afterwards the app insists on a fresh v2 export —
/// rotation without re-export leaves the wallet with *no* usable backup,
/// which is worse than an old one.
void pushWalletKeyRotateFlow(BuildContext context) async {
  final confirmed = await confirmDialog(
    context,
    title: 'Rotate wallet key?',
    message:
        'This creates a fresh key and permanently revokes every backup of the old one — including old printed QRs. '
        'You will need to back up the new key right after. Balances, name, and guardians stay the same.',
    confirmLabel: 'Continue',
    destructive: true,
  );
  if (!context.mounted || !confirmed) return;
  Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => _buildWalletPin(context)));
}

Widget _buildWalletPin(BuildContext context) {
  return PinEntryScreen(
    title: 'Confirm it’s you',
    subtitle: 'Enter your wallet PIN to authorize the rotation.',
    bannerText:
        'Rotation kills all old backups immediately. Only continue if you can back up the new key right after.',
    bannerIcon: Icons.refresh_rounded,
    onBack: () => Navigator.of(context).pop(),
    onComplete: (walletPin) => _doRotate(context, walletPin),
  );
}

/// Runs the rotation; returns the error to display, or null after pushing
/// the fresh-export prompt.
Future<String?> _doRotate(BuildContext context, String walletPin) async {
  final store = context.read<WalletStore>();
  showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingVeil(message: 'Rotating key…'));
  try {
    await store.rotateWalletKey(walletPinHash: hashPin(walletPin));
  } catch (e) {
    if (!context.mounted) return null;
    Navigator.of(context).pop(); // dismiss the veil
    final msg = e.toString();
    if (msg.contains('401') || msg.contains('incorrect PIN')) {
      return 'Incorrect wallet PIN.';
    }
    AppSnackBar.show(context,
        message: 'Could not rotate the key: $e', tone: SnackTone.danger);
    return 'Could not rotate the key.';
  }
  if (!context.mounted) return null;
  Navigator.of(context).pop(); // dismiss the veil
  // Swap the PIN screen for the backup flow: the wallet now has no usable
  // backup, and leaving here would strand it that way.
  Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (context) => _RotationDoneScreen(onBackupNow: () {
            Navigator.of(context).pop();
            pushWalletKeyBackupFlow(context);
          })));
  return null;
}

/// Interstitial after a successful rotation: celebrates briefly, then
/// funnels into a fresh v2 export. Deliberately no "later" escape hatch
/// past the back button — an un-backed-up wallet is the emergency this
/// whole flow exists to prevent.
class _RotationDoneScreen extends StatelessWidget {
  const _RotationDoneScreen({required this.onBackupNow});

  final VoidCallback onBackupNow;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 64, color: Color(0xFF3ECF7E)),
              const SizedBox(height: 16),
              const Text('Key rotated',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'Old backups are revoked and useless to anyone holding them. '
                'Back up the new key now — until you do, losing this phone loses the wallet.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: onBackupNow,
                  child: const Text('Back up the new key')),
            ],
          ),
        ),
      ),
    );
  }
}
