/// Mirrors `crates/server`'s `GroupResponse`/`MemberResponse` — see
/// `crates/server/src/routes/groups.rs`.
class GroupMember {
  const GroupMember({
    required this.id,
    required this.name,
    required this.walletId,
    required this.isOwner,
    required this.contributedUsdCents,
    required this.power,
  });

  final String id;
  final String name;
  final String? walletId;
  final bool isOwner;
  final int contributedUsdCents;

  /// Normalized voting-power share (0.0-1.0), already accounting for the
  /// group's `power_scheme` — this app never recomputes it client-side.
  final double power;

  double get contributedUsd => contributedUsdCents / 100;

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'] as String,
      name: json['name'] as String,
      walletId: json['wallet_id'] as String?,
      isOwner: json['is_owner'] as bool,
      contributedUsdCents: (json['contributed_usd_cents'] as num).toInt(),
      power: (json['power'] as num).toDouble(),
    );
  }
}

enum GroupKind { pool, cast }

enum GroupPowerScheme { equal, contrib, custom }

/// An accepted `add_member` invite still waiting on the group's vote —
/// see `crates/server/src/routes/groups.rs`'s `PendingMemberResponse`.
class PendingGroupMember {
  const PendingGroupMember({required this.requestId, required this.name});
  final String requestId;
  final String name;

  factory PendingGroupMember.fromJson(Map<String, dynamic> json) =>
      PendingGroupMember(
          requestId: json['request_id'] as String,
          name: json['name'] as String);
}

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.kind,
    required this.powerScheme,
    required this.potUsdCents,
    required this.fullHandle,
    required this.members,
    required this.openWithdrawalRequestId,
    required this.openProposalSummary,
    required this.pendingMembers,
  });

  final String id;
  final String name;
  final GroupKind kind;
  final GroupPowerScheme powerScheme;
  final int potUsdCents;
  final String fullHandle;
  final List<GroupMember> members;
  final String? openWithdrawalRequestId;

  /// One line describing the open vote, e.g. "Add Yusuf Omar" — null
  /// while an add-member proposal is still only a pending invite (not
  /// yet visible to the group — see `PendingGroupMember`).
  final String? openProposalSummary;
  final List<PendingGroupMember> pendingMembers;

  double get potUsd => potUsdCents / 100;

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: GroupKind.values.byName(json['kind'] as String),
      powerScheme:
          GroupPowerScheme.values.byName(json['power_scheme'] as String),
      potUsdCents: (json['pot_usd_cents'] as num).toInt(),
      fullHandle: json['full_handle'] as String,
      members: (json['members'] as List)
          .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
          .toList(),
      openWithdrawalRequestId: json['open_withdrawal_request_id'] as String?,
      openProposalSummary: json['open_proposal_summary'] as String?,
      pendingMembers: (json['pending_members'] as List)
          .map((e) => PendingGroupMember.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// An invite waiting on this wallet's response — see
/// `crates/server/src/routes/groups.rs`'s `PendingInviteResponse`.
class GroupInvite {
  const GroupInvite(
      {required this.requestId,
      required this.groupId,
      required this.groupName});
  final String requestId;
  final String groupId;
  final String groupName;

  factory GroupInvite.fromJson(Map<String, dynamic> json) => GroupInvite(
      requestId: json['request_id'] as String,
      groupId: json['group_id'] as String,
      groupName: json['group_name'] as String);
}

enum VoteChoice { approve, withhold, veto }

class GroupVote {
  const GroupVote(
      {required this.memberId,
      required this.memberName,
      required this.power,
      required this.choice});

  final String memberId;
  final String memberName;
  final double power;
  final VoteChoice? choice;

  factory GroupVote.fromJson(Map<String, dynamic> json) {
    return GroupVote(
      memberId: json['member_id'] as String,
      memberName: json['member_name'] as String,
      power: (json['power'] as num).toDouble(),
      choice: json['choice'] == null
          ? null
          : VoteChoice.values.byName(json['choice'] as String),
    );
  }
}

enum GroupProposalAction { withdrawal, addMember, removeMember }

/// Mirrors `WithdrawalResponse` — despite the name, this now backs any
/// group vote (a money withdrawal, or a member-management proposal — see
/// [action] and `crates/server/src/routes/groups.rs`'s doc comment on
/// `group_withdrawal_requests.action_type`). `amountUsdCents`/`payeeName`
/// are only populated when [action] is `withdrawal`; `targetMemberName`/
/// `newMemberName` only for the member-action cases.
class GroupWithdrawal {
  const GroupWithdrawal({
    required this.id,
    required this.action,
    required this.amountUsdCents,
    required this.payeeName,
    required this.targetMemberName,
    required this.newMemberName,
    required this.status,
    required this.approvePower,
    required this.withheldPower,
    required this.blockedByVeto,
    required this.passesMajority,
    required this.payoutUsdCents,
    required this.votes,
  });

  final String id;
  final GroupProposalAction action;
  final int? amountUsdCents;
  final String? payeeName;
  final String? targetMemberName;
  final String? newMemberName;
  final String status; // open | passed | blocked | executed | cancelled
  final double approvePower;
  final double withheldPower;
  final bool blockedByVeto;
  final bool passesMajority;
  final int payoutUsdCents;
  final List<GroupVote> votes;

  double get amountUsd => (amountUsdCents ?? 0) / 100;
  double get payoutUsd => payoutUsdCents / 100;
  double get notVotedPower => (1 -
          votes.fold<double>(
              0, (sum, v) => sum + (v.choice != null ? v.power : 0)))
      .clamp(0, 1);

  /// One line describing what's actually being voted on — used by
  /// `GroupVoteScreen` in place of the withdrawal-specific "Pay $X to Y"
  /// copy when this is a member-action proposal.
  String get summary => switch (action) {
        GroupProposalAction.withdrawal =>
          'Pay \$${amountUsd.toStringAsFixed(2)} to ${payeeName ?? ''}',
        GroupProposalAction.addMember =>
          'Add ${newMemberName ?? 'a new member'} to the group',
        GroupProposalAction.removeMember =>
          'Remove ${targetMemberName ?? 'a member'} from the group',
      };

  factory GroupWithdrawal.fromJson(Map<String, dynamic> json) {
    return GroupWithdrawal(
      id: json['id'] as String,
      action: switch (json['action_type'] as String) {
        'add_member' => GroupProposalAction.addMember,
        'remove_member' => GroupProposalAction.removeMember,
        _ => GroupProposalAction.withdrawal,
      },
      amountUsdCents: (json['amount_usd_cents'] as num?)?.toInt(),
      payeeName: json['payee_name'] as String?,
      targetMemberName: json['target_member_name'] as String?,
      newMemberName: json['new_member_name'] as String?,
      status: json['status'] as String,
      approvePower: (json['approve_power'] as num).toDouble(),
      withheldPower: (json['withheld_power'] as num).toDouble(),
      blockedByVeto: json['blocked_by_veto'] as bool,
      passesMajority: json['passes_majority'] as bool,
      payoutUsdCents: (json['payout_usd_cents'] as num).toInt(),
      votes: (json['votes'] as List)
          .map((e) => GroupVote.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
