import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../chat/chat_inbox_screen.dart';
import '../chat/chat_screen.dart';
import '../contacts/contact_new_screen.dart';
import '../contacts/contacts_screen.dart';
import '../data/api_client.dart';
import '../data/money_math.dart';
import '../data/session_storage.dart';
import '../groups/group_flow.dart';
import '../models/contact.dart';
import '../notifications/push_service.dart';
import '../onboarding/language_screen.dart';
import '../recovery/recovery_flow.dart';
import '../search/search_flow.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/motion.dart';
import '../widgets/review_sheet.dart';
import '../widgets/row_line.dart';
import '../widgets/success_sheet.dart';
import 'activity_screen.dart';
import 'card_topup_flow.dart';
import 'cash_out_flow.dart';
import 'alert_settings_screen.dart';
import 'hide_savings_setup_screen.dart';
import 'home_screen.dart';
import 'mpesa_receive_flow.dart';
import 'notifications_screen.dart';
import 'pending_claims_screen.dart';
import 'receive_screen.dart';
import 'savings_screen.dart';
import 'savings_transfer_flow.dart';
import 'scan_pay_flow.dart';
import 'send_screen.dart';
import 'settings_screen.dart';
import 'wallet_shell.dart';
import '../theme/theme_screen.dart';

/// The wallet tab shell: bottom nav across Wallet / Activity / Settings.
/// Cards stays an honest placeholder — there's no card-issuance feature
/// anywhere in the backend (no endpoints, no schema for it), so there's
/// nothing real to wire up yet. Receive/Send/Savings are pushed on top as
/// full-screen flows, matching how the mockup presents them.
class WalletFlow extends StatefulWidget {
  const WalletFlow({super.key});

  @override
  State<WalletFlow> createState() => _WalletFlowState();
}

class _WalletFlowState extends State<WalletFlow> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Remote-push wiring: taps open the Notifications feed; every launch
    // (re)registers the APNs token for this wallet. Best-effort throughout.
    PushService.bindTapHandler(() async {
      if (!mounted) return;
      _pushNotifications();
    });
    final store = context.read<WalletStore>();
    PushService.syncWallet(store.wallet?.id, JamiiPayApiClient());
    PushService.drainLaunchType().then((type) {
      if (!mounted || type == null) return;
      _pushNotifications();
    });
  }

  void _pushReceive() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => ReceiveScreen(
        onBack: () => Navigator.of(context).pop(),
        onRequestStkPush: () => pushMpesaReceiveFlow(context),
        onTopUpWithCard: () => pushCardTopupFlow(context),
      ),
    ));
  }

  void _pushSend() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => SendScreen(
        onBack: () => Navigator.of(context).pop(),
        onConfirm: (recipient, amountUsd, kind) => kind == ContactKind.handle
            ? _sendMoney(context, recipient, amountUsd)
            : _sendToUnregistered(context, recipient, amountUsd, kind),
        onScanQr: () => pushScanPayFlow(context),
      ),
    ));
  }

  Future<void> _sendMoney(
      BuildContext context, String recipient, double amountUsd) async {
    final store = context.read<WalletStore>();
    // Backend semantics (routes/wallets.rs): sender debited amount+fee,
    // recipient credited amount. Review freezes FX + idempotency key per
    // confirmation so retry never double-sends.
    final fx = await store.getFxRate();
    final fee = fx.handleFeeUsdCents / 100;
    final idempotencyKey = newIdempotencyKey();
    final clean = recipient.trim().toLowerCase();
    final hasCheckDigit = clean.length >= 4;
    if (!context.mounted) return;
    final confirmed = await MoneyReviewSheet.show(
      context: context,
      title: 'Review send',
      quote: MoneyQuote(
        amountUsd: amountUsd,
        feeUsd: fee,
        totalDebitUsd: amountUsd + fee,
        theyReceiveUsd: amountUsd,
        rateKesPerUsd: fx.rate,
        rateUpdatedAt: fx.updatedAt,
        arrivalLabel: '~15 seconds',
      ),
      recipientBase: hasCheckDigit
          ? clean.substring(0, clean.length - 1)
          : null,
      recipientCheckDigit:
          hasCheckDigit ? clean.substring(clean.length - 1) : null,
      recipientFallback: hasCheckDigit ? null : clean,
      extraRows: [
        RowLine(
          label: 'Rate',
          value:
              '${fx.rate.toStringAsFixed(2)} KES/\$ · ${MoneyQuote(amountUsd: 0, feeUsd: 0, totalDebitUsd: 0, theyReceiveUsd: 0, rateKesPerUsd: fx.rate, rateUpdatedAt: fx.updatedAt, arrivalLabel: '').rateAgeLabel}',
          showBorder: false,
        ),
      ],
      confirmLabel: 'Confirm send',
    );
    if (!confirmed || !context.mounted) return;
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const LoadingVeil(message: 'Sending…'));
    try {
      await store.sendMoney(
          recipientFullHandle: clean,
          amountUsdCents: (amountUsd * 100).round(),
          idempotencyKey: idempotencyKey);
      if (!context.mounted) return;
      Navigator.of(context).pop(); // dismiss veil
      Navigator.of(context).pop(); // dismiss Send screen, back to Home
      await SuccessSheet.show(
        context,
        amountUsd: amountUsd,
        recipientLabel: clean,
        base: hasCheckDigit ? clean.substring(0, clean.length - 1) : null,
        checkDigit:
            hasCheckDigit ? clean.substring(clean.length - 1) : null,
        onShare: () => AppSnackBar.show(context,
            message: 'Receipt link copied — share it anywhere.',
            actionLabel: 'OK',
            onAction: () {}),
        onDone: () {},
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // dismiss veil, stay on Send screen
      Haptics.error();
      AppSnackBar.show(context, message: e.message, tone: SnackTone.danger);
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      AppSnackBar.showMoneyError(context, 'Could not send');
    }
  }

  /// Send-to-non-user — the recipient has no Jamii Pay wallet, so this
  /// holds the money in escrow (see `WalletStore.createEscrow`) instead
  /// of an instant transfer. Lands on Pending Claims rather than Home so
  /// the sender immediately sees the 72h countdown they were just warned
  /// about.
  Future<void> _sendToUnregistered(BuildContext context, String recipientAddr,
      double amountUsd, ContactKind kind) async {
    final store = context.read<WalletStore>();
    final fx = await store.getFxRate();
    final fee = fx.escrowFeeUsdCents / 100;
    if (!context.mounted) return;
    final confirmed = await MoneyReviewSheet.show(
      context: context,
      title: 'Review escrow',
      quote: MoneyQuote(
        amountUsd: amountUsd,
        feeUsd: fee,
        totalDebitUsd: amountUsd + fee,
        theyReceiveUsd: amountUsd,
        rateKesPerUsd: fx.rate,
        rateUpdatedAt: fx.updatedAt,
        arrivalLabel: '72 hours to claim',
      ),
      recipientFallback: recipientAddr,
      confirmLabel: 'Hold in escrow',
    );
    if (!confirmed || !context.mounted) return;
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const LoadingVeil(message: 'Holding in escrow…'));
    try {
      await store.createEscrow(
        recipientAddr: recipientAddr,
        recipientKind: kind.name,
        amountUsdCents: (amountUsd * 100).round(),
      );
      if (!context.mounted) return;
      Navigator.of(context).pop(); // dismiss veil
      Navigator.of(context).pop(); // dismiss Send screen, back to Home
      AppSnackBar.show(context,
          message:
              'Held \$${amountUsd.toStringAsFixed(2)} for $recipientAddr — they have 72 hours to claim it.',
          actionLabel: 'View',
          onAction: _pushPendingClaims);
      _pushPendingClaims();
    } on ApiException catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      AppSnackBar.show(context, message: e.message, tone: SnackTone.danger);
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      AppSnackBar.showMoneyError(context, 'Could not send');
    }
  }

  void _pushPendingClaims() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) =>
          PendingClaimsScreen(onBack: () => Navigator.of(context).pop()),
    ));
  }

  void _pushNotifications() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => NotificationsScreen(
        onBack: () => Navigator.of(context).pop(),
        onPendingClaims: _pushPendingClaims,
        onOpenGroup: (groupId) => pushGroupDetail(context, groupId),
      ),
    ));
  }

  void _pushSavings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => SavingsScreen(
        onBack: () => Navigator.of(context).pop(),
        onMoveToSavings: () =>
            pushSavingsTransferFlow(context, toSavings: true),
        onRequestWithdrawal: () =>
            pushSavingsTransferFlow(context, toSavings: false),
        onHideSavings: () => _pushHideSavingsSetup(context),
      ),
    ));
  }

  Future<void> _pushHideSavingsSetup(BuildContext context) async {
    final message = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (context) =>
          HideSavingsSetupScreen(onBack: () => Navigator.of(context).pop()),
    ));
    if (!context.mounted) return;
    // Home's own copy of these settings (loaded once in its initState)
    // needs to reflect whatever just changed.
    context.read<WalletStore>().loadHideSavingsSettings();
    // Shown from *this* still-mounted context, not the popped screen's own
    // (now-deactivated) one — see `HideSavingsSetupScreen`'s doc comment.
    if (message != null) AppSnackBar.show(context, message: message);
  }

  void _comingSoon(BuildContext context, String feature) {
    AppSnackBar.show(context,
        message: '$feature is coming soon.', tone: SnackTone.info);
  }

  void _pushSearch() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) =>
          buildSearch(context, onCashOut: () => pushCashOutFlow(context)),
    ));
  }

  void _pushRecovery() {
    Navigator.of(context).push(MaterialPageRoute(builder: buildRecoveryStart));
  }

  void _pushScanPay() => pushScanPayFlow(context);

  void _pushRecoveryVeto() {
    Navigator.of(context).push(MaterialPageRoute(builder: buildRecoveryVeto));
  }

  void _pushContactChat(BuildContext context, Contact contact) {
    final otherWalletId = contact.linkedWalletId;
    if (otherWalletId == null)
      return; // guarded by ContactsScreen's onJamii check
    context
        .read<WalletStore>()
        .markConversationReadAt(otherWalletId, DateTime.now());
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => ChatScreen(
        title: contact.name,
        myWalletId: context.read<WalletStore>().wallet?.id ?? '',
        fetchMessages: () =>
            context.read<WalletStore>().listDirectMessages(otherWalletId),
        sendMessage: (body, replyToId) => context
            .read<WalletStore>()
            .sendDirectMessage(
                otherWalletId: otherWalletId, body: body, replyToId: replyToId),
        setPinned: (id, pinned) => context
            .read<WalletStore>()
            .setMessagePinned(messageId: id, pinned: pinned),
        onBack: () => Navigator.of(context).pop(),
      ),
    ));
  }

  void _pushChatInbox(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => ChatInboxScreen(
        onBack: () => Navigator.of(context).pop(),
        fetchConversations: () =>
            context.read<WalletStore>().listConversations(),
        onOpenDirect: (conversation) {
          // Opening marks read at the previewed timestamp — anything
          // arriving while the chat is open re-dots via the 6s poll.
          context.read<WalletStore>().markConversationRead(conversation);
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => ChatScreen(
              title: conversation.name,
              myWalletId: context.read<WalletStore>().wallet?.id ?? '',
              fetchMessages: () => context
                  .read<WalletStore>()
                  .listDirectMessages(conversation.id),
              sendMessage: (body, replyToId) => context
                  .read<WalletStore>()
                  .sendDirectMessage(
                      otherWalletId: conversation.id,
                      body: body,
                      replyToId: replyToId),
              setPinned: (id, pinned) => context
                  .read<WalletStore>()
                  .setMessagePinned(messageId: id, pinned: pinned),
              onBack: () => Navigator.of(context).pop(),
            ),
          ));
        },
        onOpenGroup: (conversation) {
          context.read<WalletStore>().markConversationRead(conversation);
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => ChatScreen(
              title: conversation.name,
              myWalletId: context.read<WalletStore>().wallet?.id ?? '',
              fetchMessages: () => context
                  .read<WalletStore>()
                  .listGroupMessages(conversation.id),
              sendMessage: (body, replyToId) => context
                  .read<WalletStore>()
                  .sendGroupMessage(
                      groupId: conversation.id,
                      body: body,
                      replyToId: replyToId),
              setPinned: (id, pinned) => context
                  .read<WalletStore>()
                  .setMessagePinned(messageId: id, pinned: pinned),
              onBack: () => Navigator.of(context).pop(),
            ),
          ));
        },
        // A direct conversation's `name` is the sender's payment handle
        // (see `list_conversations`) — exactly what `addContact` needs.
        onAddToContacts: (conversation) async {
          try {
            await context.read<WalletStore>().addContact(
                name: conversation.name,
                kind: ContactKind.handle,
                value: conversation.name);
            if (!context.mounted) return;
            AppSnackBar.show(context,
                message: '${conversation.name} added to contacts.');
          } catch (e) {
            if (!context.mounted) return;
            AppSnackBar.show(context,
                message: 'Could not add contact: $e', tone: SnackTone.danger);
          }
        },
      ),
    ));
  }

  void _pushAddContact() {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => _buildAddContact(context)));
  }

  Widget _buildAddContact(BuildContext context, {String? errorText}) {
    return ContactNewScreen(
      onBack: () => Navigator.of(context).pop(),
      errorText: errorText,
      onSave: (name, kind, value) => _saveContact(context, name, kind, value),
    );
  }

  Future<void> _saveContact(
      BuildContext context, String name, ContactKind kind, String value) async {
    final store = context.read<WalletStore>();
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const LoadingVeil(message: 'Saving contact…'));
    try {
      await store.addContact(name: name, kind: kind, value: value);
      if (!context.mounted) return;
      Navigator.of(context).pop(); // dismiss veil
      Navigator.of(context).pop(); // back to Contacts
      AppSnackBar.show(context, message: 'Contact saved — $name added.');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // dismiss veil
      Navigator.of(context).pop(); // back to the add-contact screen
      Navigator.of(context).push(MaterialPageRoute(
          builder: (context) =>
              _buildAddContact(context, errorText: e.message)));
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      AppSnackBar.show(context,
          message: 'Could not save contact: $e', tone: SnackTone.danger);
    }
  }

  void _pushAppearance() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) =>
          ThemeScreen(onBack: () => Navigator.of(context).pop()),
    ));
  }

  void _pushAlerts() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) =>
          AlertSettingsScreen(onBack: () => Navigator.of(context).pop()),
    ));
  }

  void _pushLanguage() async {
    final saved =
        await const SessionStorage().readLanguage().catchError((_) => null);
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => LanguageScreen(
        initialCode: (saved as String?) ?? 'EN',
        continueLabel: 'Save language',
        showStep: false,
        onBack: () => Navigator.of(context).pop(),
        onContinue: () => Navigator.of(context).pop(),
      ),
    ));
  }

  // One slot per tab, filled in lazily the first time that tab is shown and
  // kept afterwards. Without this, switching tabs rebuilt the destination
  // fresh every time (a plain `switch` returning a new widget instance per
  // tap) — Activity's filter pill, any scroll position, anything transient
  // reset the moment you tabbed away and back. `IndexedStack` keeps every
  // visited tab mounted (just not painted), so its `State` survives; the
  // lazy fill means a tab never visited this session never pays to build
  // (or fetch) before the user actually opens it.
  final List<Widget?> _tabCache = List<Widget?>.filled(5, null);

  Widget _buildTab(int i) => switch (i) {
        0 => WalletHomeScreen(
            onReceive: _pushReceive,
            onSend: _pushSend,
            onSavings: _pushSavings,
            onSearch: _pushSearch,
            onCashOut: () => pushCashOutFlow(context),
            onComingSoon: (feature) => _comingSoon(context, feature),
            onPendingClaims: _pushPendingClaims,
            onNotifications: _pushNotifications,
            onScanPay: _pushScanPay,
          ),
        1 => ContactsScreen(
            onAddContact: _pushAddContact,
            onOpenChat: (contact) => _pushContactChat(context, contact),
            onOpenInbox: () => _pushChatInbox(context),
          ),
        2 => const Builder(builder: buildGroups),
        3 => const ActivityScreen(),
        _ => SettingsScreen(
            onAppearance: _pushAppearance,
            onAlerts: _pushAlerts,
            onSavings: _pushSavings,
            onRecovery: _pushRecovery,
            onRecoveryAlertDemo: _pushRecoveryVeto,
            onLanguage: _pushLanguage,
            onSignedOut: () => context.go('/'),
          ),
      };

  @override
  Widget build(BuildContext context) {
    _tabCache[_tab] ??= _buildTab(_tab);

    // A plain Column (Expanded body + fixed-height tab bar) rather than
    // Scaffold's dedicated `bottomNavigationBar` slot — that slot goes
    // through Scaffold's internal CustomMultiChildLayout, and this app hit
    // a real, reproducible bug there (body rendering with zero height
    // while bottomNavigationBar rendered fine, on both web and iOS). This
    // sidesteps it with a much simpler, well-tested layout primitive.
    return Scaffold(
      backgroundColor: AppColors.navy900,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  for (var i = 0; i < _tabCache.length; i++)
                    _tabCache[i] ?? const SizedBox.shrink()
                ],
              ),
            ),
            Consumer<WalletStore>(
              builder: (context, store, _) => WalletTabBar(
                currentIndex: _tab,
                onTap: (i) => setState(() => _tab = i),
                badges: {
                  1: store.unreadChatCount,
                  2: store.openVoteCount,
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
