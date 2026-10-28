import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/conversation.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/avatar_palette.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/screen_nav.dart';
import '../widgets/skeleton.dart';

/// The inbox — every conversation this wallet is party to, split into
/// **Contacts** (people already saved, plus every group) and **Spam**
/// (a direct message from someone who isn't in Contacts yet). Without
/// this split, a message from a stranger was previously invisible
/// entirely — the only way to reach `ChatScreen` was by tapping an
/// already-saved contact, so an incoming message from anyone else had
/// nowhere to surface. From Spam, "Add to contacts" promotes them; you
/// can also just keep replying from there without ever adding them.
class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({
    super.key,
    required this.onBack,
    required this.fetchConversations,
    required this.onOpenDirect,
    required this.onOpenGroup,
    required this.onAddToContacts,
  });

  final VoidCallback onBack;
  final Future<List<Conversation>> Function() fetchConversations;
  final void Function(Conversation) onOpenDirect;
  final void Function(Conversation) onOpenGroup;
  final Future<void> Function(Conversation) onAddToContacts;

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  List<Conversation>? _conversations;
  bool _spamTab = false;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    // Live dots while the inbox is open: a message landing in another
    // thread (or the 6s store poll firing first) must surface here
    // without backing out and re-entering.
    _refresh = Timer.periodic(
        const Duration(seconds: 5), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final conversations = await widget.fetchConversations();
      if (!mounted) return;
      // Silent tick: only rebuild when the thread list actually moved,
      // so the list doesn't jump under a reading user every 5s.
      // (Live dots still update: the build watches WalletStore, whose
      // 6s poll refreshes `conversations` + read marks independently.)
      if (!silent || !_sameThreads(_conversations, conversations)) {
        setState(() => _conversations = conversations);
      }
    } catch (_) {
      // Transient (offline blip) — keep the last good list rather than
      // blanking the inbox into a spinner; the next tick retries.
    }
  }

  bool _sameThreads(
      List<Conversation>? a, List<Conversation> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].lastMessageAt != b[i].lastMessageAt) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final all = _conversations;
    final store = context.watch<WalletStore>();
    final contactsAndGroups = (all ?? const [])
        .where((c) => c.kind == ConversationKind.group || c.isContact == true)
        .toList();
    final spam = (all ?? const [])
        .where((c) => c.kind == ConversationKind.direct && c.isContact == false)
        .toList();
    final shown = _spamTab ? spam : contactsAndGroups;
    final shownUnread =
        shown.where((c) => store.isUnread(c)).length;

    return AppScreen(
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Messages', onBack: widget.onBack),
          Row(
            children: [
              _TabChip(
                  label: 'Chats',
                  count: contactsAndGroups.length,
                  selected: !_spamTab,
                  onTap: () => setState(() => _spamTab = false)),
              const SizedBox(width: 8),
              _TabChip(
                  label: 'Spam',
                  count: spam.length,
                  selected: _spamTab,
                  onTap: () => setState(() => _spamTab = true)),
              const Spacer(),
              if (shownUnread > 0)
                Text('$shownUnread new',
                    style: AppText.ui(
                        size: 12,
                        weight: FontWeight.w700,
                        color: AppColors.green)),
            ],
          ),
          const SizedBox(height: 14),
          if (all == null)
            const Expanded(child: SkeletonCard(lines: 3))
          else if (shown.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _spamTab
                      ? 'Nothing from strangers right now.'
                      : 'No conversations yet.',
                  style: AppText.ui(size: 13, color: AppColors.ink3),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: shown.length,
                separatorBuilder: (_, __) => const SizedBox(height: 9),
                itemBuilder: (context, i) => _ConversationRow(
                  conversation: shown[i],
                  colorIndex: i,
                  unread: store.isUnread(shown[i]),
                  showAddToContacts: _spamTab,
                  onTap: () => shown[i].kind == ConversationKind.group
                      ? widget.onOpenGroup(shown[i])
                      : widget.onOpenDirect(shown[i]),
                  onAddToContacts: () async {
                    await widget.onAddToContacts(shown[i]);
                    _load();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip(
      {required this.label,
      required this.count,
      required this.selected,
      required this.onTap});
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.blue.withValues(alpha: 0.102)
              : Colors.transparent,
          border:
              Border.all(color: selected ? AppColors.blue : AppColors.line2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          count > 0 ? '$label ($count)' : label,
          style: AppText.ui(
              size: 12.5,
              weight: FontWeight.w700,
              color: selected ? AppColors.blue : AppColors.ink3),
        ),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.conversation,
    required this.colorIndex,
    required this.unread,
    required this.showAddToContacts,
    required this.onTap,
    required this.onAddToContacts,
  });

  final Conversation conversation;
  final int colorIndex;
  final bool unread;
  final bool showAddToContacts;
  final VoidCallback onTap;
  final VoidCallback onAddToContacts;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          AvatarCircle(
              name: conversation.name,
              color: avatarPaletteColor(colorIndex),
              size: 40),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (unread)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                            color: AppColors.green,
                            shape: BoxShape.circle),
                      ),
                    Expanded(
                        child: Text(conversation.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.ui(
                                size: 13.5,
                                weight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w700))),
                    if (conversation.kind == ConversationKind.group)
                      Icon(Icons.groups_outlined,
                          size: 13, color: AppColors.ink3),
                    const SizedBox(width: 6),
                    Text(_relativeTime(conversation.lastMessageAt),
                        style: AppText.mono(
                            size: 10, color: AppColors.ink3)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(conversation.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.ui(
                        size: 12,
                        weight:
                            unread ? FontWeight.w600 : FontWeight.w400,
                        color: unread
                            ? AppColors.ink
                            : AppColors.ink3)),
              ],
            ),
          ),
          if (showAddToContacts)
            TextButton(
              onPressed: onAddToContacts,
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.green, padding: EdgeInsets.zero),
              child: const Text('Add'),
            ),
        ],
      ),
    );
  }
}

String _relativeTime(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${at.day}/${at.month}';
}
