import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api_client.dart';
import '../data/wallet_key_backup_codec.dart';
import '../security/pin_hash.dart';
import '../state/wallet_store.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/pin_entry_screen.dart';
import 'restore_upload_screen.dart';

/// "Restore from wallet key" — the counterpart to `wallet_key_backup_flow`.
///
/// - **v2 (current):** upload the split-share QR → key PIN unwraps `S1` →
///   wallet PIN releases `S2` from the server oracle (rate-limited,
///   audit-logged, guardian-alerted) → shares combine in memory →
///   `restoreFromPrivateKey`. The QR alone is never sufficient.
/// - **v1 (legacy):** whole-key QRs printed before the split upgrade keep
///   working through the old two-PIN path below.
///
/// Only reachable when the person did *not* choose to restore this way
/// already — i.e. from `RestoreChoiceScreen`, not during a fresh "create
/// my wallet" onboarding run.
void pushRestoreFromKeyFlow(BuildContext context, VoidCallback onFinished) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => _buildUpload(context, onFinished)));
}

Widget _buildUpload(BuildContext context, VoidCallback onFinished,
    {String? errorText}) {
  return RestoreUploadScreen(
    onBack: () => Navigator.of(context).pop(),
    errorText: errorText,
    onDecoded: (raw) {
      // v2 first — the only kind new exports produce.
      try {
        final envelope = SplitBackupEnvelope.decodeV2(raw);
        _pushKeyPinV2(context, onFinished, envelope);
        return;
      } on FormatException {
        // Not v2 — fall through to the legacy path.
      }
      try {
        WalletKeyBackupCodec.decode(raw); // validate before advancing
        _pushKeyPin(context, onFinished, raw);
      } on FormatException catch (e) {
        Navigator.of(context).pop();
        Navigator.of(context).push(MaterialPageRoute(
            builder: (context) =>
                _buildUpload(context, onFinished, errorText: e.message)));
      }
    },
  );
}

/// v2, step 2 of 4 — the key PIN unwraps the QR-side share `S1` locally
/// (fail fast) and runs the OPAQUE login that releases `S2` — without the
/// PIN or its hash ever crossing the wire. Both shares ride to the next
/// screen; neither touches disk.
void _pushKeyPinV2(BuildContext context, VoidCallback onFinished,
    SplitBackupEnvelope envelope) {
  final shortId = envelope.backupId.length > 8
      ? '${envelope.backupId.substring(0, 8)}…'
      : envelope.backupId;
  Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => PinEntryScreen(
            title: 'Enter your key PIN',
            subtitle:
                'The PIN you set when you saved this Wallet Key certificate (v2 split backup, ID $shortId).',
            bannerText:
                'This unlocks the backup file only — your money still needs the next step in this app.',
            bannerIcon: Icons.key_rounded,
            onBack: () => Navigator.of(context).pop(),
            onComplete: (keyPin) => _unlockV2(context, onFinished, envelope, keyPin),
          )));
}

/// Unlocks both v2 shares. Returns the error to display, or `null` after
/// navigating on to the wallet-PIN screen.
Future<String?> _unlockV2(BuildContext context, VoidCallback onFinished,
    SplitBackupEnvelope envelope, String keyPin) async {
  final store = context.read<WalletStore>();
  final String s1Hex;
  try {
    s1Hex = store.decryptBackupShare(
      saltHex: envelope.saltHex,
      nonceHex: envelope.nonceHex,
      ciphertextHex: envelope.ciphertextHex,
      keyPin: keyPin,
    );
  } catch (_) {
    return 'Incorrect PIN, or the file is corrupted.';
  }
  try {
    final s2Hex = await store.opaqueLoginRelease(
        backupId: envelope.backupId, keyPin: keyPin);
    if (!context.mounted) return null;
    _pushWalletPinV2(context, onFinished, envelope, s1Hex, s2Hex);
    return null;
  } on ApiException catch (e) {
    if (e.statusCode == 423) {
      return 'Too many attempts — releases are locked for now and your guardians were alerted.';
    }
    if (e.statusCode == 410) {
      return 'This backup was revoked. Use recovery guardians instead.';
    }
    if (e.statusCode == 404) {
      // Predates OPAQUE (no password file) — fall through to the legacy
      // wallet-PIN release path on the next screen.
      if (!context.mounted) return null;
      _pushWalletPinV2(context, onFinished, envelope, s1Hex, '');
      return null;
    }
    return 'Incorrect PIN, or the file is corrupted.';
  } catch (_) {
    return 'Could not reach JamiiPay. Check your connection and try again.';
  }
}

/// v2, steps 3-4 of 4 — the wallet PIN gates the final combine + restore.
/// `s2Hex` arrives via OPAQUE already; empty means "predates OPAQUE", in
/// which case the legacy wallet-PIN release runs here instead. Shares meet
/// only in memory, never on disk.
void _pushWalletPinV2(BuildContext context, VoidCallback onFinished,
    SplitBackupEnvelope envelope, String s1Hex, String s2Hex) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => PinEntryScreen(
            title: 'Enter your wallet PIN',
            subtitle:
                'The PIN you use to unlock JamiiPay on this wallet. Step 3 of 3.',
            bannerText:
                'Verified with JamiiPay to finish restoring your wallet on this device. Too many wrong tries locks releases and alerts your guardians.',
            bannerIcon: Icons.lock_outline,
            onBack: () => Navigator.of(context).pop(),
            onComplete: (walletPin) =>
                _finishV2(context, onFinished, envelope, s1Hex, s2Hex, walletPin),
          )));
}

/// Returns an error message to keep the user on the wallet-PIN screen, or
/// `null` on success.
Future<String?> _finishV2(BuildContext context, VoidCallback onFinished,
    SplitBackupEnvelope envelope, String s1Hex, String s2Hex, String walletPin) async {
  final store = context.read<WalletStore>();
  showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingVeil(message: 'Verifying…'));
  try {
    final walletPinHash = hashPin(walletPin);
    // Empty `s2Hex` = pre-OPAQUE backup: fall back to the legacy
    // wallet-PIN release for this one restore (re-export afterwards).
    final effectiveS2 = s2Hex.isEmpty
        ? await store.releaseBackupShare(
            backupId: envelope.backupId, walletPinHash: walletPinHash)
        : s2Hex;
    final privateKeyHex =
        store.combineBackupShares(s1Hex: s1Hex, s2Hex: effectiveS2);
    await store.restoreFromPrivateKey(
        privateKeyHex: privateKeyHex, walletPinHash: walletPinHash);
    if (!context.mounted) return null;
    Navigator.of(context).pop(); // dismiss the veil
    onFinished();
    return null;
  } on ApiException catch (e) {
    if (!context.mounted) return null;
    Navigator.of(context).pop(); // dismiss the veil
    if (e.statusCode == 401) return 'Incorrect wallet PIN.';
    if (e.statusCode == 423) {
      return 'Too many attempts — releases are locked for now and your guardians were alerted.';
    }
    if (e.statusCode == 410) {
      return 'This backup was revoked. Use recovery guardians instead.';
    }
    return e.message;
  } catch (_) {
    if (!context.mounted) return null;
    Navigator.of(context).pop(); // dismiss the veil
    return 'Incorrect PIN, or the file is corrupted.';
  }
}

void _pushKeyPin(
    BuildContext context, VoidCallback onFinished, String rawPayload) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => _buildKeyPin(context, onFinished, rawPayload)));
}

Widget _buildKeyPin(
    BuildContext context, VoidCallback onFinished, String rawPayload) {
  return PinEntryScreen(
    title: 'Enter your key PIN',
    subtitle: 'The PIN you set when you saved this Wallet Key certificate.',
    bannerText:
        'Legacy backup (v1) detected — it restores just fine. Its older whole-key format is easier to brute-force than current backups, so back up again right after you get in.\n\nThis PIN unlocks the backup file itself. There is no reset — a wrong PIN simply will not open it.',
    bannerIcon: Icons.key_rounded,
    onBack: () => Navigator.of(context).pop(),
    onComplete: (keyPin) async {
      final store = context.read<WalletStore>();
      try {
        final backup = WalletKeyBackupCodec.decode(rawPayload);
        final privateKeyHex =
            store.decryptBackup(backup: backup, keyPin: keyPin);
        if (!context.mounted) return null;
        _pushWalletPin(context, onFinished, privateKeyHex);
        return null;
      } catch (_) {
        return 'Incorrect PIN, or the file is corrupted.';
      }
    },
  );
}

void _pushWalletPin(
    BuildContext context, VoidCallback onFinished, String privateKeyHex) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (context) =>
          _buildWalletPin(context, onFinished, privateKeyHex)));
}

Widget _buildWalletPin(
    BuildContext context, VoidCallback onFinished, String privateKeyHex) {
  return PinEntryScreen(
    title: 'Enter your wallet PIN',
    subtitle: 'The PIN you use to unlock JamiiPay on this wallet.',
    bannerText:
        'Step 3 of 3 — verified with JamiiPay to finish restoring your wallet on this device.',
    bannerIcon: Icons.lock_outline,
    onBack: () => Navigator.of(context).pop(),
    onComplete: (walletPin) =>
        _finish(context, onFinished, privateKeyHex, walletPin),
  );
}

/// Legacy (v1) finish. Returns an error message to keep the user on the
/// wallet-PIN screen (cleared, shaken in place), or `null` on success.
/// On success, nudges a fresh v2 export before finishing — a restored v1
/// wallet on a new phone with only the old print is one lost print away
/// from being stranded on the weaker format.
Future<String?> _finish(BuildContext context, VoidCallback onFinished,
    String privateKeyHex, String walletPin) async {
  final store = context.read<WalletStore>();
  showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingVeil(message: 'Verifying…'));
  try {
    final walletPinHash = hashPin(walletPin);
    await store.restoreFromPrivateKey(
        privateKeyHex: privateKeyHex, walletPinHash: walletPinHash);
    if (!context.mounted) return null;
    Navigator.of(context).pop(); // dismiss the veil
    AppSnackBar.show(context,
        message:
            'Restored from a legacy (v1) backup. Back up again from Settings to get the current split format.',
        tone: SnackTone.success);
    onFinished();
    return null;
  } on ApiException catch (e) {
    if (!context.mounted) return null;
    Navigator.of(context).pop(); // dismiss the veil
    return e.statusCode == 401 ? 'Incorrect wallet PIN.' : e.message;
  } catch (e) {
    if (!context.mounted) return null;
    Navigator.of(context).pop(); // dismiss the veil
    AppSnackBar.show(context,
        message: 'Could not restore your wallet: $e', tone: SnackTone.danger);
    return 'Could not restore your wallet.';
  }
}
