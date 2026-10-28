import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/wallet_store.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_snackbar.dart';
import 'recovery_approvals_screen.dart';
import 'recovery_start_screen.dart';
import 'recovery_veto_screen.dart';
import 'recovery_waiting_screen.dart';

/// Chains R1 → R2 → R3 (the owner's own device shows R4 separately, since
/// it's pushed to a *different* device than the one running recovery).
/// Each step is backed by the real `POST /recovery` / `GET /recovery/:id` /
/// `POST /recovery/:id/approvals` / `POST /recovery/:id/cancel` endpoints.
///
/// Deliberately doesn't require an active `WalletStore.wallet` — this is
/// the flow for a device that has *lost* its session (a stolen or wiped
/// phone), so it only ever reads a pre-filled handle as a convenience for
/// the in-app "Lost your phone?" demo entry point, never as a requirement.
Widget buildRecoveryStart(BuildContext context) {
  final wallet = context.read<WalletStore>().wallet;

  Future<void> start(String handle, {required bool reportedStolen}) async {
    final store = context.read<WalletStore>();
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const LoadingVeil(message: 'Starting recovery…'));
    try {
      final status = await store.startRecovery(
          fullHandle: handle, reportedStolen: reportedStolen);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _pushApprovals(context, status.id);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      AppSnackBar.show(context,
          message: 'Could not start recovery: $e', tone: SnackTone.danger);
    }
  }

  return RecoveryStartScreen(
    initialHandle: wallet?.fullHandle,
    onBack: () => Navigator.of(context).pop(),
    onContinue: (handle) => start(handle, reportedStolen: false),
    onReportStolen: (handle) => start(handle, reportedStolen: true),
  );
}

void _pushApprovals(BuildContext context, String recoveryId) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (context) => FutureBuilder(
      future: context.read<WalletStore>().getRecovery(recoveryId),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const AppLoading(label: 'Loading recovery…');
        final status = snapshot.data!;
        return RecoveryApprovalsScreen(
          guardians: status.guardians,
          approvals: status.approvals,
          threshold: status.threshold,
          onBack: () => Navigator.of(context).pop(),
          onStartWait: () =>
              _approveAndWait(context, recoveryId, status.guardians),
        );
      },
    ),
  ));
}

/// This device has no other device/guardian to actually approve from, so
/// recovery here submits an approval for every guardian type the wallet was
/// set up with — a stand-in for the real multi-device approval flow, but
/// every approval is still a genuine `POST /recovery/:id/approvals` call
/// against the server's real threshold logic.
Future<void> _approveAndWait(
    BuildContext context, String recoveryId, List<String> guardians) async {
  final store = context.read<WalletStore>();
  showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingVeil(message: 'Submitting approval…'));
  try {
    var status = await store.getRecovery(recoveryId);
    for (final guardian in guardians) {
      if (status.approvals.length >= status.threshold) break;
      if (status.approvals.contains(guardian)) continue;
      status = await store.approveRecovery(recoveryId, guardian);
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
    final waitCompletesAt =
        status.waitCompletesAt ?? DateTime.now().add(const Duration(hours: 48));
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RecoveryWaitingScreen(
        startedAt: status.startedAt.toLocal(),
        waitCompletesAt: waitCompletesAt.toLocal(),
        onCancelledRecovery: () => _cancel(context, recoveryId),
      ),
    ));
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    AppSnackBar.show(context,
        message: 'Could not record approvals: $e', tone: SnackTone.danger);
  }
}

Future<void> _cancel(BuildContext context, String recoveryId) async {
  final store = context.read<WalletStore>();
  try {
    await store.cancelRecovery(recoveryId);
  } catch (_) {
    // Best-effort — still return the user to the wallet either way.
  }
  if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
}

/// R4 is reached independently — it's the notification shown on the real
/// owner's *other* device when a recovery they didn't start is in
/// progress, not a step the person recovering ever sees. No push-delivery
/// infrastructure exists yet to route this to another device, so this
/// screen stays a demo entry point (see `wallet_flow.dart`'s Settings tab).
Widget buildRecoveryVeto(BuildContext context) {
  final now = DateTime.now();
  final completes = now.add(const Duration(hours: 48));
  String fmt(DateTime dt) =>
      '${dt.day} Aug · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  return RecoveryVetoScreen(
    startedLabel: fmt(now),
    completesLabel: fmt(completes),
    onStopRecovery: () => Navigator.of(context).pop(),
    onThisWasMe: () => Navigator.of(context).pop(),
  );
}
