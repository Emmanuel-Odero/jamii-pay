import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/money_math.dart';
import '../models/contact.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/avatar_palette.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/hold_to_confirm_button.dart';
import '../widgets/info_banner.dart';
import '../widgets/row_line.dart';
import '../widgets/screen_nav.dart';

/// Wallet → "Send money". Recipient and amount are real input, not a fixed
/// demo transaction — this used to always show "Yusuf Omar" / "$25.00" to
/// every user. Backed by the real `POST /wallets/:id/transfers` endpoint
/// (see `WalletStore.sendMoney`) — this used to always end in a "coming
/// soon" snackbar no matter what was typed. The confirm gesture is a real
/// hold, not a tap — the design's own rationale is that sends can't be
/// reversed, so a plain tap isn't enough friction.
class SendScreen extends StatefulWidget {
  const SendScreen(
      {super.key,
      required this.onBack,
      required this.onConfirm,
      this.onScanQr});

  final VoidCallback onBack;
  final void Function(String recipient, double amountUsd, ContactKind kind)
      onConfirm;

  /// Jumps to the camera-based "Scan to pay" flow instead of typing a
  /// handle in by hand — a separate flow (see `scan_pay_flow.dart`), not
  /// a shortcut into this screen's own fields, since scan-to-pay confirms
  /// with a PIN rather than this screen's hold gesture: a scan can hit
  /// someone you've never sent to before, which warrants the same
  /// friction as Cash-out, not the lighter one built for a known
  /// recipient you've already typed a handle for.
  final VoidCallback? onScanQr;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();

  static const _handleFeeUsd = 0.04;
  // Higher fee for send-to-non-user — matches the prototype's fee
  // transparency requirement exactly (registered: $0.04, unregistered:
  // $0.09), reflecting the extra cost of holding funds in escrow.
  static const _escrowFeeUsd = 0.09;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WalletStore>().loadContacts();
    });
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  double get _amount =>
      MoneyMath.parseAmount(_amountController.text) ?? 0;
  bool get _canSend =>
      _recipientController.text.trim().length >= 3 &&
      _amount > 0 &&
      !_overBalance;

  /// Send had no balance check at all — unlike the otherwise-equivalent
  /// Cash-out screen, which warns inline as soon as the typed amount
  /// exceeds what's available. Without this, the only feedback on
  /// over-spending was the confirm button silently staying disabled with
  /// no visible reason why.
  bool get _overBalance {
    final everydayUsd =
        context.read<WalletStore>().wallet?.everydayBalanceUsd ?? 0;
    return _amount > everydayUsd;
  }

  void _pickContact(Contact contact) {
    setState(() => _recipientController.text = contact.value);
  }

  ContactKind get _kind => detectContactKind(_recipientController.text);

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final feeUsd = kind == ContactKind.handle ? _handleFeeUsd : _escrowFeeUsd;
    final theyReceive = (_amount - feeUsd).clamp(0, double.infinity);
    final isEscrow = kind != ContactKind.handle;
    final everydayUsd =
        context.watch<WalletStore>().wallet?.everydayBalanceUsd ?? 0;

    return AppScreen(
      footer: HoldToConfirmButton(
        label: 'Hold to confirm',
        onConfirmed: _canSend
            ? () => widget.onConfirm(
                _recipientController.text.trim(), _amount, kind)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(
            title: 'Send money',
            onBack: widget.onBack,
            trailing: widget.onScanQr == null
                ? null
                : Semantics(
                    button: true,
                    label: 'Scan a QR code',
                    child: InkWell(
                      onTap: widget.onScanQr,
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.line2),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.qr_code_scanner,
                            color: AppColors.ink2, size: 15),
                      ),
                    ),
                  ),
          ),
          Text('To', style: AppText.ui(size: 12, color: AppColors.ink3)),
          const SizedBox(height: 8),
          AppCard(
            variant: AppCardVariant.selected,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _recipientController,
              onChanged: (_) => setState(() {}),
              style: AppText.mono(size: 15),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'their payment name',
                hintStyle: AppText.mono(size: 15, color: AppColors.ink3),
              ),
            ),
          ),
          Builder(builder: (context) {
            final onJamiiContacts = context
                .watch<WalletStore>()
                .contacts
                .where((c) => c.onJamii)
                .toList();
            if (onJamiiContacts.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 9),
                Text('Your contacts',
                    style: AppText.ui(size: 11, color: AppColors.ink3)),
                const SizedBox(height: 6),
                for (var i = 0; i < onJamiiContacts.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GestureDetector(
                      onTap: () => _pickContact(onJamiiContacts[i]),
                      child: Row(
                        children: [
                          AvatarCircle(
                              name: onJamiiContacts[i].name,
                              color: avatarPaletteColor(i),
                              size: 28),
                          const SizedBox(width: 9),
                          Text(onJamiiContacts[i].name,
                              style: AppText.ui(
                                  size: 12.5, weight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 9),
          if (isEscrow)
            InfoBanner(
              icon: Icons.hourglass_top,
              tone: BannerTone.warning,
              text: kind == ContactKind.email
                  ? 'Not on Jamii Pay yet. They will have 72 hours to claim it before it comes back to you.'
                  : "Not on Jamii Pay yet. We'll check by SMS — they'll have 72 hours to claim it before it comes back to you.",
            )
          else
            const InfoBanner(
              icon: Icons.warning_amber_rounded,
              tone: BannerTone.warning,
              text:
                  "Check this is the right person before you continue. Payments can't be reversed.",
            ),
          const SizedBox(height: 26),
          Center(
            child: Column(
              children: [
                Text('Amount',
                    style: AppText.ui(size: 12, color: AppColors.ink3)),
                const SizedBox(height: 6),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _amountController,
                    onChanged: (_) => setState(() {}),
                    textAlign: TextAlign.center,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: AppText.balance(size: 40),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      prefixText: '\$',
                      prefixStyle: AppText.balance(size: 25),
                      hintText: '0.00',
                      hintStyle:
                          AppText.balance(size: 40, color: AppColors.ink3),
                    ),
                  ),
                ),
                if (_overBalance) ...[
                  const SizedBox(height: 4),
                  Text(
                      'More than your ${MoneyMath.usd(everydayUsd)} balance. Lower the amount to continue.',
                      textAlign: TextAlign.center,
                      style: AppText.ui(size: 12, color: AppColors.coral)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              children: [
                RowLine(
                    label: 'Fee',
                    value: '\$${feeUsd.toStringAsFixed(2)}',
                    valueColor: AppColors.green),
                RowLine(
                    label: 'Total debited',
                    value: '\$${_amount.toStringAsFixed(2)}',
                    valueColor: AppColors.ink),
                RowLine(
                    label: 'They receive',
                    value: '\$${theyReceive.toStringAsFixed(2)}'),
                RowLine(
                  label: isEscrow ? 'Claim window' : 'Arrives',
                  value: isEscrow ? '72 hours' : '~15 seconds',
                  valueColor: AppColors.amber,
                  showBorder: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
