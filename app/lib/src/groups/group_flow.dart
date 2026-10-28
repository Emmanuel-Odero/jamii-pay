import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/chat_screen.dart';
import '../data/api_client.dart';
import '../data/money_math.dart';
import '../models/group.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/amount_prompt.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/review_sheet.dart';
import '../widgets/skeleton.dart';
import 'broadcast_send_screen.dart';
import 'group_detail_screen.dart';
import 'group_manage_members_screen.dart';
import 'group_new_screen.dart';
import 'group_vote_screen.dart';
import 'groups_screen.dart';

/// Chains every Groups/Chamas screen together — mirrors the other
/// `*_flow.dart` files' plain-`Navigator.push` chaining pattern (see
/// `onboarding_flow.dart`, `recovery_flow.dart`).
Widget buildGroups(BuildContext context) {
  return GroupsScreen(
    onNewGroup: () => Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => _buildNewGroup(context))),
    onOpenGroup: (group) => _pushDetail(context, group.id),
  );
}

Widget _buildNewGroup(BuildContext context) {
  return GroupNewScreen(
    onBack: () => Navigator.of(context).pop(),
    onCreate: (name, kind, power, memberIds) =>
        _createGroup(context, name, kind, power, memberIds),
  );
}

Future<void> _createGroup(
  BuildContext context,
  String name,
  GroupKind kind,
  GroupPowerScheme power,
  Set<String> memberIds,
) async {
  final store = context.read<WalletStore>();
  showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingVeil(message: 'Creating group…'));
  try {
    final group = await store.createGroup(
        name: name,
        kind: kind,
        powerScheme: power,
        memberContactIds: memberIds.toList());
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss veil
    Navigator.of(context).pop(); // back to Groups list
    _pushDetail(context, group.id);
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    AppSnackBar.show(context,
        message: 'Could not create group: $e', tone: SnackTone.danger);
  }
}

/// Public entry point for jumping straight to a group's detail screen
/// from outside this flow — e.g. `NotificationsScreen`'s "vote open" card.
void pushGroupDetail(BuildContext context, String groupId) =>
    _pushDetail(context, groupId);

void _pushDetail(BuildContext context, String groupId) {
  Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => _DetailLoader(groupId: groupId)));
}

/// Reloads the group on every push rather than trusting `WalletStore.groups`
/// to already be fresh — contribute/vote/execute all mutate server state
/// that this screen needs to reflect immediately.
class _DetailLoader extends StatefulWidget {
  const _DetailLoader({required this.groupId});
  final String groupId;

  @override
  State<_DetailLoader> createState() => _DetailLoaderState();
}

class _DetailLoaderState extends State<_DetailLoader> {
  late Future<Group> _future =
      context.read<WalletStore>().getGroup(widget.groupId);

  void _reload() => setState(
      () => _future = context.read<WalletStore>().getGroup(widget.groupId));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Group>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: AppColors.navy900,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Could not load group',
                        style: AppText.ui(
                            size: 16, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('Check your connection and try again.',
                        style: AppText.ui(
                            size: 13, color: AppColors.ink3)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _reload,
                        child: const Text('Retry'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Go back'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          // Skeleton matching the detail hero + member list shape,
          // with cached stale data underneath when available.
          final cached = context
              .read<WalletStore>()
              .groups
              .where((g) => g.id == widget.groupId);
          return Scaffold(
            backgroundColor: AppColors.navy900,
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (cached.isNotEmpty)
                      Text(cached.first.name,
                          style: AppText.ui(
                              size: 16, weight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    const SkeletonCard(lines: 2),
                    const SizedBox(height: 12),
                    const SkeletonCard(lines: 4),
                    const SizedBox(height: 12),
                    Text('Loading latest…',
                        style: AppText.ui(
                            size: 12, color: AppColors.ink3)),
                  ],
                ),
              ),
            ),
          );
        }
        final group = snapshot.data!;
        return GroupDetailScreen(
          group: group,
          myWalletId: context.read<WalletStore>().wallet?.id,
          onBack: () => Navigator.of(context).pop(),
          onContribute: () => _contribute(context, group.id, _reload),
          onRequestWithdrawal: () => _promptWithdrawal(context, group, _reload),
          onOpenVote: () => _pushVote(
              context, group, group.openWithdrawalRequestId!, _reload),
          onBroadcast: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => BroadcastSendScreen(
              group: group,
              onBack: () => Navigator.of(context).pop(),
              onSend: (amount, walletIds) =>
                  _broadcast(context, group.id, amount, walletIds),
            ),
          )),
          onManageMembers: () => _pushManageMembers(context, group, _reload),
          onChat: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => ChatScreen(
              title: group.name,
              myWalletId: context.read<WalletStore>().wallet?.id ?? '',
              fetchMessages: () =>
                  context.read<WalletStore>().listGroupMessages(group.id),
              sendMessage: (body, replyToId) => context
                  .read<WalletStore>()
                  .sendGroupMessage(
                      groupId: group.id, body: body, replyToId: replyToId),
              setPinned: (id, pinned) => context
                  .read<WalletStore>()
                  .setMessagePinned(messageId: id, pinned: pinned),
              onBack: () => Navigator.of(context).pop(),
            ),
          )),
        );
      },
    );
  }
}

Future<void> _contribute(
    BuildContext context, String groupId, VoidCallback onDone) async {
  final everydayUsd =
      context.read<WalletStore>().wallet?.everydayBalanceUsd ?? 0;
  final amount = await promptAmountUsd(
    context,
    title: 'Contribute to the pot',
    subtitle: 'How much do you want to add?',
    maxUsd: everydayUsd,
  );
  if (amount == null || !context.mounted) return;
  await _submitContribution(context, groupId, (amount * 100).round(), onDone);
}

Future<void> _submitContribution(BuildContext context, String groupId,
    int amountUsdCents, VoidCallback onDone) async {
  final store = context.read<WalletStore>();
  try {
    await store.contributeToGroup(
        groupId: groupId, amountUsdCents: amountUsdCents);
    if (!context.mounted) return;
    AppSnackBar.show(context,
        message: 'Contributed \$${(amountUsdCents / 100).toStringAsFixed(2)}');
    onDone();
  } on ApiException catch (e) {
    if (!context.mounted) return;
    AppSnackBar.show(context, message: e.message, tone: SnackTone.danger);
  }
}

Future<void> _promptWithdrawal(
    BuildContext context, Group group, VoidCallback onDone) async {
  final amountController =
      TextEditingController(text: (group.potUsd).toStringAsFixed(2));
  final payeeController = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.navy800,
      title: Text('Request a withdrawal',
          style: AppText.ui(size: 15, weight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Amount (USD)',
              style: AppText.ui(size: 11, color: AppColors.ink3)),
          TextField(
              controller: amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: AppText.ui(size: 14)),
          const SizedBox(height: 12),
          Text('Pay to', style: AppText.ui(size: 11, color: AppColors.ink3)),
          TextField(
              controller: payeeController,
              style: AppText.ui(size: 14),
              decoration:
                  const InputDecoration(hintText: 'e.g. Kakuma Water Co.')),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open vote')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final amount = double.tryParse(amountController.text) ?? 0;
  final payee = payeeController.text.trim();
  if (amount <= 0 || payee.isEmpty) return;

  final store = context.read<WalletStore>();
  try {
    final withdrawal = await store.openWithdrawal(
        groupId: group.id,
        amountUsdCents: (amount * 100).round(),
        payeeName: payee);
    if (!context.mounted) return;
    onDone();
    _pushVote(context, group, withdrawal.id, onDone);
  } on ApiException catch (e) {
    if (!context.mounted) return;
    AppSnackBar.show(context, message: e.message, tone: SnackTone.danger);
  }
}

void _pushVote(BuildContext context, Group group, String requestId,
    VoidCallback onParentReload) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (context) => _VoteLoader(
        group: group, requestId: requestId, onParentReload: onParentReload),
  ));
}

class _VoteLoader extends StatefulWidget {
  const _VoteLoader(
      {required this.group,
      required this.requestId,
      required this.onParentReload});
  final Group group;
  final String requestId;
  final VoidCallback onParentReload;

  @override
  State<_VoteLoader> createState() => _VoteLoaderState();
}

class _VoteLoaderState extends State<_VoteLoader> {
  late Future<GroupWithdrawal> _future = _load();

  Future<GroupWithdrawal> _load() => context
      .read<WalletStore>()
      .getWithdrawal(groupId: widget.group.id, requestId: widget.requestId);

  void _reload() => setState(() => _future = _load());

  String? get _myMemberId {
    final myWalletId = context.read<WalletStore>().wallet?.id;
    final mine = widget.group.members.where((m) => m.walletId == myWalletId);
    return mine.isEmpty ? null : mine.first.id;
  }

  Future<void> _vote(VoteChoice choice) async {
    final myId = _myMemberId;
    if (myId == null) return;
    final store = context.read<WalletStore>();
    try {
      await store.castVote(
          groupId: widget.group.id,
          requestId: widget.requestId,
          memberId: myId,
          choice: choice);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      AppSnackBar.show(context, message: e.message, tone: SnackTone.danger);
    }
  }

  Future<void> _execute() async {
    final store = context.read<WalletStore>();
    try {
      await store.executeWithdrawal(
          groupId: widget.group.id, requestId: widget.requestId);
      if (!mounted) return;
      widget.onParentReload();
      _reload();
      AppSnackBar.show(context, message: 'Paid out');
    } on ApiException catch (e) {
      if (!mounted) return;
      AppSnackBar.show(context, message: e.message, tone: SnackTone.danger);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GroupWithdrawal>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
              backgroundColor: AppColors.navy900,
              body: const AppLoading(label: 'Loading proposal…'));
        }
        return GroupVoteScreen(
          withdrawal: snapshot.data!,
          myMemberId: _myMemberId,
          onBack: () {
            widget.onParentReload();
            Navigator.of(context).pop();
          },
          onVote: _vote,
          onExecute: _execute,
        );
      },
    );
  }
}

Future<void> _broadcast(BuildContext context, String groupId,
    int amountPerMemberUsdCents, List<String> memberWalletIds) async {
  final store = context.read<WalletStore>();
  final fx = await store.getFxRate();
  final perMember = amountPerMemberUsdCents / 100;
  final total = perMember * memberWalletIds.length;
  if (!context.mounted) return;
  // Fee transparency per member (was missing: no KES, no fee total).
  final confirmed = await MoneyReviewSheet.show(
    context: context,
    title: 'Review broadcast',
    quote: MoneyQuote(
      amountUsd: total,
      feeUsd: 0,
      totalDebitUsd: total,
      theyReceiveUsd: total,
      rateKesPerUsd: fx.rate,
      rateUpdatedAt: fx.updatedAt,
      arrivalLabel: '~15 seconds',
    ),
    recipientFallback:
        '${memberWalletIds.length} members · \$${perMember.toStringAsFixed(2)} each',
    confirmLabel: 'Send to everyone',
  );
  if (!confirmed || !context.mounted) return;
  showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingVeil(message: 'Sending…'));
  try {
    await store.broadcastToGroup(
        groupId: groupId,
        amountPerMemberUsdCents: amountPerMemberUsdCents,
        memberWalletIds: memberWalletIds);
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss veil
    Navigator.of(context).pop(); // back to detail
    AppSnackBar.show(context,
        message:
            'Sent \$${perMember.toStringAsFixed(2)} each to ${memberWalletIds.length} members.',
        actionLabel: 'View',
        onAction: () {});
  } on ApiException catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    AppSnackBar.show(context, message: e.message, tone: SnackTone.danger);
  } catch (_) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    AppSnackBar.showMoneyError(context, 'Could not broadcast');
  }
}

void _pushManageMembers(
    BuildContext context, Group group, VoidCallback onDone) {
  final store = context.read<WalletStore>();
  if (store.contacts.isEmpty) store.loadContacts();
  Navigator.of(context).push(MaterialPageRoute(
    builder: (context) => Consumer<WalletStore>(
      builder: (context, store, _) => GroupManageMembersScreen(
        group: group,
        myWalletId: store.wallet?.id,
        contacts: store.contacts,
        onBack: () => Navigator.of(context).pop(),
        onProposeAdd: (contact) => _proposeAddMember(context, group, onDone,
            contactId: contact.id, name: contact.name),
        onProposeAddByHandle: (handle) => _proposeAddMember(
            context, group, onDone,
            handle: handle, name: handle),
        onProposeRemove: (member) =>
            _proposeRemoveMember(context, group, member, onDone),
      ),
    ),
  ));
}

/// Sends an invite — this does NOT open a group vote yet. The rest of
/// the group only finds out (and gets to vote) once the invitee accepts;
/// see `crates/server/src/routes/groups.rs`'s `propose_add_member` doc
/// comment. Nothing to navigate to here, since there's no vote screen
/// yet — just confirm the invite went out.
Future<void> _proposeAddMember(
    BuildContext context, Group group, VoidCallback onDone,
    {String? contactId, String? handle, required String name}) async {
  final store = context.read<WalletStore>();
  try {
    await store.proposeAddMember(
        groupId: group.id, contactId: contactId, handle: handle);
    if (!context.mounted) return;
    onDone();
    AppSnackBar.show(context,
        message: 'Invited $name — they need to accept before the group votes.');
  } on ApiException catch (e) {
    if (!context.mounted) return;
    AppSnackBar.show(context, message: e.message, tone: SnackTone.danger);
  }
}

Future<void> _proposeRemoveMember(BuildContext context, Group group,
    GroupMember member, VoidCallback onDone) async {
  final confirmed = await confirmDialog(
    context,
    title: 'Propose removing ${member.name}?',
    message:
        'This opens a vote — ${member.name} only leaves the group once the vote actually passes.',
    confirmLabel: 'Open vote',
  );
  if (!confirmed || !context.mounted) return;

  final store = context.read<WalletStore>();
  try {
    final withdrawal =
        await store.proposeRemoveMember(groupId: group.id, memberId: member.id);
    if (!context.mounted) return;
    onDone();
    Navigator.of(context)
        .pop(); // back to detail — the vote screen replaces Manage Members on top
    _pushVote(context, group, withdrawal.id, onDone);
  } on ApiException catch (e) {
    if (!context.mounted) return;
    AppSnackBar.show(context, message: e.message, tone: SnackTone.danger);
  }
}
