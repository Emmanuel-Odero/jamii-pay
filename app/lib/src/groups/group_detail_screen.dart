import 'package:flutter/material.dart';

import '../models/group.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/avatar_palette.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/group_member_row.dart';
import '../widgets/handle_chip.dart';
import '../widgets/screen_nav.dart';
import '../widgets/segmented_bar.dart';

/// Group detail — hero card, voting-power split, member list, and the
/// per-kind footer actions. Matches
/// `designs/jammii-pay-prototype.html`'s `groupDetail` screen.
class GroupDetailScreen extends StatelessWidget {
  const GroupDetailScreen({
    super.key,
    required this.group,
    required this.myWalletId,
    required this.onBack,
    required this.onContribute,
    required this.onRequestWithdrawal,
    required this.onOpenVote,
    required this.onBroadcast,
    required this.onManageMembers,
    required this.onChat,
  });

  final Group group;

  /// The signed-in wallet's id — compared against each member's
  /// `walletId` to find "(you)". NOT the same as [GroupMember.isOwner],
  /// which marks who *created* the group, not who's currently looking at
  /// it (a bug: those two were conflated here before, so on a device
  /// signed into a different wallet than the one that created the group,
  /// the owner — not the viewer — was wrongly tagged "(you)").
  final String? myWalletId;
  final VoidCallback onBack;
  final VoidCallback onContribute;
  final VoidCallback onRequestWithdrawal;
  final VoidCallback onOpenVote;
  final VoidCallback onBroadcast;
  final VoidCallback onManageMembers;
  final VoidCallback onChat;

  static List<Color> get _powerColors =>
      [AppColors.blue, AppColors.green, AppColors.amber, AppColors.coral];

  @override
  Widget build(BuildContext context) {
    final isPool = group.kind == GroupKind.pool;

    return AppScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(
            title: group.name,
            onBack: onBack,
            trailing: InkWell(
              onTap: onChat,
              borderRadius: BorderRadius.circular(9),
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line2),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(Icons.chat_bubble_outline,
                    color: AppColors.ink2, size: 15),
              ),
            ),
          ),
          AppCard(
            variant: isPool ? AppCardVariant.green : AppCardVariant.plain,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isPool) ...[
                  Text('Pooled',
                      style: AppText.balanceLabel(color: AppColors.green)),
                  Text('\$${group.potUsd.toStringAsFixed(2)}',
                      style: AppText.display(size: 25)),
                ] else ...[
                  Text('Members', style: AppText.balanceLabel()),
                  Text('${group.members.length}',
                      style: AppText.display(size: 25)),
                ],
                const SizedBox(height: 9),
                HandleChip(
                  base: group.fullHandle
                      .substring(0, group.fullHandle.length - 1),
                  checkDigit:
                      group.fullHandle.substring(group.fullHandle.length - 1),
                  size: HandleChipSize.small,
                ),
              ],
            ),
          ),
          if (group.openWithdrawalRequestId != null) ...[
            const SizedBox(height: 9),
            AppCard(
              variant: AppCardVariant.amber,
              onTap: onOpenVote,
              child: Text(
                'Vote open: ${group.openProposalSummary ?? 'tap to review'}',
                style: AppText.ui(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: AppColors.amber),
              ),
            ),
          ],
          if (isPool) ...[
            const SizedBox(height: 18),
            Text('Voting power',
                style: AppText.ui(size: 12, color: AppColors.ink3)),
            const SizedBox(height: 8),
            SegmentedBar(
              segments: [
                for (var i = 0; i < group.members.length; i++)
                  (
                    group.members[i].power,
                    _powerColors[i % _powerColors.length]
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_powerSchemeLabel(group.powerScheme.name)} split · majority + no veto to pass',
              style: AppText.ui(size: 12, color: AppColors.ink3),
            ),
          ],
          const SizedBox(height: 18),
          Text('Members', style: AppText.ui(size: 12, color: AppColors.ink3)),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < group.members.length; i++)
                  GroupMemberRow(
                    name: group.members[i].name,
                    isYou: group.members[i].walletId != null &&
                        group.members[i].walletId == myWalletId,
                    subStat:
                        'contributed \$${group.members[i].contributedUsd.toStringAsFixed(2)}',
                    trailingText:
                        '${(group.members[i].power * 100).toStringAsFixed(0)}%',
                    trailingColor: _powerColors[i % _powerColors.length],
                    avatarColor: avatarPaletteColor(i),
                    showBorder: i != group.members.length - 1 ||
                        group.pendingMembers.isNotEmpty,
                  ),
                // Accepted their invite, waiting on the group's
                // vote — not a real member yet (see `PendingGroupMember`).
                for (var i = 0; i < group.pendingMembers.length; i++)
                  GroupMemberRow(
                    name: group.pendingMembers[i].name,
                    isYou: false,
                    subStat: 'waiting for the group to vote',
                    trailingText: 'PENDING',
                    trailingColor: AppColors.amber,
                    avatarColor: AppColors.ink3,
                    showBorder: i != group.pendingMembers.length - 1,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (isPool) ...[
            AppButton(
                label: 'Contribute',
                variant: AppButtonVariant.green,
                onPressed: onContribute),
            const SizedBox(height: 9),
            AppButton(
              label: 'Request a withdrawal',
              variant: AppButtonVariant.outline,
              onPressed: group.openWithdrawalRequestId != null ||
                      group.potUsdCents <= 0
                  ? null
                  : onRequestWithdrawal,
            ),
          ] else
            AppButton(label: 'Send to everyone', onPressed: onBroadcast),
          const SizedBox(height: 9),
          AppButton(
              label: 'Manage members',
              variant: AppButtonVariant.outline,
              onPressed: onManageMembers),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  static String _powerSchemeLabel(String raw) {
    switch (raw) {
      case 'equal':
        return 'Equal';
      case 'contrib':
        return 'Contribution-based';
      default:
        if (raw.isEmpty) return 'Equal';
        return '${raw[0].toUpperCase()}${raw.substring(1)}';
    }
  }
}
