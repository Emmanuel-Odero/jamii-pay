import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/message.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/screen_nav.dart';
import '../widgets/skeleton.dart';

const int kChatMessageMaxLength = 66;

/// Real-time-*enough* chat, capped at [kChatMessageMaxLength] characters —
/// this is a payments app, not a social app, so messages are for a quick
/// nudge ("sent, check please"), never a conversation. No websocket yet:
/// polls [fetchMessages] every few seconds while this screen is open,
/// which is "live enough" for that job without standing up a new
/// transport (see `crates/server/src/routes/messages.rs`'s doc comment).
///
/// Reused for both group chat and direct (contact) chat — the caller
/// supplies [fetchMessages]/[sendMessage] bound to whichever conversation.
///
/// Gestures match the brief: swipe a bubble right to reply (WhatsApp's
/// own gesture); swipe left to reveal Set reminder / Add to calendar /
/// Pin. "Set reminder" and "Add to calendar" have no backend yet, so they
/// surface an honest "coming soon" notice rather than a fake success
/// toast — a confirmation the user can't tell apart from a real one is
/// worse than admitting the feature isn't built. "Pin" is real, persisted
/// server-side.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.title,
    required this.myWalletId,
    required this.fetchMessages,
    required this.sendMessage,
    required this.setPinned,
    required this.onBack,
  });

  final String title;
  final String myWalletId;
  final Future<List<ChatMessage>> Function() fetchMessages;
  final Future<ChatMessage> Function(String body, String? replyToId)
      sendMessage;
  final Future<void> Function(String messageId, bool pinned) setPinned;
  final VoidCallback onBack;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  ChatMessage? _replyTo;
  bool _loading = true;
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // Not a websocket — see the class doc comment. 3s is fast enough for
    // a quick nudge without hammering the server.
    _poll =
        Timer.periodic(const Duration(seconds: 3), (_) => _load(silent: true));
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final messages = await widget.fetchMessages();
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || body.length > kChatMessageMaxLength || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.sendMessage(body, _replyTo?.id);
      if (!mounted) return;
      _controller.clear();
      setState(() => _replyTo = null);
      await _load();
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    } catch (_) {
      // The draft is kept (cleared only on success above) — offer an
      // inline retry so an offline blip doesn't eat the message or force
      // retyping. This is the offline outbox, minimal form.
      if (!mounted) return;
      AppSnackBar.show(context,
          message: 'Could not send — your text is kept below.',
          tone: SnackTone.danger,
          actionLabel: 'Retry',
          onAction: _send);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showActions(ChatMessage message) async {
    // Every action here is real: the old "Set reminder / Add to calendar"
    // entries only ever toasted "coming soon" — dead options above a real
    // Pin trained users that this sheet lies. Reply duplicates the
    // swipe-right gesture for anyone who never discovers it.
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.navy800,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionTile(
                icon: Icons.reply,
                label: 'Reply',
                onTap: () => Navigator.of(context).pop('reply')),
            _ActionTile(
              icon: message.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              label: message.pinned ? 'Unpin' : 'Pin',
              onTap: () => Navigator.of(context).pop('pin'),
            ),
            _ActionTile(
                icon: Icons.copy_rounded,
                label: 'Copy text',
                onTap: () => Navigator.of(context).pop('copy')),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'reply':
        setState(() => _replyTo = message);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body));
        if (!mounted) return;
        AppSnackBar.show(context, message: 'Copied to clipboard.');
      case 'pin':
        try {
          await widget.setPinned(message.id, !message.pinned);
          await _load();
        } catch (_) {
          if (!mounted) return;
          AppSnackBar.showMoneyError(context, 'Could not update pin');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinned = _messages.where((m) => m.pinned).toList();
    final remaining = kChatMessageMaxLength - _controller.text.length;

    return Scaffold(
      backgroundColor: AppColors.navy900,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: ScreenNav(title: widget.title, onBack: widget.onBack),
            ),
            if (pinned.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.09),
                    border: Border.all(
                        color: AppColors.amber.withValues(alpha: 0.302)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.push_pin, size: 14, color: AppColors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pinned.length > 1
                              ? '${pinned.length} pinned · ${pinned.last.body}'
                              : pinned.last.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.ui(size: 12, color: AppColors.ink2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Semantics(
                        button: true,
                        label: 'Unpin latest message',
                        child: InkWell(
                          onTap: () async {
                            try {
                              await widget.setPinned(
                                  pinned.last.id, false);
                              await _load();
                            } catch (_) {
                              if (!mounted) return;
                              AppSnackBar.showMoneyError(
                                  context, 'Could not unpin');
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(Icons.close,
                                size: 14, color: AppColors.ink3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const SkeletonCard(lines: 3)
                  : _messages.isEmpty
                      ? Center(
                          child: Text(
                            'No messages yet.\nSay something in $kChatMessageMaxLength characters or less.',
                            textAlign: TextAlign.center,
                            style: AppText.ui(
                                size: 13, color: AppColors.ink3, height: 1.5),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final message = _messages[_messages.length - 1 - i];
                            final mine =
                                message.senderWalletId == widget.myWalletId;
                            // Day boundary: the list is reversed (newest at
                            // the bottom), so the divider renders after the
                            // bubble — visually above the day's first message.
                            final older = i + 1 < _messages.length
                                ? _messages[_messages.length - 2 - i]
                                : null;
                            final newDay = older == null ||
                                !_sameDay(message.createdAt,
                                    older.createdAt);
                            return Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                _SwipeableBubble(
                                  message: message,
                                  mine: mine,
                                  onSwipeRight: () => setState(
                                      () => _replyTo = message),
                                  onSwipeLeft: () =>
                                      _showActions(message),
                                  // Discoverability: swipe gestures are
                                  // invisible — long-press opens the same
                                  // sheet (Reply / Pin / Copy) explicitly.
                                  onLongPress: () =>
                                      _showActions(message),
                                ),
                                if (newDay)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.navy800,
                                          borderRadius:
                                              BorderRadius.circular(99),
                                        ),
                                        child: Text(
                                          _dayLabel(message.createdAt),
                                          style: AppText.mono(
                                              size: 10,
                                              color: AppColors.ink3),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
            ),
            if (_replyTo != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.navy800,
                    border: Border(
                        left: BorderSide(color: AppColors.blue, width: 3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Replying to ${_replyTo!.senderName}',
                                style: AppText.ui(
                                    size: 10.5,
                                    color: AppColors.blue,
                                    weight: FontWeight.w700)),
                            Text(_replyTo!.body,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.ui(
                                    size: 11.5, color: AppColors.ink3)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon:
                            Icon(Icons.close, size: 16, color: AppColors.ink3),
                        onPressed: () => setState(() => _replyTo = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.navy800,
                        border: Border.all(color: AppColors.line2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              maxLength: kChatMessageMaxLength,
                              maxLines: 3,
                              minLines: 1,
                              buildCounter: (_,
                                      {required currentLength,
                                      required isFocused,
                                      maxLength}) =>
                                  null,
                              style:
                                  AppText.ui(size: 13.5, color: AppColors.ink),
                              decoration: InputDecoration(
                                hintText: 'Message…',
                                hintStyle: AppText.ui(
                                    size: 13.5, color: AppColors.ink3),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          Text(
                            '$remaining',
                            style: AppText.mono(
                                size: 10,
                                color: remaining <= 10
                                    ? AppColors.amber
                                    : AppColors.ink3),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: 'Send message',
                    child: InkWell(
                      onTap: _sending || _controller.text.trim().isEmpty
                          ? null
                          : _send,
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _controller.text.trim().isEmpty
                              ? AppColors.navy700
                              : AppColors.green,
                          shape: BoxShape.circle,
                        ),
                        child: _sending
                            ? Icon(Icons.arrow_upward,
                                size: 20,
                                color: AppColors.onGreen
                                    .withValues(alpha: 0.45))
                            : Icon(Icons.arrow_upward,
                                size: 20, color: AppColors.onGreen),
                      ),
                    ),
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

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dayLabel(DateTime at) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${at.day}/${at.month}/${at.year}';
}

class _ActionTile extends StatelessWidget {  const _ActionTile(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppColors.ink2),
      title: Text(label, style: AppText.ui(size: 14, color: AppColors.ink)),
    );
  }
}

/// One bubble, draggable horizontally: drag right past [_replyThreshold]
/// triggers [onSwipeRight] (reply) on release; drag left past the same
/// threshold triggers [onSwipeLeft] (the actions sheet). The bubble
/// always springs back to rest — nothing stays "open", matching the
/// brief's "swipe to reply" / "swipe to see options" as one-shot
/// gestures rather than a persistent revealed panel.
class _SwipeableBubble extends StatefulWidget {
  const _SwipeableBubble(
      {required this.message,
      required this.mine,
      required this.onSwipeRight,
      required this.onSwipeLeft,
      required this.onLongPress});

  final ChatMessage message;
  final bool mine;
  final VoidCallback onSwipeRight;
  final VoidCallback onSwipeLeft;
  final VoidCallback onLongPress;

  @override
  State<_SwipeableBubble> createState() => _SwipeableBubbleState();
}

class _SwipeableBubbleState extends State<_SwipeableBubble>
    with SingleTickerProviderStateMixin {
  static const double _replyThreshold = 56;
  double _dx = 0;
  late final AnimationController _spring = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 180))
    ..addListener(() => setState(() {}));
  Animation<double>? _springAnim;

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _settleTo(double target) {
    _springAnim = Tween<double>(begin: _dx, end: target)
        .animate(CurvedAnimation(parent: _spring, curve: Curves.easeOut))
      ..addListener(() => setState(() => _dx = _springAnim!.value));
    _spring
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final revealingReply = _dx > 12;
    final revealingActions = _dx < -12;

    return GestureDetector(
      onLongPress: widget.onLongPress,
      onHorizontalDragUpdate: (details) =>
          setState(() => _dx = (_dx + details.delta.dx).clamp(-90.0, 90.0)),
      onHorizontalDragEnd: (_) {
        if (_dx > _replyThreshold) widget.onSwipeRight();
        if (_dx < -_replyThreshold) widget.onSwipeLeft();
        _settleTo(0);
      },
      child: Stack(
        children: [
          if (revealingReply)
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: Center(
                  child: Icon(Icons.reply,
                      size: 18,
                      color: AppColors.ink3.withValues(
                          alpha: (_dx / _replyThreshold).clamp(0, 1)))),
            ),
          if (revealingActions)
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              child: Center(
                  child: Icon(Icons.more_horiz,
                      size: 18,
                      color: AppColors.ink3.withValues(
                          alpha: (-_dx / _replyThreshold).clamp(0, 1)))),
            ),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: Align(
              alignment:
                  widget.mine ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: widget.mine
                        ? AppColors.green.withValues(alpha: 0.149)
                        : AppColors.navy800,
                    border: Border.all(
                        color: widget.mine
                            ? AppColors.green.withValues(alpha: 0.349)
                            : AppColors.line2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!widget.mine)
                        Text(message.senderName,
                            style: AppText.ui(
                                size: 10.5,
                                weight: FontWeight.w700,
                                color: AppColors.blue)),
                      if (message.replyToPreview != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 4, top: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.navy900.withValues(alpha: 0.4),
                            border: Border(
                                left: BorderSide(
                                    color: AppColors.ink3, width: 2)),
                          ),
                          child: Text(
                            message.replyToPreview!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                AppText.ui(size: 10.5, color: AppColors.ink3),
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                              child: Text(message.body,
                                  style: AppText.ui(
                                      size: 13.5, color: AppColors.ink))),
                          if (message.pinned) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.push_pin,
                                size: 10, color: AppColors.amber),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
