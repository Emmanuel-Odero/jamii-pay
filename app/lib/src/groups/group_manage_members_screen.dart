import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../models/group.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/avatar_palette.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/info_banner.dart';
import '../widgets/screen_nav.dart';

/// A lightweight "type a payment name" dialog — used to invite someone
/// who isn't in the proposer's Contacts at all (see
/// `crates/server/src/routes/groups.rs`'s `ProposeAddMemberRequest`,
/// which now accepts a bare handle).
Future<String?> _promptHandle(BuildContext context) async {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.navy800,
      title: Text('Invite by payment name',
          style: AppText.ui(size: 15, weight: FontWeight.w700)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: AppText.ui(size: 14),
        decoration: const InputDecoration(hintText: 'e.g. amina42'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Invite')),
      ],
    ),
  );
}

/// "Manage members" — the current roster with a remove action per
/// member, plus a picker to propose adding a contact. Unlike the design
/// prototype (which has no source for this screen at all), every action
/// here doesn't apply instantly: it opens the same approve/withhold/veto
/// vote as a withdrawal (see `GroupProposalAction`), so this screen never
/// mutates membership directly — it only *proposes*.
class GroupManageMembersScreen extends StatelessWidget {
  const GroupManageMembersScreen({
    super.key,
    required this.group,
    required this.myWalletId,
    required this.contacts,
    required this.onBack,
    required this.onProposeAdd,
    required this.onProposeAddByHandle,
    required this.onProposeRemove,
  });

  final Group group;
  final String? myWalletId;
  final List<Contact> contacts;
  final VoidCallback onBack;
  final ValueChanged<Contact> onProposeAdd;

  /// Invites by raw payment handle — works even for someone who isn't in
  /// this wallet's Contacts at all.
  final ValueChanged<String> onProposeAddByHandle;
  final ValueChanged<GroupMember> onProposeRemove;

  @override
  Widget build(BuildContext context) {
    final hasOpenVote = group.openWithdrawalRequestId != null;
    // Only on-Jamii contacts can be invited (they need to accept — see
    // `GroupFlow`'s doc comment on the invite step), and a contact
    // already on the roster (by linked wallet, not by contact-list id —
    // those are different ids) can't be proposed again.
    final memberWalletIds =
        group.members.map((m) => m.walletId).whereType<String>().toSet();
    final addable = contacts
        .where((c) => c.onJamii && !memberWalletIds.contains(c.linkedWalletId))
        .toList();

    return AppScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Manage members', onBack: onBack),
          if (hasOpenVote) ...[
            const InfoBanner(
              icon: Icons.how_to_vote_outlined,
              tone: BannerTone.warning,
              text:
                  'A vote is already open for this group — new proposals have to wait until it resolves.',
            ),
            const SizedBox(height: 14),
          ],
          Text('Current members',
              style: AppText.ui(size: 12, color: AppColors.ink3)),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < group.members.length; i++)
                  _MemberRow(
                    member: group.members[i],
                    isYou: group.members[i].walletId != null &&
                        group.members[i].walletId == myWalletId,
                    colorIndex: i,
                    canRemove: !group.members[i].isOwner && !hasOpenVote,
                    onRemove: () => onProposeRemove(group.members[i]),
                    showBorder: i != group.members.length - 1,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppButton(
            label: 'Invite by payment name',
            variant: AppButtonVariant.outline,
            onPressed: hasOpenVote
                ? null
                : () async {
                    final handle = await _promptHandle(context);
                    if (handle != null && handle.isNotEmpty)
                      onProposeAddByHandle(handle);
                  },
          ),
          const SizedBox(height: 20),
          Text('Add from contacts',
              style: AppText.ui(size: 12, color: AppColors.ink3)),
          const SizedBox(height: 8),
          if (addable.isEmpty)
            Text(
              contacts.any((c) => !c.onJamii)
                  ? "Everyone on Jamii in your contacts is already a member. Contacts who haven't joined Jamii yet can't be invited to a group until they do."
                  : 'Everyone in your contacts is already a member.',
              style: AppText.ui(size: 12, color: AppColors.ink3),
            )
          else
            AppCard(
              child: Column(
                children: [
                  for (var i = 0; i < addable.length; i++)
                    _AddableRow(
                      contact: addable[i],
                      colorIndex: i,
                      enabled: !hasOpenVote,
                      onTap: () => onProposeAdd(addable[i]),
                      showBorder: i != addable.length - 1,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isYou,
    required this.colorIndex,
    required this.canRemove,
    required this.onRemove,
    required this.showBorder,
  });

  final GroupMember member;
  final bool isYou;
  final int colorIndex;
  final bool canRemove;
  final VoidCallback onRemove;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: showBorder
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line2)))
          : null,
      child: Row(
        children: [
          AvatarCircle(
              name: member.name,
              color: avatarPaletteColor(colorIndex),
              size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isYou
                  ? '${member.name} (you)'
                  : member.isOwner
                      ? '${member.name} (owner)'
                      : member.name,
              style: AppText.ui(size: 13, weight: FontWeight.w600),
            ),
          ),
          if (canRemove)
            TextButton(
              onPressed: onRemove,
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.coral, padding: EdgeInsets.zero),
              child: const Text('Remove'),
            ),
        ],
      ),
    );
  }
}

class _AddableRow extends StatelessWidget {
  const _AddableRow(
      {required this.contact,
      required this.colorIndex,
      required this.enabled,
      required this.onTap,
      required this.showBorder});

  final Contact contact;
  final int colorIndex;
  final bool enabled;
  final VoidCallback onTap;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: enabled ? onTap : null,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
      variant: AppCardVariant.plain,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Row(
          children: [
            AvatarCircle(
                name: contact.name,
                color: avatarPaletteColor(colorIndex),
                size: 32),
            const SizedBox(width: 10),
            Expanded(
                child: Text(contact.name,
                    style: AppText.ui(size: 13, weight: FontWeight.w600))),
            Icon(Icons.add_circle_outline, size: 18, color: AppColors.green),
          ],
        ),
      ),
    );
  }
}
