import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../onboarding/onboarding_flow.dart';
import '../recovery/recovery_flow.dart';
import '../security/lock_screen.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../wallet/wallet_flow.dart';
import '../widgets/jamii_logo.dart';

/// Two top-level destinations: the onboarding flow (`/`) and the wallet
/// shell (`/wallet`). Recovery and search are reached by pushing on top of
/// the wallet shell (see [[wallet_flow.dart]]) rather than being separate
/// top-level routes — that matches how they're actually entered in the
/// design (from within the app, not as deep links).
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const _Bootstrap(),
    ),
    GoRoute(
      path: '/wallet',
      builder: (context, state) => const WalletFlow(),
    ),
  ],
);

/// Checks for a persisted session (secure-storage-backed wallet id) before
/// showing onboarding — a returning user who already created a wallet
/// should never see the "create/have a wallet" screen again.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<bool> _hasSession =
      context.read<WalletStore>().restoreSession();
  bool _unlocked = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasSession,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: AppColors.navy900,
            body: const Center(child: JamiiLogo(size: 64)),
          );
        }
        if (snapshot.data == true) {
          if (!_unlocked) {
            // The PIN/biometric screens set during onboarding are the ones
            // being checked against here — see `security/lock_screen.dart`.
            return LockScreen(
              onUnlocked: () => setState(() => _unlocked = true),
              onForgotPin: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: buildRecoveryStart)),
            );
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/wallet');
          });
          return Scaffold(backgroundColor: AppColors.navy900);
        }
        return buildWelcome(context, () => context.go('/wallet'));
      },
    );
  }
}
