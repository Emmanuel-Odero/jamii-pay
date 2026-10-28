import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import '../widgets/row_line.dart';
import '../widgets/screen_nav.dart';

/// "Send to everyone" — per-member amount, insufficient-balance banner.
/// Matches `designs/jammii-pay-prototype.html`'s `broadcastSend` screen.
/// Only members with a real linked wallet can be selected — off-Jamii
/// cast members aren't reachable this way yet (no escrow integration for
/// group broadcasts).
class BroadcastSendScreen extends StatefulWidget {
  const BroadcastSendScreen(
      {super.key,
      required this.group,
      required this.onBack,
      required this.onSend});

  final Group group;
  final VoidCallback onBack;
  final void Function(int amountPerMemberUsdCents, List<String> memberWalletIds)
      onSend;

  @override
  State<BroadcastSendScreen> createState() => _BroadcastSendScreenState();
}

class _BroadcastSendScreenState extends State<BroadcastSendScreen> {
  final _amountController = TextEditingController(text: '10');
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    final myWalletId = context.read<WalletStore>().wallet?.id;
    // Excludes the *viewer*, not the group owner — those aren't the same
    // member when someone other than the creator opens this screen.
    _selected = widget.group.members
        .where((m) => m.walletId != myWalletId && m.walletId != null)
        .map((m) => m.id)
        .toSet();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _each => double.tryParse(_amountController.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    final myWalletId = context.watch<WalletStore>().wallet?.id;
    final everydayUsd =
        context.watch<WalletStore>().wallet?.everydayBalanceUsd ?? 0;
    final recipients = widget.group.members
        .where((m) =>
            m.walletId != myWalletId &&
            m.walletId != null &&
            _selected.contains(m.id))
        .toList();
    final total = _each * recipients.length;
    final overBalance = total > everydayUsd;

    return AppScreen(
      scrollable: false,
      footer: AppButton(
        label:
            'Send to ${recipients.length} people — \$${total.toStringAsFixed(2)}',
        onPressed: recipients.isEmpty || overBalance || _each <= 0
            ? null
            : () => widget.onSend((_each * 100).round(),
                recipients.map((m) => m.walletId!).toList()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Send to everyone', onBack: widget.onBack),
          Center(
            child: Column(
              children: [
                Text('Each gets',
                    style: AppText.ui(size: 12, color: AppColors.ink3)),
                const SizedBox(height: 6),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _amountController,
                    onChanged: (_) => setState(() {}),
                    textAlign: TextAlign.center,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: AppText.balance(size: 34),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      prefixText: '\$',
                      prefixStyle: AppText.balance(size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                for (final member in widget.group.members.where(
                    (m) => m.walletId != myWalletId && m.walletId != null))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      variant: _selected.contains(member.id)
                          ? AppCardVariant.selected
                          : AppCardVariant.plain,
                      onTap: () => setState(() {
                        if (!_selected.remove(member.id))
                          _selected.add(member.id);
                      }),
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          AvatarCircle(
                              name: member.name,
                              color: avatarPaletteColor(
                                  widget.group.members.indexOf(member)),
                              size: 32),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(member.name,
                                  style: AppText.ui(
                                      size: 13, weight: FontWeight.w600))),
                          if (_selected.contains(member.id))
                            Text('\$${_each.toStringAsFixed(2)}',
                                style: AppText.mono(
                                    size: 12, color: AppColors.green)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                AppCard(
                  child: Column(
                    children: [
                      RowLine(
                          label: 'Recipients', value: '${recipients.length}'),
                      RowLine(
                          label: 'Each gets',
                          value: '\$${_each.toStringAsFixed(2)}'),
                      RowLine(
                          label: 'Total',
                          value: '\$${total.toStringAsFixed(2)}',
                          valueColor: overBalance ? AppColors.coral : null),
                      RowLine(
                          label: 'Your balance',
                          value: '\$${everydayUsd.toStringAsFixed(2)}',
                          showBorder: false),
                    ],
                  ),
                ),
                if (overBalance) ...[
                  const SizedBox(height: 9),
                  const InfoBanner(
                      icon: Icons.error_outline,
                      tone: BannerTone.danger,
                      text: "That's more than your everyday balance."),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
