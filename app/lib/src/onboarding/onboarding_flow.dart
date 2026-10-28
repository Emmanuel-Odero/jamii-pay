import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/session_storage.dart';
import '../recovery/recovery_flow.dart';
import '../security/local_auth_service.dart';
import '../security/pin_hash.dart';
import '../state/wallet_store.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_snackbar.dart';
import 'biometric_screen.dart';
import 'done_screen.dart';
import 'guardians_screen.dart';
import 'handle_screen.dart';
import 'language_screen.dart';
import 'pin_screen.dart';
import 'restore_choice_screen.dart';
import 'restore_from_key_flow.dart';
import 'welcome_screen.dart';

/// Chains the seven onboarding screens together with plain
/// `Navigator.push`/`pop` — each screen only knows about the callbacks it
/// was given, not about the flow as a whole. The entry point
/// ([buildWelcome]) is what the router points `/` at.
Widget buildWelcome(BuildContext context, VoidCallback onFinished) {
  return WelcomeScreen(
    onCreateWallet: () => _pushLanguage(context, onFinished),
    // There's no separate "sign in" mechanism in this product — recovery
    // (guardian approval) or a downloaded wallet key are how you get back
    // into a wallet on a device that never held it. This used to just
    // repeat onboarding, which can't actually get anyone back into an
    // existing wallet.
    onHaveWallet: () => _pushRestoreChoice(context, onFinished),
  );
}

void _pushRestoreChoice(BuildContext context, VoidCallback onFinished) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (context) => RestoreChoiceScreen(
      onBack: () => Navigator.of(context).pop(),
      onRestoreFromKey: () => pushRestoreFromKeyFlow(context, onFinished),
      onGuardianRecovery: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: buildRecoveryStart)),
    ),
  ));
}

void _pushLanguage(BuildContext context, VoidCallback onFinished) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (context) => LanguageScreen(
      onBack: () => Navigator.of(context).pop(),
      onContinue: () => _pushPin(context, onFinished),
    ),
  ));
}

void _pushPin(BuildContext context, VoidCallback onFinished) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (context) => PinScreen(
      onBack: () => Navigator.of(context).pop(),
      onComplete: (pin) => _savePinAndContinue(context, onFinished, pin),
    ),
  ));
}

/// The PIN typed here is what the lock screen checks against on every
/// future cold start (see `security/lock_screen.dart` and
/// `router/app_router.dart`'s `_Bootstrap`) — this used to be discarded
/// the moment the user typed it, so nothing ever actually locked the app.
Future<void> _savePinAndContinue(
    BuildContext context, VoidCallback onFinished, String pin) async {
  await const SessionStorage().savePinHash(hashPin(pin));
  await const SessionStorage().saveOnboardingStep('pin');
  if (!context.mounted) return;
  _pushBiometric(context, onFinished);
}

void _pushBiometric(BuildContext context, VoidCallback onFinished) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (context) => BiometricScreen(
      onBack: () => Navigator.of(context).pop(),
      onEnable: () => _enableBiometricAndContinue(context, onFinished),
      onSkip: () => _pushHandle(context, onFinished),
    ),
  ));
}

/// A real platform biometric prompt, not a button that just advances the
/// flow — "Enable fingerprint" only actually enables it if the OS confirms
/// a real match.
Future<void> _enableBiometricAndContinue(
    BuildContext context, VoidCallback onFinished) async {
  final auth = LocalAuthService();
  final supported = await auth.isSupported;
  if (!context.mounted) return;
  if (!supported) {
    AppSnackBar.show(
      context,
      message:
          'No biometric sensor is enrolled on this device. Use "Not now" instead.',
      tone: SnackTone.danger,
    );
    return;
  }
  final matched = await auth
      .authenticate('Confirm to enable fingerprint unlock for JamiiPay');
  if (!context.mounted) return;
  if (matched) {
    await const SessionStorage().saveBiometricEnabled(true);
    if (!context.mounted) return;
    _pushHandle(context, onFinished);
  } else {
    AppSnackBar.show(
      context,
      message:
          'Could not confirm your fingerprint. Try again, or tap "Not now".',
      tone: SnackTone.danger,
    );
  }
}

void _pushHandle(BuildContext context, VoidCallback onFinished) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (context) => HandleScreen(
      onBack: () => Navigator.of(context).pop(),
      onClaim: (fullHandle) => _pushGuardians(context, onFinished, fullHandle),
    ),
  ));
}

void _pushGuardians(
    BuildContext context, VoidCallback onFinished, String fullHandle) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (context) => GuardiansScreen(
      onBack: () => Navigator.of(context).pop(),
      onConfirm: (guardians) =>
          _createWalletAndFinish(context, onFinished, fullHandle, guardians),
    ),
  ));
}

/// The point where onboarding stops being a UI walkthrough and becomes a
/// real account: generates a real key via the `wallet-core` FFI bridge and
/// registers the wallet with `POST /wallets`.
Future<void> _createWalletAndFinish(
  BuildContext context,
  VoidCallback onFinished,
  String fullHandle,
  Set<String> guardians,
) async {
  final store = context.read<WalletStore>();
  final handleBase = fullHandle.substring(0, fullHandle.length - 1);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const LoadingVeil(message: 'Creating wallet…'),
  );

  try {
    // Saved by the PIN step earlier in this same flow (see `_savePinAndContinue`) —
    // read back rather than threaded through every callback in between.
    final pinHash = await const SessionStorage().readPinHash();
    if (pinHash == null)
      throw StateError('PIN was not set before wallet creation');
    await store.createWallet(
        handleBase: handleBase, guardians: guardians, pinHash: pinHash);
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss the veil
    _pushDone(context, onFinished, store.wallet!.handleBase,
        store.wallet!.handleCheckDigit);
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss the veil
    AppSnackBar.show(context,
        message: 'Could not create your wallet: $e', tone: SnackTone.danger);
  }
}

void _pushDone(BuildContext context, VoidCallback onFinished, String handleBase,
    String handleCheckDigit) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (context) => DoneScreen(
      handleBase: handleBase,
      handleCheckDigit: handleCheckDigit,
      // Used to be identical to onGoToWallet — "Share my payment name"
      // didn't actually share anything. A real share sheet now, then
      // finish onboarding either way (declining the share sheet shouldn't
      // strand the user on this screen).
      onShare: () {
        final box = context.findRenderObject() as RenderBox?;
        final origin =
            box != null ? box.localToGlobal(Offset.zero) & box.size : null;
        Share.share('Pay me on JamiiPay: $handleBase$handleCheckDigit',
            sharePositionOrigin: origin);
        onFinished();
      },
      onGoToWallet: onFinished,
    ),
  ));
}
