import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/contact.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/avatar_palette.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/eternity_refresh.dart';
import '../widgets/app_screen.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/handle_chip.dart';
import '../widgets/motion.dart';

/// Contacts tab — address book, matching
/// `designs/jammii-pay-prototype.html`'s `contacts` screen. Replaces the
/// old "Cards" placeholder tab, which had no design source or backend at
/// all; Contacts has both.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen(
      {super.key,
      required this.onAddContact,
      required this.onOpenChat,
      required this.onOpenInbox});

  final VoidCallback onAddContact;

  /// Only called for on-Jamii contacts — chat needs a real wallet on the
  /// other end (see `ChatScreen`'s doc comment).
  final ValueChanged<Contact> onOpenChat;

  /// Opens `ChatInboxScreen` — every conversation, including messages
  /// from people not in Contacts (the "Spam" tab).
  final VoidCallback onOpenInbox;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WalletStore>().loadContacts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WalletStore>();
    final q = _query.trim().toLowerCase();
    final contacts = q.isEmpty
        ? store.contacts
        : store.contacts
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.value.toLowerCase().contains(q))
            .toList();

    return AppScreen(
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Contacts',
                  style: AppText.ui(size: 16, weight: FontWeight.w700)),
              Row(
                children: [
                  _HeaderButton(
                    label: store.unreadChatCount > 0
                        ? 'Messages, ${store.unreadChatCount} unread'
                        : 'Messages',
                    icon: Icons.forum_outlined,
                    badgeCount: store.unreadChatCount,
                    onTap: widget.onOpenInbox,
                  ),
                  const SizedBox(width: 8),
                  _HeaderButton(
                    label: 'Add contact',
                    icon: Icons.person_add_outlined,
                    primary: true,
                    onTap: widget.onAddContact,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppCard(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              style: AppText.ui(size: 14),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'Search name or payment name…',
                hintStyle:
                    AppText.ui(size: 14, color: AppColors.ink3),
                icon: Icon(Icons.search,
                    size: 18, color: AppColors.ink3),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close,
                            size: 16, color: AppColors.ink3),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: EternityRefresh(
              onRefresh: () => store.loadContacts(),
              child: contacts.isEmpty
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
                                  color: AppColors.blue
                                      .withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                    Icons.people_outline,
                                    size: 32,
                                    color: AppColors.ink3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                q.isEmpty
                                    ? 'No contacts yet'
                                    : 'No match for "$_query"',
                                style: AppText.ui(
                                    size: 15,
                                    weight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                q.isEmpty
                                    ? 'Add the people you pay most — chatting and sending get one tap faster.'
                                    : 'Try a different spelling.',
                                textAlign: TextAlign.center,
                                style: AppText.ui(
                                    size: 13.5,
                                    color: AppColors.ink3),
                              ),
                              if (q.isEmpty) ...[
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 52,
                                  child: ElevatedButton.icon(
                                    onPressed: widget.onAddContact,
                                    icon: const Icon(Icons.add,
                                        size: 18),
                                    label: const Text('Add contact',
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
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      itemCount: contacts.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _ContactCard(
                        contact: contacts[i],
                        colorIndex: i,
                        onTap: contacts[i].onJamii
                            ? () =>
                                widget.onOpenChat(contacts[i])
                            : () => showInviteSheet(
                                context, contacts[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton(
      {required this.label,
      required this.icon,
      this.badgeCount = 0,
      this.primary = false,
      required this.onTap});

  final String label;
  final IconData icon;
  final int badgeCount;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: primary
                ? AppColors.green.withValues(alpha: 0.14)
                : AppColors.navy800,
            border: Border.all(
                color: primary
                    ? AppColors.green.withValues(alpha: 0.4)
                    : AppColors.line2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon,
                      size: 18,
                      color: primary
                          ? AppColors.green
                          : AppColors.ink2),
                  if (badgeCount > 0)
                    Positioned(
                      top: -6,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.coral,
                          borderRadius:
                              BorderRadius.circular(99),
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: AppText.mono(
                              size: 9,
                              weight: FontWeight.w700,
                              color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 6),
              Text(
                  primary
                      ? 'Add'
                      : (badgeCount > 0
                          ? 'Messages ($badgeCount)'
                          : 'Messages'),
                  style: AppText.ui(
                      size: 13,
                      weight: FontWeight.w700,
                      color: primary
                          ? AppColors.green
                          : AppColors.ink2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard(
      {required this.contact, required this.colorIndex, this.onTap});

  final Contact contact;
  final int colorIndex;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final value = contact.value;
    final hasCheckDigit =
        contact.kind == ContactKind.handle && value.length >= 2;
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          AvatarCircle(
              name: contact.name,
              color: avatarPaletteColor(colorIndex),
              size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.ui(
                        size: 14, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (hasCheckDigit)
                  HandleChip(
                    base: value.substring(0, value.length - 1),
                    checkDigit:
                        value.substring(value.length - 1),
                    size: HandleChipSize.small,
                  )
                else
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.mono(
                          size: 12, color: AppColors.ink3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (contact.onJamii)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.green
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('ON JAMII',
                      style: AppText.mono(
                          size: 10,
                          weight: FontWeight.w700,
                          color: AppColors.green)),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right,
                    size: 20, color: AppColors.ink3),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color:
                    AppColors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mail_outline,
                      size: 14, color: AppColors.amber),
                  const SizedBox(width: 4),
                  Text('Invite',
                      style: AppText.ui(
                          size: 12,
                          weight: FontWeight.w700,
                          color: AppColors.amber)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Off-Jamii contacts used to be dead cards — the whole row did nothing.
/// Now tapping opens a real invite: share JamiiPay with them (and anything
/// you send in the meantime waits 72h in escrow for them to claim).
Future<void> showInviteSheet(
    BuildContext context, Contact contact) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.navy800,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.line2,
                      borderRadius: BorderRadius.circular(99))),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                AvatarCircle(
                    name: contact.name,
                    color: AppColors.amber,
                    size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(contact.name,
                          style: AppText.ui(
                              size: 16,
                              weight: FontWeight.w700)),
                      Text(contact.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.mono(
                              size: 12,
                              color: AppColors.ink3)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${contact.name} isn\'t on JamiiPay yet. Invite them — and anything you send in the meantime waits 72 hours in escrow for them to claim.',
              style: AppText.ui(
                  size: 13.5,
                  color: AppColors.ink2,
                  height: 1.5),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Share.share(
                    'Join me on JamiiPay — send and receive money instantly with just a payment name. https://jamiipay.com',
                    subject: 'Join me on JamiiPay',
                  );
                },
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Share invite',
                    style:
                        TextStyle(fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
