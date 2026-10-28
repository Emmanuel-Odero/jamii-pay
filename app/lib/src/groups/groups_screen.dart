import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/group.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_card.dart';
import '../widgets/eternity_refresh.dart';
import '../widgets/app_screen.dart';
import '../widgets/handle_chip.dart';
import '../widgets/motion.dart';

/// Groups tab — pooled savings (chamas) and broadcast-send groups.
/// Matches `designs/jammii-pay-prototype.html`'s `groups` screen.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen(
      {super.key, required this.onNewGroup, required this.onOpenGroup});

  final VoidCallback onNewGroup;
  final ValueChanged<Group> onOpenGroup;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WalletStore>().loadGroups();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WalletStore>();
    final groups = store.groups;
    final openVotes =
        groups.where((g) => g.openWithdrawalRequestId != null).length;

    return AppScreen(
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('Groups',
                      style: AppText.ui(
                          size: 16, weight: FontWeight.w700)),
                  if (openVotes > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:
                            AppColors.amber.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text('$openVotes vote${openVotes == 1 ? '' : 's'} open',
                          style: AppText.mono(
                              size: 10,
                              weight: FontWeight.w700,
                              color: AppColors.amber)),
                    ),
                  ],
                ],
              ),
              Semantics(
                button: true,
                label: 'Create new group',
                child: Pressable(
                  onTap: widget.onNewGroup,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.14),
                      border: Border.all(
                          color: AppColors.green
                              .withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add,
                            size: 18, color: AppColors.green),
                        const SizedBox(width: 4),
                        Text('New',
                            style: AppText.ui(
                                size: 13,
                                weight: FontWeight.w700,
                                color: AppColors.green)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: EternityRefresh(
              onRefresh: () =>
                  context.read<WalletStore>().loadGroups(),
              child: groups.isEmpty
                  ? ListView(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 48),
                          child: Column(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.green
                                      .withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                    Icons.groups_outlined,
                                    size: 32,
                                    color: AppColors.ink3),
                              ),
                              const SizedBox(height: 16),
                              Text('No groups yet',
                                  style: AppText.ui(
                                      size: 15,
                                      weight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              Text(
                                'Create one to send to many people at once, or pool money together as a chama.',
                                textAlign: TextAlign.center,
                                style: AppText.ui(
                                    size: 13.5,
                                    color: AppColors.ink3,
                                    height: 1.5),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 52,
                                child: ElevatedButton.icon(
                                  onPressed: widget.onNewGroup,
                                  icon: const Icon(Icons.add,
                                      size: 18),
                                  label: const Text(
                                      'Create group',
                                      style: TextStyle(
                                          fontWeight:
                                              FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        AppColors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(
                                                14)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      itemCount: groups.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, i) => _GroupCard(
                          group: groups[i],
                          onTap: () =>
                              widget.onOpenGroup(groups[i])),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});

  final Group group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPool = group.kind == GroupKind.pool;
    final voteOpen = group.openWithdrawalRequestId != null;
    final accent = voteOpen
        ? AppColors.amber
        : isPool
            ? AppColors.green
            : AppColors.blue;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  isPool ? Icons.savings_outlined : Icons.call_split,
                  size: 22,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.ui(
                            size: 14, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      isPool
                          ? '${group.members.length} members · \$${group.potUsd.toStringAsFixed(2)} pooled'
                          : '${group.members.length} members · broadcast',
                      style: AppText.ui(
                          size: 12.5, color: AppColors.ink3),
                    ),
                  ],
                ),
              ),
              if (voteOpen)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('VOTE OPEN',
                      style: AppText.mono(
                          size: 10,
                          weight: FontWeight.w700,
                          color: AppColors.amber)),
                )
              else
                Icon(Icons.chevron_right,
                    size: 20, color: AppColors.ink3),
            ],
          ),
          const SizedBox(height: 10),
          HandleChip(
            base: group.fullHandle.substring(0, group.fullHandle.length - 1),
            checkDigit: group.fullHandle.substring(group.fullHandle.length - 1),
            size: HandleChipSize.small,
          ),
        ],
      ),
    );
  }
}
