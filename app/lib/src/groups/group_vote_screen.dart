import 'package:flutter/material.dart';

import '../models/group.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/row_line.dart';
import '../widgets/screen_nav.dart';
import '../widgets/segmented_bar.dart';

/// Group withdrawal vote — 3-segment approve/withhold/veto bar, legend,
/// status card with the exact payout-math rows, and per-member vote
/// status. Matches `designs/jammii-pay-prototype.html`'s `groupVote`
/// screen. `myMemberId` is null when the viewer isn't a member with a
/// linked wallet on this device (shouldn't normally happen, but keeps
/// this screen safe to render either way).
class GroupVoteScreen extends StatelessWidget {
  const GroupVoteScreen({
    super.key,
    required this.withdrawal,
    required this.myMemberId,
    required this.onBack,
    required this.onVote,
    required this.onExecute,
  });

  final GroupWithdrawal withdrawal;
  final String? myMemberId;
  final ValueChanged<VoteChoice> onVote;
  final VoidCallback onBack;
  final VoidCallback onExecute;

  @override
  Widget build(BuildContext context) {
    final myVotes = withdrawal.votes.where((v) => v.memberId == myMemberId);
    final myVote = myVotes.isEmpty ? null : myVotes.first;
    final hasVoted = myVote?.choice != null;
    final canExecute = withdrawal.passesMajority &&
        !withdrawal.blockedByVeto &&
        withdrawal.status == 'open';
    // Real veto power — the old 0.0001 hack forced a visible coral sliver
    // even for a dust-size veto, which misread as meaningful opposition.
    final vetoPower = withdrawal.votes
        .where((v) => v.choice == VoteChoice.veto)
        .fold<double>(0, (s, v) => s + v.power);

    final (Color statusBorder, statusVariant) = withdrawal.blockedByVeto
        ? (AppColors.coral, AppCardVariant.plain)
        : withdrawal.passesMajority
            ? (AppColors.green, AppCardVariant.green)
            : (AppColors.amber, AppCardVariant.amber);

    final isWithdrawal = withdrawal.action == GroupProposalAction.withdrawal;

    return AppScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(
              title: isWithdrawal ? 'Withdrawal vote' : 'Group vote',
              onBack: onBack),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: isWithdrawal
                  ? [
                      Text('\$${withdrawal.amountUsd.toStringAsFixed(2)}',
                          style: AppText.display(size: 25)),
                      Text('to ${withdrawal.payeeName}',
                          style: AppText.ui(size: 12, color: AppColors.ink3)),
                    ]
                  : [
                      Text(withdrawal.summary,
                          style: AppText.screenTitle(size: 18))
                    ],
            ),
          ),
          const SizedBox(height: 14),
          SegmentedBar(
            segments: [
              (withdrawal.approvePower, AppColors.green),
              (withdrawal.withheldPower, AppColors.amber),
              (vetoPower, AppColors.coral),
            ],
            height: 10,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _Legend(
                  color: AppColors.green,
                  label:
                      '${(withdrawal.approvePower * 100).toStringAsFixed(0)}% approve'),
              _Legend(
                  color: AppColors.amber,
                  label:
                      '${(withdrawal.withheldPower * 100).toStringAsFixed(0)}% withheld'),
              _Legend(
                color: AppColors.coral,
                label:
                    '${(vetoPower * 100).toStringAsFixed(0)}% veto',
              ),
              _Legend(
                  color: AppColors.ink3,
                  label:
                      '${(withdrawal.notVotedPower * 100).toStringAsFixed(0)}% not voted'),
            ],
          ),
          const SizedBox(height: 14),
          AppCard(
            variant: statusVariant,
            child: Column(
              children: [
                RowLine(
                  label: 'Majority (over 50%)',
                  value: withdrawal.passesMajority
                      ? 'Reached'
                      : '${(withdrawal.approvePower * 100).toStringAsFixed(0)}% so far',
                  valueColor: withdrawal.passesMajority
                      ? AppColors.green
                      : AppColors.amber,
                  showBorder: isWithdrawal,
                ),
                if (isWithdrawal) ...[
                  RowLine(
                    label: 'Withheld shares',
                    value:
                        '−\$${(withdrawal.amountUsd - withdrawal.payoutUsd).toStringAsFixed(2)}',
                    valueColor: AppColors.amber,
                  ),
                  RowLine(
                    label: 'Would pay out',
                    value: withdrawal.blockedByVeto
                        ? 'Blocked by veto'
                        : '\$${withdrawal.payoutUsd.toStringAsFixed(2)}',
                    valueColor: withdrawal.blockedByVeto
                        ? AppColors.coral
                        : AppColors.green,
                    showBorder: false,
                  ),
                ] else if (withdrawal.blockedByVeto)
                  RowLine(
                      label: 'Outcome',
                      value: 'Blocked by veto',
                      valueColor: AppColors.coral,
                      showBorder: false),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < withdrawal.votes.length; i++)
                  RowLine(
                    label: withdrawal.votes[i].memberId == myMemberId
                        ? '${withdrawal.votes[i].memberName} (you)'
                        : withdrawal.votes[i].memberName,
                    value: switch (withdrawal.votes[i].choice) {
                      VoteChoice.approve => 'APPROVED',
                      VoteChoice.withhold => 'WITHHELD',
                      VoteChoice.veto => 'VETO',
                      null => 'WAITING',
                    },
                    valueColor: switch (withdrawal.votes[i].choice) {
                      VoteChoice.approve => AppColors.green,
                      VoteChoice.withhold => AppColors.amber,
                      VoteChoice.veto => AppColors.coral,
                      null => AppColors.ink3,
                    },
                    showBorder: i != withdrawal.votes.length - 1,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!hasVoted && myMemberId != null) ...[
            AppButton(
                label: 'Approve',
                variant: AppButtonVariant.green,
                onPressed: () => onVote(VoteChoice.approve)),
            const SizedBox(height: 8),
            AppButton(
                label: 'Withhold my share only',
                variant: AppButtonVariant.outline,
                onPressed: () => onVote(VoteChoice.withhold)),
            const SizedBox(height: 8),
            AppButton(
                label: 'Reject the whole thing',
                variant: AppButtonVariant.danger,
                onPressed: () => onVote(VoteChoice.veto)),
          ] else if (canExecute)
            AppButton(
              label: isWithdrawal ? 'Execute payout' : 'Apply change',
              variant: AppButtonVariant.green,
              onPressed: onExecute,
            )
          else
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                      myMemberId == null
                          ? Icons.visibility_outlined
                          : withdrawal.blockedByVeto
                              ? Icons.block_outlined
                              : Icons.hourglass_top,
                      size: 18,
                      color: AppColors.ink2),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      myMemberId == null
                          ? 'You\'re viewing this vote — only group members can vote or execute.'
                          : withdrawal.blockedByVeto
                              ? 'Blocked by veto — this proposal cannot pass. Your vote is recorded above.'
                              : hasVoted
                                  ? 'Your vote is in — waiting for the rest of the group. You\'ll be notified of the outcome.'
                                  : 'Waiting for a majority with no veto — nothing needs you right now.',
                      style: AppText.ui(
                          size: 13,
                          color: AppColors.ink2,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: AppText.mono(size: 11, color: AppColors.ink2)),
      ],
    );
  }
}
