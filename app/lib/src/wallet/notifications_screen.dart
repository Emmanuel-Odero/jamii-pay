import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/escrow_claim.dart';
import '../models/group.dart';
import '../models/wallet.dart';
import '../notifications/device_badge.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/screen_nav.dart';
import '../widgets/skeleton.dart';

/// Wallet → notification bell. Previously a dead end (`onComingSoon`) with
/// no screen behind it at all — this is a real, if simple, feed: computed
/// entirely from data that already exists (pending/expiring escrow
/// claims, this wallet's recovery history), not a fake list and not
/// another snackbar.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen(
      {super.key,
      required this.onBack,
      required this.onPendingClaims,
      required this.onOpenGroup});

  final VoidCallback onBack;
  final VoidCallback onPendingClaims;
  final ValueChanged<String> onOpenGroup;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<RecoverySummary>? _recovery;
  List<GroupInvite>? _invites;
  List<Group>? _groups;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Opening the feed is the acknowledgement — drop the icon badge.
    DeviceBadge.clear();
    _load();
  }

  // Each source is independent — one failing (e.g. a transient network
  // blip on just the invites call) used to blank the *entire* screen
  // behind a single error, which looked exactly like "notifications
  // don't work" even when most of the feed was fine. Every source now
  // fails on its own and defaults to "nothing from this source" instead.
  Future<void> _load() async {
    final store = context.read<WalletStore>();

    // Four independent sources, run concurrently rather than one after
    // another — each already fails on its own (see the class doc comment
    // above), but awaiting them in sequence meant a fast source still
    // waited behind however long the slowest one took.
    String? error;
    final refreshFuture = store.refresh().catchError((Object e) {
      error = '$e';
    });
    final recoveryFuture =
        _tryLoad(store.listRecoveryHistory, const <RecoverySummary>[]);
    final invitesFuture = _tryLoad(store.listInvites, const <GroupInvite>[]);
    final groupsFuture = _tryLoad(() async {
      await store.loadGroups();
      return store.groups;
    }, const <Group>[]);

    await refreshFuture;
    final recovery = await recoveryFuture;
    final invites = await invitesFuture;
    final groups = await groupsFuture;

    if (!mounted) return;
    setState(() {
      _recovery = recovery;
      _invites = invites;
      _groups = groups;
      _error = error;
    });
  }

  /// Runs [load], returning [fallback] instead of throwing — each of the
  /// three data sources needs a value even when its own fetch fails,
  /// without hiding the rest of the feed behind that one failure.
  Future<T> _tryLoad<T>(Future<T> Function() load, T fallback) async {
    try {
      return await load();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _respond(GroupInvite invite, bool accept) async {
    try {
      await context.read<WalletStore>().respondToInvite(
          groupId: invite.groupId, requestId: invite.requestId, accept: accept);
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: accept
            ? 'Joined the vote to add you to ${invite.groupName}.'
            : 'Declined the invite to ${invite.groupName}.',
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(context,
          message: 'Could not respond: $e', tone: SnackTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final claims = context.watch<WalletStore>().escrowClaims;
    final invites = _invites ?? const [];
    final openGroupVotes = (_groups ?? const [])
        .where((g) => g.openWithdrawalRequestId != null)
        .toList();
    final everythingLoaded =
        _recovery != null && _invites != null && _groups != null;
    final nothingToShow = everythingLoaded &&
        claims.isEmpty &&
        _recovery!.isEmpty &&
        invites.isEmpty &&
        openGroupVotes.isEmpty;

    return AppScreen(
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Notifications', onBack: widget.onBack),
          // Non-blocking — a refresh hiccup shouldn't hide whatever
          // else loaded fine (invites, group votes, recovery history).
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Text('Some notifications might be stale: $_error',
                  style: AppText.ui(size: 11, color: AppColors.coral)),
            ),
          if (!everythingLoaded)
            const Expanded(child: SkeletonCard(lines: 2))
          else if (nothingToShow)
            Expanded(
              child: Center(
                child: Text('Nothing to show yet.',
                    style: AppText.ui(size: 13, color: AppColors.ink3)),
              ),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  for (final invite in invites)
                    _InviteNotification(
                        invite: invite,
                        onAccept: () => _respond(invite, true),
                        onDecline: () => _respond(invite, false)),
                  for (final group in openGroupVotes)
                    _GroupVoteNotification(
                        group: group,
                        onTap: () => widget.onOpenGroup(group.id)),
                  for (final claim in claims)
                    _ClaimNotification(
                        claim: claim, onTap: widget.onPendingClaims),
                  for (final recovery in _recovery!)
                    _RecoveryNotification(recovery: recovery),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InviteNotification extends StatelessWidget {
  const _InviteNotification(
      {required this.invite, required this.onAccept, required this.onDecline});
  final GroupInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: AppCard(
        variant: AppCardVariant.selected,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.group_add_outlined, size: 18, color: AppColors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "You're invited to join ${invite.groupName}",
                    style: AppText.ui(size: 12.5, weight: FontWeight.w700),
                  ),
                ),
                // Invites are actionable until accepted/declined, so they
                // always carry the dot — unlike chats, there is no
                // "read" state to clear here, only the decision itself.
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: AppColors.blue, shape: BoxShape.circle),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Accepting only opens the group\'s vote — you\'re not a member until it passes.',
              style: AppText.ui(size: 11, color: AppColors.ink3),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDecline,
                    style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.line2)),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: AppColors.onGreen),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupVoteNotification extends StatelessWidget {
  const _GroupVoteNotification({required this.group, required this.onTap});
  final Group group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: AppCard(
        onTap: onTap,
        variant: AppCardVariant.amber,
        child: Row(
          children: [
            Icon(Icons.how_to_vote_outlined, size: 18, color: AppColors.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${group.name}: vote open',
                      style: AppText.ui(size: 12.5, weight: FontWeight.w700)),
                  Text(group.openProposalSummary ?? 'Tap to review',
                      style: AppText.ui(size: 11, color: AppColors.amber)),
                ],
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: AppColors.amber, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClaimNotification extends StatelessWidget {
  const _ClaimNotification({required this.claim, required this.onTap});
  final EscrowClaim claim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final left = claim.timeLeft;
    final soon = left.inHours < 12;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: AppCard(
        onTap: onTap,
        variant: soon ? AppCardVariant.amber : AppCardVariant.plain,
        child: Row(
          children: [
            Icon(Icons.hourglass_top,
                size: 18, color: soon ? AppColors.amber : AppColors.ink3),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\$${claim.amountUsd.toStringAsFixed(2)} held for ${claim.recipientAddr}',
                    style: AppText.ui(size: 12.5, weight: FontWeight.w700),
                  ),
                  Text(
                    soon ? 'Claim window closes soon' : 'Waiting to be claimed',
                    style: AppText.ui(
                        size: 11,
                        color: soon ? AppColors.amber : AppColors.ink3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryNotification extends StatelessWidget {
  const _RecoveryNotification({required this.recovery});
  final RecoverySummary recovery;

  @override
  Widget build(BuildContext context) {
    final label = switch (recovery.status) {
      'pending_approvals' => 'Recovery started — waiting for approvals',
      'waiting' => 'Recovery approved — 48-hour wait in progress',
      'completed' => 'Recovery completed',
      'cancelled' => 'Recovery cancelled',
      _ => 'Recovery ${recovery.status}',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: AppCard(
        variant: AppCardVariant.plain,
        child: Row(
          children: [
            Icon(Icons.shield_outlined, size: 18, color: AppColors.blue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppText.ui(size: 12.5, weight: FontWeight.w700)),
                  Text(_formatDate(recovery.startedAt),
                      style: AppText.ui(size: 11, color: AppColors.ink3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
