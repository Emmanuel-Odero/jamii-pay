import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_card.dart';
import '../widgets/eternity_refresh.dart';
import '../widgets/handle_chip.dart';
import '../widgets/jamii_logo.dart';
import '../widgets/quick_action_grid.dart';
import '../widgets/tx_detail_sheet.dart';
import '../widgets/tx_row.dart';

/// Wallet tab — "Home". Two balances, not one: everyday money unlocks with
/// a PIN, savings needs guardians. Savings stays visible but visibly
/// locked, rather than hidden — hiding it would be a lie the user has to
/// maintain.
class WalletHomeScreen extends StatefulWidget {
  const WalletHomeScreen({
    super.key,
    required this.onReceive,
    required this.onSend,
    required this.onSavings,
    required this.onSearch,
    required this.onCashOut,
    required this.onComingSoon,
    required this.onPendingClaims,
    required this.onNotifications,
    required this.onScanPay,
  });

  final VoidCallback onReceive;
  final VoidCallback onSend;
  final VoidCallback onSavings;
  final VoidCallback onSearch;
  final VoidCallback onCashOut;
  final ValueChanged<String> onComingSoon;
  final VoidCallback onPendingClaims;
  final VoidCallback onNotifications;

  /// "Scan to pay" — the camera-based counterpart to typing a handle
  /// into Send. Lives in the header row next to Search/Notifications
  /// rather than as a fifth quick action, since the mockup's quick-action
  /// row is a fixed, sourced 4-up (Receive/Send/Cash out/Pay bill).
  final VoidCallback onScanPay;

  @override
  State<WalletHomeScreen> createState() => _WalletHomeScreenState();
}

class _WalletHomeScreenState extends State<WalletHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WalletStore>().loadHideSavingsSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WalletStore>();
    final wallet = store.wallet;
    if (wallet == null) {
      // Matches the branded loader used at bootstrap (`app_router.dart`)
      // and on the lock screen — a bare, unstyled spinner here would flash
      // a plain background at the one moment (first load) that should
      // feel most like a continuation of the app opening, not a break.
      return Container(
          color: AppColors.navy900,
          child: const Center(child: JamiiLogo(size: 64)));
    }
    final recent = store.transactions.take(3).toList();
    final showSavings = !store.hideSavingsEnabled || store.savingsRevealed;

    return EternityRefresh(
      onRefresh: () => store.refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mockup greets by a display name ("Habari, Amina") the
                      // app has no data source for — there's no separate
                      // name field, only the handle. Greeting by the handle
                      // base (capitalized) is real data, not a placeholder.
                      Text(
                        'Habari, ${_capitalize(wallet.handleBase)}',
                        style: AppText.ui(size: 12, color: AppColors.ink2),
                      ),
                      const SizedBox(height: 5),
                      HandleChip(
                          base: wallet.handleBase,
                          checkDigit: wallet.handleCheckDigit,
                          size: HandleChipSize.small),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Semantics(
                    button: true,
                    label: 'Search',
                    child: Material(
                      color: AppColors.navy600,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: widget.onSearch,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 33,
                          height: 33,
                          alignment: Alignment.center,
                          child: Icon(Icons.search,
                              size: 16, color: AppColors.ink),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Semantics(
                    button: true,
                    label: 'Scan to pay',
                    child: Material(
                      color: AppColors.navy600,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: widget.onScanPay,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 33,
                          height: 33,
                          alignment: Alignment.center,
                          child: Icon(Icons.qr_code_scanner,
                              size: 16, color: AppColors.ink),
                        ),
                      ),
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: store.bellBadgeCount > 0
                      ? 'Notifications, ${store.bellBadgeCount} new'
                      : 'Notifications',
                  child: Material(
                    color: AppColors.navy600,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: widget.onNotifications,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 33,
                        height: 33,
                        alignment: Alignment.center,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            Icon(Icons.notifications_none,
                                size: 17, color: AppColors.ink),
                            if (store.bellBadgeCount > 0)
                              Positioned(
                                top: -2,
                                right: -6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.coral,
                                    borderRadius:
                                        BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    store.bellBadgeCount > 99
                                        ? '99+'
                                        : '${store.bellBadgeCount}',
                                    style: AppText.mono(
                                        size: 9,
                                        weight: FontWeight.w700,
                                        color: Colors.white),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Connectivity, stated plainly: when the phone can't reach the
            // server (ATS block, wrong Wi-Fi, LAN permission off), every
            // balance is stale and no push/poll notification can arrive.
            // Without this banner that state looks identical to "no news".
            if (store.state == WalletLoadState.error)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  variant: AppCardVariant.coral,
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off_rounded,
                          size: 18, color: AppColors.coral),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Offline — balances may be stale',
                                style: AppText.ui(
                                    size: 13,
                                    weight: FontWeight.w700,
                                    color: AppColors.coral)),
                            Text(
                              'Check Wi-Fi, Settings → JamiiPay → Local Network, then pull to refresh.',
                              style: AppText.ui(
                                  size: 12, color: AppColors.ink2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            GestureDetector(
              // The reveal gesture — tap or long-press, per whichever the
              // user chose in `HideSavingsSetupScreen` — lives on this
              // card specifically (not the savings card itself), matching
              // the prototype's `#everydayCard` binding exactly.
              onTap:
                  store.hideSavingsEnabled && store.hideSavingsAction == 'tap'
                      ? store.bumpSavingsReveal
                      : null,
              onLongPress:
                  store.hideSavingsEnabled && store.hideSavingsAction == 'hold'
                      ? store.bumpSavingsReveal
                      : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.navy700, AppColors.navy800],
                  ),
                  border: Border.all(color: AppColors.line2),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.blue.withValues(alpha: 0.12),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOTAL BALANCE',
                        style: AppText.balanceLabel()),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: '\$',
                            style: AppText.balance(size: 24)),
                        TextSpan(
                            text: (wallet.everydayBalanceUsd +
                                    (showSavings
                                        ? wallet.savingsBalanceUsd
                                        : 0))
                                .toStringAsFixed(2),
                            style: AppText.balance(size: 44).copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            )),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '≈ KSh ${((wallet.everydayBalanceUsd + (showSavings ? wallet.savingsBalanceUsd : 0)) * (store.fxCache?.rate ?? 129.25)).toStringAsFixed(0)} · Everyday \$${wallet.everydayBalanceUsd.toStringAsFixed(2)}',
                      style: AppText.balanceAlt(),
                    ),
                  ],
                ),
              ),
            ),
            if (store.escrowClaims.isNotEmpty) ...[
              const SizedBox(height: 9),
              GestureDetector(
                onTap: widget.onPendingClaims,
                child: AppCard(
                  variant: AppCardVariant.amber,
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_top,
                          size: 18, color: AppColors.amber),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${store.escrowClaims.length} waiting to be claimed',
                              style: AppText.ui(
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: AppColors.amber),
                            ),
                            Text(
                              'Returns to you if not claimed in 72 hours',
                              style:
                                  AppText.ui(size: 12.5, color: AppColors.ink3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (showSavings) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: widget.onSavings,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.07),
                    border: Border.all(
                        color: AppColors.green.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline,
                          size: 20, color: AppColors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              store.savingsRevealed
                                  ? 'Savings · locked · visible briefly'
                                  : 'Savings · locked',
                              style: AppText.ui(
                                  size: 12.5,
                                  weight: FontWeight.w600,
                                  color: AppColors.green),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '\$${wallet.savingsBalanceUsd.toStringAsFixed(2)}',
                              style: AppText.display(size: 20),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 20, color: AppColors.ink3),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            QuickActionGrid(actions: [
              QuickAction(
                  icon: Icons.arrow_downward,
                  label: 'Receive',
                  tint: AppColors.green,
                  onTap: widget.onReceive),
              QuickAction(
                  icon: Icons.arrow_upward,
                  label: 'Send',
                  tint: AppColors.blue,
                  onTap: widget.onSend),
              QuickAction(
                  icon: Icons.sync_alt,
                  label: 'Cash out',
                  tint: AppColors.amber,
                  onTap: widget.onCashOut),
              QuickAction(
                  icon: Icons.receipt_long_outlined,
                  label: 'Pay bill',
                  badge: 'Soon',
                  tint: AppColors.ink3,
                  onTap: () => widget.onComingSoon('Pay bill')),
            ]),
            const SizedBox(height: 8),
            Text('Recent',
                style: AppText.ui(
                    size: 13,
                    weight: FontWeight.w600,
                    color: AppColors.ink3)),
            if (recent.isEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.06),
                  border: Border.all(
                      color: AppColors.green.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(18),
                ),
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
                            color: AppColors.green
                                .withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.waving_hand_rounded,
                              size: 22, color: AppColors.green),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text("You're ready 🎉",
                                  style: AppText.ui(
                                      size: 15,
                                      weight: FontWeight.w700)),
                              Text('Step 3 of 3: fund your wallet',
                                  style: AppText.ui(
                                      size: 12.5,
                                      color: AppColors.ink3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                        'Get your first payment to bring this screen to life.',
                        style: AppText.ui(
                            size: 13.5, color: AppColors.ink2)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: widget.onReceive,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(0, 52),
                              backgroundColor: AppColors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                            ),
                            child: const Text('Share my name',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: widget.onPendingClaims,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 52),
                              side:
                                  BorderSide(color: AppColors.line2),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                            ),
                            child: Text('Pending claims',
                                style: AppText.ui(
                                    size: 13,
                                    weight: FontWeight.w700,
                                    color: AppColors.ink)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else ...[
              for (final tx in recent)
                TxRow(
                    tx: tx,
                    showBorder: tx != recent.last,
                    onTap: () => TxDetailSheet.show(context, tx)),
              TextButton(
                onPressed: widget.onPendingClaims,
                child: Text('View all → Activity',
                    style: AppText.ui(
                        size: 13,
                        weight: FontWeight.w700,
                        color: AppColors.blue)),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
