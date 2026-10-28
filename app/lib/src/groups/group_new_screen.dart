import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/contact.dart';
import '../models/group.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/avatar_palette.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/info_banner.dart';
import '../widgets/option_card.dart';
import '../widgets/screen_nav.dart';

/// "New group" — name, kind, voting power (pool only), and a member
/// picker sourced from Contacts. Matches
/// `designs/jammii-pay-prototype.html`'s `groupNew` screen.
class GroupNewScreen extends StatefulWidget {
  const GroupNewScreen(
      {super.key, required this.onBack, required this.onCreate});

  final VoidCallback onBack;
  final void Function(String name, GroupKind kind, GroupPowerScheme powerScheme,
      Set<String> memberContactIds) onCreate;

  @override
  State<GroupNewScreen> createState() => _GroupNewScreenState();
}

class _GroupNewScreenState extends State<GroupNewScreen> {
  final _nameController = TextEditingController();
  GroupKind _kind = GroupKind.pool;
  GroupPowerScheme _power = GroupPowerScheme.equal;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WalletStore>().loadContacts();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canCreate => _nameController.text.trim().length >= 3;

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<WalletStore>().contacts;

    return AppScreen(
      footer: AppButton(
        label: 'Create group',
        onPressed: _canCreate
            ? () => widget.onCreate(
                _nameController.text.trim(), _kind, _power, _selected)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'New group', onBack: widget.onBack),
          Text('Name', style: AppText.ui(size: 12, color: AppColors.ink3)),
          const SizedBox(height: 8),
          AppCard(
            variant: AppCardVariant.selected,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              maxLength: 30,
              style: AppText.ui(size: 15),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                counterText: '',
                hintText: 'e.g. Kakuma Traders Chama',
                hintStyle: AppText.ui(size: 15, color: AppColors.ink3),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('What is it for?',
              style: AppText.ui(size: 12, color: AppColors.ink3)),
          const SizedBox(height: 8),
          OptionCard(
            icon: Icons.savings_outlined,
            iconBackground: AppColors.green.withValues(alpha: 0.18),
            iconColor: AppColors.green,
            title: 'Contribution group',
            description:
                'Members pool money. Withdrawals need a majority vote.',
            selected: _kind == GroupKind.pool,
            onTap: () => setState(() => _kind = GroupKind.pool),
          ),
          const SizedBox(height: 9),
          OptionCard(
            icon: Icons.call_split,
            iconBackground: AppColors.blue.withValues(alpha: 0.2),
            iconColor: AppColors.blue,
            title: 'Broadcast group',
            description: 'Send one payment split across everyone at once.',
            selected: _kind == GroupKind.cast,
            onTap: () => setState(() => _kind = GroupKind.cast),
          ),
          if (_kind == GroupKind.pool) ...[
            const SizedBox(height: 16),
            Text('Voting power',
                style: AppText.ui(size: 12, color: AppColors.ink3)),
            const SizedBox(height: 8),
            OptionCard(
              icon: Icons.balance_outlined,
              iconBackground: AppColors.navy600,
              iconColor: AppColors.ink2,
              title: 'Equal',
              description: 'Everyone gets one equal vote',
              selected: _power == GroupPowerScheme.equal,
              onTap: () => setState(() => _power = GroupPowerScheme.equal),
            ),
            const SizedBox(height: 9),
            OptionCard(
              icon: Icons.trending_up,
              iconBackground: AppColors.navy600,
              iconColor: AppColors.ink2,
              title: 'By contribution',
              description: 'Power follows what each person put in',
              selected: _power == GroupPowerScheme.contrib,
              onTap: () => setState(() => _power = GroupPowerScheme.contrib),
            ),
          ],
          const SizedBox(height: 16),
          Text('Add members from contacts',
              style: AppText.ui(size: 12, color: AppColors.ink3)),
          const SizedBox(height: 8),
          if (contacts.isEmpty)
            Text(
              'No contacts yet. Add people first, or create the group and invite later.',
              style: AppText.ui(size: 12, color: AppColors.ink3),
            )
          else
            for (var i = 0; i < contacts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MemberPickCard(
                  contact: contacts[i],
                  colorIndex: i,
                  selected: _selected.contains(contacts[i].id),
                  onTap: () => setState(() {
                    if (!_selected.remove(contacts[i].id))
                      _selected.add(contacts[i].id);
                  }),
                ),
              ),
          const SizedBox(height: 12),
          const InfoBanner(
            icon: Icons.info_outline,
            text:
                'You (always included) plus the contacts you pick become founding members.',
          ),
        ],
      ),
    );
  }
}

class _MemberPickCard extends StatelessWidget {
  const _MemberPickCard(
      {required this.contact,
      required this.colorIndex,
      required this.selected,
      required this.onTap});

  final Contact contact;
  final int colorIndex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: selected ? AppCardVariant.selected : AppCardVariant.plain,
      onTap: onTap,
      padding: const EdgeInsets.all(10),
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
          Container(
            width: 19,
            height: 19,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.green : Colors.transparent,
              border: Border.all(
                  color: selected ? AppColors.green : AppColors.line2,
                  width: 1.5),
              shape: BoxShape.circle,
            ),
            child: selected
                ? Icon(Icons.check, size: 13, color: AppColors.onGreen)
                : null,
          ),
        ],
      ),
    );
  }
}
