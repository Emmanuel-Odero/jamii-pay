import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../bridge/api.dart' as bridge;
import '../data/api_client.dart';
import '../data/session_storage.dart';
import '../models/alert_preference.dart';
import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/escrow_claim.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';
import '../notifications/local_notifications.dart';
import '../security/device_vault.dart';
import '../security/pin_hash.dart';

enum WalletLoadState { idle, loading, ready, error }

/// The one place screens read wallet/transaction state from. Fetched once
/// (on wallet creation, or on app boot if a session is already persisted)
/// and shared via `Provider`/`ChangeNotifierProvider` at the app root —
/// see `main.dart`.
class WalletStore extends ChangeNotifier {
  WalletStore({JamiiPayApiClient? api, SessionStorage? storage})
      : _api = api ?? JamiiPayApiClient(),
        _storage = storage ?? const SessionStorage();

  final JamiiPayApiClient _api;
  final SessionStorage _storage;

  WalletLoadState state = WalletLoadState.idle;

  Wallet? _wallet;
  Wallet? get wallet => _wallet;

  /// Every assignment (there are several — creation, restore, savings
  /// transfers, ...) re-syncs the live-balance WebSocket to whichever
  /// wallet is now current, so nothing has to remember to do it manually.
  set wallet(Wallet? value) {
    _wallet = value;
    _syncBalanceSocket();
    _syncMessagePoll();
    unawaited(_loadReadMarks());
  }

  WebSocketChannel? _balanceSocket;
  StreamSubscription? _balanceSub;
  String? _balanceSocketWalletId;
  Timer? _balanceReconnectTimer;
  int _balanceReconnectAttempts = 0;

  /// Live balance push — see `crates/server/src/routes/ws.rs`. Best
  /// effort only: if the socket can't connect or drops, the app still
  /// works fine via ordinary HTTP calls, it just stops getting instant
  /// updates until the next successful (re)connect.
  void _syncBalanceSocket() {
    final id = _wallet?.id;
    if (id == _balanceSocketWalletId) return;
    _balanceReconnectTimer?.cancel();
    _balanceSub?.cancel();
    _balanceSocket?.sink.close();
    _balanceSocket = null;
    _balanceSocketWalletId = id;
    _sawFirstBalanceSnapshot = false;
    if (id != null) _connectBalanceSocket(id);
  }

  void _connectBalanceSocket(String walletId) {
    final wsUrl = _api.baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    try {
      final channel =
          WebSocketChannel.connect(Uri.parse('$wsUrl/wallets/$walletId/ws'));
      _balanceSocket = channel;
      _balanceReconnectAttempts = 0;
      _balanceSub = channel.stream.listen(
        _onBalancePush,
        onError: (_) => _scheduleBalanceReconnect(walletId),
        onDone: () => _scheduleBalanceReconnect(walletId),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleBalanceReconnect(walletId);
    }
  }

  void _scheduleBalanceReconnect(String walletId) {
    // Only if still the current wallet — avoids reconnecting to a wallet
    // the user has since signed out of or switched away from.
    // Exponential backoff (3s -> 30s max) instead of fixed 3s forever:
    // patchy networks outside Nairobi used to hot-loop reconnects.
    if (_balanceSocketWalletId != walletId) return;
    _balanceReconnectTimer?.cancel();
    _balanceReconnectAttempts++;
    final delaySeconds =
        (3 * (1 << (_balanceReconnectAttempts - 1).clamp(0, 3))).clamp(3, 30);
    _balanceReconnectTimer = Timer(
        Duration(seconds: delaySeconds),
        () => _connectBalanceSocket(walletId));
  }

  /// `false` until the socket's very first message (the connect-time
  /// snapshot) has been seen — that one is "here's your current
  /// balance," not "money just arrived," so it must never trigger a
  /// notification the way every message after it should when the
  /// balance has actually gone up.
  bool _sawFirstBalanceSnapshot = false;

  void _onBalancePush(dynamic event) async {
    try {
      final data = jsonDecode(event as String) as Map<String, dynamic>;
      if (data['type'] != 'balance' || _wallet == null) return;
      final newEveryday = (data['everyday_balance_usd_cents'] as num).toInt();
      final oldEveryday = _wallet!.everydayBalanceUsdCents;
      _wallet = _wallet!.copyWith(
        everydayBalanceUsdCents: newEveryday,
        savingsBalanceUsdCents:
            (data['savings_balance_usd_cents'] as num).toInt(),
      );
      if (_sawFirstBalanceSnapshot && newEveryday > oldEveryday) {
        // Redacted by default: exact amounts on the lock screen leak
        // balances to shoulder-surfers. Open the app for the figure.
        // Awaited (not fire-and-forget): an unawaited show() turns plugin
        // failures into silent unhandled errors — the exact "no banner,
        // no clue" symptom this path once had.
        await LocalNotifications.show(
          title: 'Money received',
          body: 'A payment just arrived — open JamiiPay to see it.',
          badgeCount: bellBadgeCount,
        );
      }
      _sawFirstBalanceSnapshot = true;
      notifyListeners();
    } catch (_) {
      // Malformed/unexpected push — ignore rather than crash the socket
      // listener over one bad frame.
    }
  }

  Timer? _messagePollTimer;
  final Map<String, DateTime> _lastSeenMessageAt = {};
  bool _messagePollPrimed = false;

  /// New-message alerts — there's no per-conversation server push, so
  /// this polls the same `listConversations` the inbox screen uses and
  /// diffs `lastMessageAt` per thread. The first poll after a wallet
  /// loads only *records* what's there (so existing history doesn't
  /// spam a wall of notifications the moment you sign in); every poll
  /// after that notifies for anything newer that wasn't sent by me.
  void _syncMessagePoll() {
    _messagePollTimer?.cancel();
    _lastSeenMessageAt.clear();
    _messagePollPrimed = false;
    if (_wallet == null) return;
    _pollConversationsForNotifications();
    _messagePollTimer = Timer.periodic(const Duration(seconds: 6),
        (_) => _pollConversationsForNotifications());
  }

  Future<void> _pollConversationsForNotifications() async {
    if (_wallet == null) return;
    final myWalletId = _wallet!.id;
    List<Conversation> fetched;
    try {
      fetched = await listConversations();
    } catch (_) {
      return; // transient — the next tick tries again
    }

    // Publish first so badge counts (and the banner's badge number) are
    // fresh — the fetched list used to die in a shadowing local, leaving
    // every in-app badge permanently at zero.
    conversations = fetched;
    for (final c in fetched) {
      final previouslySeen = _lastSeenMessageAt[c.id];
      final isNew =
          previouslySeen == null || c.lastMessageAt.isAfter(previouslySeen);
      _lastSeenMessageAt[c.id] = c.lastMessageAt;
      if (!_messagePollPrimed ||
          !isNew ||
          c.lastMessageSenderWalletId == myWalletId) continue;
      LocalNotifications.show(
        title: c.kind == ConversationKind.group
            ? c.name
            : 'New message from ${c.name}',
        body: c.lastMessage,
        // Field is already updated above, so the triggering message is
        // included in the count the icon badge shows.
        badgeCount: unreadChatCount,
      );
    }
    _messagePollPrimed = true;
    notifyListeners();
  }

  List<Transaction> transactions = const [];
  List<Contact> contacts = const [];
  List<Group> groups = const [];
  List<EscrowClaim> escrowClaims = const [];
  List<GroupInvite> invites = const [];

  /// Last polled conversation list (refreshed every 6s by
  /// [_pollConversationsForNotifications]) — badge counts and inbox dots
  /// read from here so no screen pays an extra fetch for them.
  List<Conversation> conversations = const [];

  /// Per-conversation last-read marks (persisted in secure storage).
  /// Unknown ids mean "never seen" — treated as baselined, never unread.
  Map<String, DateTime> lastReadAt = {};
  String? error;

  Future<void> _loadReadMarks() async {
    try {
      lastReadAt = await _storage.readConversationReads();
      notifyListeners();
    } catch (_) {}
  }

  /// Unread rule (no server read-receipts exist, so this is per-device):
  /// - a stored mark → unread iff a newer message arrived from someone else;
  /// - no mark (never opened, fresh login) → unread iff the latest message
  ///   is from someone else AND within the last 72h. The window bounds
  ///   history spam after a fresh login while still catching "yesterday's
  ///   message I never saw". Opening a chat writes the mark (persisted).
  static const _unreadWindow = Duration(hours: 72);

  bool isUnread(Conversation c) {
    if (c.lastMessageSenderWalletId == _wallet?.id) return false;
    final mark = lastReadAt[c.id];
    if (mark == null) {
      return DateTime.now().difference(c.lastMessageAt) < _unreadWindow;
    }
    return c.lastMessageAt.isAfter(mark);
  }

  int get unreadChatCount {
    var n = 0;
    for (final c in conversations) {
      if (isUnread(c)) n++;
    }
    return n;
  }

  int get pendingInviteCount => invites.length;

  int get openVoteCount => groups
      .where((g) => g.openWithdrawalRequestId != null)
      .length;

  /// Home bell badge: waiting escrow + unread chats + pending invites.
  int get bellBadgeCount =>
      escrowClaims.length + unreadChatCount + pendingInviteCount;

  Future<void> markConversationRead(Conversation c) =>
      markConversationReadAt(c.id, c.lastMessageAt);

  Future<void> markConversationReadAt(String id, DateTime at) async {
    final cur = lastReadAt[id];
    if (cur != null && !at.isAfter(cur)) return;
    lastReadAt[id] = at;
    notifyListeners();
    await _persistMark(id, at);
  }

  Future<void> _persistMark(String id, DateTime at) async {
    try {
      await _storage.saveConversationRead(id, at);
    } catch (_) {}
  }

  bool get hasWallet => wallet != null;

  // --- Hide savings (coercion protection) — ephemeral reveal state lives
  // here rather than in `HomeScreen`'s own State, because the reveal
  // gesture can be satisfied from a *different* screen (Search's secret
  // phrase) than the one that needs to react to it (Home's savings
  // card) — see `hide_savings_setup_screen.dart` for the persisted
  // settings this reads.
  bool hideSavingsEnabled = false;
  String hideSavingsAction = 'tap';
  int hideSavingsCount = 3;
  int hideSavingsRevealSeconds = 20;
  String? _hideSavingsPhraseHash;
  bool savingsRevealed = false;
  int _tapCount = 0;
  Timer? _tapResetTimer;
  Timer? _revealTimer;

  Future<void> loadHideSavingsSettings() async {
    hideSavingsEnabled = await _storage.readHideSavingsEnabled();
    hideSavingsAction = await _storage.readHideSavingsAction() ?? 'tap';
    hideSavingsCount = await _storage.readHideSavingsCount();
    hideSavingsRevealSeconds = await _storage.readHideSavingsRevealSeconds();
    _hideSavingsPhraseHash = await _storage.readHideSavingsPhraseHash();
    notifyListeners();
  }

  /// One qualifying tap or long-press toward `hideSavingsCount` — resets
  /// after 1400ms of inactivity, matching the prototype's `bumpReveal`/
  /// `tapReset` timing exactly.
  void bumpSavingsReveal() {
    _tapCount++;
    _tapResetTimer?.cancel();
    _tapResetTimer =
        Timer(const Duration(milliseconds: 1400), () => _tapCount = 0);
    if (_tapCount >= hideSavingsCount) {
      _tapCount = 0;
      revealSavings();
    }
  }

  /// Returns true (and reveals) if `query` matches the stored secret
  /// phrase — callers should clear the search field and navigate home
  /// when this returns true, same as the prototype's search-triggered
  /// reveal.
  bool checkSavingsRevealPhrase(String query) {
    if (_hideSavingsPhraseHash == null) return false;
    if (hashPin(query.trim().toLowerCase()) != _hideSavingsPhraseHash)
      return false;
    revealSavings();
    return true;
  }

  void revealSavings() {
    savingsRevealed = true;
    notifyListeners();
    _revealTimer?.cancel();
    _revealTimer = Timer(Duration(seconds: hideSavingsRevealSeconds), () {
      savingsRevealed = false;
      notifyListeners();
    });
  }

  /// Checked once at app boot: if a session is already persisted, skip
  /// onboarding and reload it straight away.
  Future<bool> restoreSession() async {
    final walletId = await _storage.readWalletId();
    if (walletId == null) return false;
    await refresh(walletId);
    return state == WalletLoadState.ready;
  }

  Future<void> refresh([String? walletId]) async {
    final id = walletId ?? wallet?.id;
    if (id == null) return;
    state = WalletLoadState.loading;
    notifyListeners();
    try {
      final results = await Future.wait(
          [_api.getWallet(id), _api.listTransactions(id), _api.listEscrow(id)]);
      wallet = results[0] as Wallet;
      transactions = results[1] as List<Transaction>;
      escrowClaims = results[2] as List<EscrowClaim>;
      state = WalletLoadState.ready;
    } catch (e) {
      error = e.toString();
      state = WalletLoadState.error;
    }
    // Best-effort: invites feed the bell badge but must never fail
    // the whole refresh (and its offline banner) on their own.
    await loadInvites();
    notifyListeners();
  }

  /// Group invites for the bell badge + Notifications feed. Independent
  /// from [refresh]'s core three — fails to empty, never throws.
  Future<void> loadInvites() async {
    if (_wallet == null) return;
    try {
      invites = await _api.listInvites(_wallet!.id);
    } catch (_) {
      invites = const [];
    }
    notifyListeners();
  }

  /// Generates a real key via the `wallet-core` FFI bridge, persists it,
  /// and registers the wallet with the backend. Called once, at the end of
  /// onboarding — `pinHash` is the same PIN hash saved locally by the PIN
  /// step earlier in onboarding, sent along so `verifyPin` has something
  /// to check against later if this wallet is ever restored on another
  /// device via a downloaded wallet key.
  Future<void> createWallet({
    required String handleBase,
    required Set<String> guardians,
    required String pinHash,
  }) async {
    state = WalletLoadState.loading;
    notifyListeners();
    try {
      final keyMaterial = bridge.generateWallet();
      // Best-effort device binding: the server records the vault key for
      // future release policy, but creation never fails for want of it
      // (simulators, vault-less builds).
      final device = await DeviceVault.ensureKey();
      wallet = await _api.createWallet(
        evmAddress: keyMaterial.addressHex,
        handleBase: handleBase,
        guardians: guardians.toList(),
        pinHash: pinHash,
        deviceKeyPub: device?.publicKeyBase64,
        deviceEnclave: device?.hardwareBacked ?? false,
      );
      await _storage.saveSession(
          walletId: wallet!.id, privateKeyHex: keyMaterial.privateKeyHex);
      transactions = await _api.listTransactions(wallet!.id);
      state = WalletLoadState.ready;
    } catch (e) {
      error = e.toString();
      state = WalletLoadState.error;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// Rotates the wallet's device key after wallet-PIN proof: fresh key in
  /// `wallet-core`, off-chain record + device binding updated, every
  /// escrowed backup revoked server-side. The session is re-saved (vault
  /// re-wrapped) and the wallet reloaded.
  ///
  /// Callers must then: (a) prompt a fresh v2 export — old QRs, v1
  /// whole-key prints included, are dead by design; (b) where the smart
  /// account is live, point its owner at the new address (RecoveryModule
  /// or an owner update), since this endpoint rotates the off-chain
  /// record, not the chain.
  Future<void> rotateWalletKey({required String walletPinHash}) async {
    if (wallet == null) throw StateError('no active wallet');
    state = WalletLoadState.loading;
    notifyListeners();
    try {
      final fresh = bridge.generateWallet();
      final device = await DeviceVault.ensureKey();
      wallet = await _api.rotateWalletKey(
        walletId: wallet!.id,
        newEvmAddress: fresh.addressHex,
        pinHash: walletPinHash,
        deviceKeyPub: device?.publicKeyBase64,
        deviceEnclave: device?.hardwareBacked ?? false,
      );
      await _storage.saveSession(
          walletId: wallet!.id, privateKeyHex: fresh.privateKeyHex);
      transactions = await _api.listTransactions(wallet!.id);
      state = WalletLoadState.ready;
    } catch (e) {
      error = e.toString();
      state = WalletLoadState.error;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// Encrypts the current session's private key under `pin` for the
  /// "Download wallet key" backup screen. Reads straight from secure
  /// storage rather than caching the key anywhere on this object.
  ///
  /// Legacy (v1) — retained for decrypting already-printed backups only.
  /// New exports must use [exportSplitBackup].
  Future<bridge.EncryptedKeyBackup> exportEncryptedKey(String pin) async {
    final privateKeyHex = await _storage.readPrivateKeyHex();
    if (privateKeyHex == null || wallet == null)
      throw StateError('no active wallet to export');
    return bridge.encryptWalletKey(
        privateKeyHex: privateKeyHex, addressHex: wallet!.evmAddress, pin: pin);
  }

  /// v2 split-backup export: splits the private key (`S1` PIN-wrapped for
  /// the QR, `S2` uploaded to the server release oracle) and stores `S2`
  /// before returning. If the upload fails, throws — the caller must not
  /// show a QR whose other half was never escrowed.
  ///
  /// Runs OPAQUE registration for the key PIN first, so the release oracle
  /// never sees the PIN or any deterministic function of it — only the
  /// password file. Order: split → OPAQUE register → escrow `S2` → QR.
  /// Any step failing aborts the export with no QR shown.
  Future<SplitBackupMaterial> exportSplitBackup(String pin) async {
    final privateKeyHex = await _storage.readPrivateKeyHex();
    if (privateKeyHex == null || wallet == null) {
      throw StateError('no active wallet to export');
    }
    final raw = bridge.createSplitBackup(
        privateKeyHex: privateKeyHex,
        addressHex: wallet!.evmAddress,
        pin: pin);
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final material = SplitBackupMaterial(
      backupId: map['backup_id'] as String,
      qrPayload: map['qr_payload'] as String,
      s2Hex: map['s2_hex'] as String,
      addressHex: map['address_hex'] as String,
    );
    await _opaqueRegister(walletId: wallet!.id, backupId: material.backupId, pin: pin);
    await _api.storeBackupShare(
        walletId: wallet!.id, backupId: material.backupId, s2Hex: material.s2Hex);
    return material;
  }

  /// OPAQUE registration for one backup's key PIN. Both round trips run
  /// here; client state lives in Rust memory between them (the app holds
  /// only a single-use handle).
  Future<void> _opaqueRegister(
      {required String walletId,
      required String backupId,
      required String pin}) async {
    final startRaw = bridge.opaqueRegisterStart(pin: pin);
    final start = jsonDecode(startRaw) as Map<String, dynamic>;
    final responseB64 = await _api.opaqueRegisterStart(
        walletId: walletId,
        backupId: backupId,
        requestB64: start['request_b64'] as String);
    final finishRaw = bridge.opaqueRegisterFinish(
        handle: start['handle'] as String,
        responseB64: responseB64,
        pin: pin);
    final finish = jsonDecode(finishRaw) as Map<String, dynamic>;
    await _api.opaqueRegisterFinish(
        walletId: walletId,
        backupId: backupId,
        uploadB64: finish['upload_b64'] as String);
  }

  /// v2 restore via OPAQUE: proves key-PIN knowledge to the release oracle
  /// without ever sending the PIN (or its hash) and returns `s2Hex`.
  /// Throws [ApiException] with the server's status (401/423/410).
  Future<String> opaqueLoginRelease(
      {required String backupId, required String keyPin}) async {
    final startRaw = bridge.opaqueLoginStart(pin: keyPin);
    final start = jsonDecode(startRaw) as Map<String, dynamic>;
    final (loginId, responseB64) = await _api.opaqueLoginStart(
        backupId: backupId, requestB64: start['request_b64'] as String);
    final finishRaw = bridge.opaqueLoginFinish(
        handle: start['handle'] as String,
        responseB64: responseB64,
        pin: keyPin);
    final finish = jsonDecode(finishRaw) as Map<String, dynamic>;
    return _api.opaqueLoginFinish(
        backupId: backupId,
        loginId: loginId,
        finalizationB64: finish['finalization_b64'] as String);
  }

  /// v2 restore, step 2 of 4 — unwraps the QR-side share with the key PIN.
  /// Returns `s1Hex`: random bytes, useless without the server's `s2Hex`.
  String decryptBackupShare(
          {required String saltHex,
          required String nonceHex,
          required String ciphertextHex,
          required String keyPin}) =>
      bridge.decryptBackupShare(
          saltHex: saltHex,
          nonceHex: nonceHex,
          ciphertextHex: ciphertextHex,
          pin: keyPin);

  /// v2 restore, step 3 of 4 — releases the server-held share after proving
  /// wallet-PIN knowledge. The server rate-limits and locks after repeated
  /// failures; every request is audit-logged and alerts guardians.
  Future<String> releaseBackupShare(
          {required String backupId, required String walletPinHash}) =>
      _api.releaseBackupShare(backupId: backupId, pinHash: walletPinHash);

  /// v2 restore, step 4 of 4 — recombines both shares into the private key.
  /// Call with both shares in hand, in memory, immediately before
  /// [restoreFromPrivateKey].
  String combineBackupShares({required String s1Hex, required String s2Hex}) =>
      bridge.combineBackupShares(s1Hex: s1Hex, s2Hex: s2Hex);

  /// "Restore from wallet key", step 1 of 2 — decrypts an uploaded backup
  /// with the key PIN. Kept separate from [restoreFromPrivateKey] so the
  /// screen flow can fail fast on a wrong key PIN before ever asking for
  /// the wallet PIN. Throws a bridge exception (message: "incorrect PIN,
  /// or the file is corrupted") on failure — the caller shows it as-is.
  String decryptBackup(
          {required bridge.EncryptedKeyBackup backup,
          required String keyPin}) =>
      bridge.decryptWalletKey(backup: backup, pin: keyPin);

  /// "Restore from wallet key", step 2 of 2 — the counterpart to
  /// [exportEncryptedKey]. Proves ownership of the already-decrypted key
  /// to the server with `walletPinHash` (hash of the app-unlock PIN set
  /// when this wallet was first created) via `POST /wallets/verify-pin`.
  /// On success, saves a fresh local session and loads the wallet — this
  /// device now has a live session exactly like one that just finished
  /// onboarding. Throws [ApiException] (401) on a wrong wallet PIN.
  Future<void> restoreFromPrivateKey(
      {required String privateKeyHex, required String walletPinHash}) async {
    state = WalletLoadState.loading;
    notifyListeners();
    try {
      final addressHex =
          bridge.addressFromPrivateKey(privateKeyHex: privateKeyHex);
      final verification =
          await _api.verifyPin(evmAddress: addressHex, pinHash: walletPinHash);
      await _storage.saveSession(
          walletId: verification.id, privateKeyHex: privateKeyHex);
      await _storage.savePinHash(walletPinHash);
      wallet = await _api.getWallet(verification.id);
      transactions = await _api.listTransactions(verification.id);
      state = WalletLoadState.ready;
    } catch (e) {
      error = e.toString();
      state = WalletLoadState.error;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<HandleAvailability> checkHandleAvailability(String base) =>
      _api.checkHandleAvailability(base);

  FxRate? _fxCache;
  FxRate? get fxCache => _fxCache;

  /// Live FX with 30-min cache — review sheets call this to freeze the
  /// quote at confirm time. Falls back to static constants offline.
  Future<FxRate> getFxRate({bool forceRefresh = false}) async {
    if (!forceRefresh && _fxCache != null) {
      final age = DateTime.now().difference(_fxCache!.updatedAt);
      if (age < const Duration(minutes: 30)) return _fxCache!;
    }
    try {
      final fx = await _api.getFxRate();
      _fxCache = fx;
      try {
        await _storage.saveFxRate(fx.rate);
      } catch (_) {}
      return fx;
    } catch (_) {
      // Offline: last persisted rate, else static fallback.
      try {
        final cached = await _storage.readFxRate();
        if (cached != null) {
          _fxCache = FxRate(
            rate: cached.$1,
            spread: 0.008,
            effectiveCashoutRate: cached.$1 * (1 - 0.008),
            handleFeeUsdCents: 4,
            escrowFeeUsdCents: 9,
            updatedAt: cached.$2,
          );
          return _fxCache!;
        }
      } catch (_) {}
      _fxCache = FxRate.fallback();
      return _fxCache!;
    }
  }

  /// Sends real money between two wallets — see `SendScreen`. Refreshes
  /// this wallet's transactions afterward so Activity/Home pick up the new
  /// outgoing row without a separate manual refresh.
  /// Backend debits `amount + fee`; recipient is credited `amount`.
  Future<void> sendMoney(
      {required String recipientFullHandle,
      required int amountUsdCents,
      String? idempotencyKey}) async {
    if (wallet == null) throw StateError('no active wallet');
    final newBalanceUsd = await _api.transfer(
      walletId: wallet!.id,
      recipientFullHandle: recipientFullHandle,
      amountUsdCents: amountUsdCents,
      idempotencyKey: idempotencyKey,
    );
    wallet = Wallet(
      id: wallet!.id,
      evmAddress: wallet!.evmAddress,
      fullHandle: wallet!.fullHandle,
      everydayBalanceUsdCents: (newBalanceUsd * 100).round(),
      savingsBalanceUsdCents: wallet!.savingsBalanceUsdCents,
      guardians: wallet!.guardians,
    );
    transactions = await _api.listTransactions(wallet!.id);
    notifyListeners();
  }

  /// Real backend for the Cash-out flow — debits everyday balance,
  /// records the transaction, and refreshes the transaction list so
  /// Activity/Home pick it up immediately.
  Future<CashOutResult> cashOut(
      {required String mpesaNumber,
      required int amountUsdCents,
      String? idempotencyKey}) async {
    if (wallet == null) throw StateError('no active wallet');
    final result = await _api.cashOut(
        walletId: wallet!.id,
        mpesaNumber: mpesaNumber,
        amountUsdCents: amountUsdCents,
        idempotencyKey: idempotencyKey);
    wallet = Wallet(
      id: wallet!.id,
      evmAddress: wallet!.evmAddress,
      fullHandle: wallet!.fullHandle,
      everydayBalanceUsdCents: (result.everydayBalanceUsd * 100).round(),
      savingsBalanceUsdCents: wallet!.savingsBalanceUsdCents,
      guardians: wallet!.guardians,
    );
    transactions = await _api.listTransactions(wallet!.id);
    notifyListeners();
    return result;
  }

  /// Loads this wallet's saved contacts — called once when the Contacts
  /// tab is first shown, and after every add/remove so the list stays in
  /// sync without a full `refresh()`.
  Future<void> loadContacts() async {
    if (wallet == null) return;
    contacts = await _api.listContacts(wallet!.id);
    notifyListeners();
  }

  /// Throws [ApiException] (404) if a `handle`-kind value doesn't resolve
  /// to a real registered wallet — the caller shows that as a form error,
  /// same as the prototype's live "✕ Not a valid payment ID" message.
  Future<void> addContact(
      {required String name,
      required ContactKind kind,
      required String value}) async {
    if (wallet == null) throw StateError('no active wallet');
    final contact = await _api.createContact(
        walletId: wallet!.id, name: name, kind: kind, value: value);
    contacts = [...contacts, contact]..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  Future<void> removeContact(String contactId) async {
    if (wallet == null) throw StateError('no active wallet');
    await _api.deleteContact(walletId: wallet!.id, contactId: contactId);
    contacts = contacts.where((c) => c.id != contactId).toList();
    notifyListeners();
  }

  /// Loads this wallet's groups/chamas — called when the Groups screen is
  /// first shown, and after create/contribute/execute so the list and
  /// each group's pot stay in sync without a full `refresh()`.
  Future<void> loadGroups() async {
    if (wallet == null) return;
    groups = await _api.listGroups(wallet!.id);
    notifyListeners();
  }

  Future<Group> createGroup({
    required String name,
    required GroupKind kind,
    required GroupPowerScheme powerScheme,
    required List<String> memberContactIds,
  }) async {
    if (wallet == null) throw StateError('no active wallet');
    final group = await _api.createGroup(
      ownerWalletId: wallet!.id,
      name: name,
      kind: kind,
      powerScheme: powerScheme,
      memberContactIds: memberContactIds,
    );
    groups = [...groups, group];
    notifyListeners();
    return group;
  }

  Future<Group> getGroup(String groupId) => _api.getGroup(groupId);

  /// Debits *this* wallet's everyday balance into the group's pot —
  /// callers must already know the current member owns `wallet`; the
  /// server re-validates membership regardless.
  Future<Group> contributeToGroup(
      {required String groupId, required int amountUsdCents}) async {
    if (wallet == null) throw StateError('no active wallet');
    final group = await _api.contributeToGroup(
        groupId: groupId, walletId: wallet!.id, amountUsdCents: amountUsdCents);
    // Contributing also debits *this* wallet, so its own balance needs a
    // refresh — the group pot alone doesn't tell the Home screen anything.
    await refresh();
    return group;
  }

  Future<GroupWithdrawal> openWithdrawal(
          {required String groupId,
          required int amountUsdCents,
          required String payeeName}) =>
      _api.openWithdrawal(
          groupId: groupId,
          amountUsdCents: amountUsdCents,
          payeeName: payeeName);

  Future<GroupWithdrawal> getWithdrawal(
          {required String groupId, required String requestId}) =>
      _api.getWithdrawal(groupId: groupId, requestId: requestId);

  Future<GroupWithdrawal> castVote({
    required String groupId,
    required String requestId,
    required String memberId,
    required VoteChoice choice,
  }) =>
      _api.castVote(
          groupId: groupId,
          requestId: requestId,
          memberId: memberId,
          choice: choice);

  Future<GroupWithdrawal> executeWithdrawal(
          {required String groupId, required String requestId}) =>
      _api.executeWithdrawal(groupId: groupId, requestId: requestId);

  Future<GroupWithdrawal> proposeAddMember(
          {required String groupId, String? contactId, String? handle}) =>
      _api.proposeAddMember(
          groupId: groupId, contactId: contactId, handle: handle);

  Future<void> respondToInvite(
      {required String groupId,
      required String requestId,
      required bool accept}) {
    if (wallet == null) throw StateError('no active wallet');
    return _api.respondToInvite(
        groupId: groupId,
        requestId: requestId,
        walletId: wallet!.id,
        accept: accept);
  }

  Future<List<GroupInvite>> listInvites() {
    if (wallet == null) throw StateError('no active wallet');
    return _api.listInvites(wallet!.id);
  }

  Future<void> moveToSavings(int amountUsdCents) async {
    if (wallet == null) throw StateError('no active wallet');
    final result = await _api.moveToSavings(
        walletId: wallet!.id, amountUsdCents: amountUsdCents);
    wallet = wallet!.copyWith(
        everydayBalanceUsdCents: (result.everydayBalanceUsd * 100).round(),
        savingsBalanceUsdCents: (result.savingsBalanceUsd * 100).round());
    notifyListeners();
  }

  Future<void> withdrawFromSavings(int amountUsdCents) async {
    if (wallet == null) throw StateError('no active wallet');
    final result = await _api.withdrawFromSavings(
        walletId: wallet!.id, amountUsdCents: amountUsdCents);
    wallet = wallet!.copyWith(
        everydayBalanceUsdCents: (result.everydayBalanceUsd * 100).round(),
        savingsBalanceUsdCents: (result.savingsBalanceUsd * 100).round());
    notifyListeners();
  }

  Future<GroupWithdrawal> proposeRemoveMember(
          {required String groupId, required String memberId}) =>
      _api.proposeRemoveMember(groupId: groupId, memberId: memberId);

  // --- Chat (66-char, groups + direct) ---------------------------------

  Future<List<ChatMessage>> listGroupMessages(String groupId) =>
      _api.listGroupMessages(groupId);

  Future<ChatMessage> sendGroupMessage(
      {required String groupId, required String body, String? replyToId}) {
    if (wallet == null) throw StateError('no active wallet');
    return _api.sendGroupMessage(
        groupId: groupId,
        senderWalletId: wallet!.id,
        body: body,
        replyToId: replyToId);
  }

  Future<List<ChatMessage>> listDirectMessages(String otherWalletId) {
    if (wallet == null) throw StateError('no active wallet');
    return _api.listDirectMessages(
        walletId: wallet!.id, otherWalletId: otherWalletId);
  }

  Future<ChatMessage> sendDirectMessage(
      {required String otherWalletId,
      required String body,
      String? replyToId}) {
    if (wallet == null) throw StateError('no active wallet');
    return _api.sendDirectMessage(
        walletId: wallet!.id,
        otherWalletId: otherWalletId,
        body: body,
        replyToId: replyToId);
  }

  Future<void> setMessagePinned(
          {required String messageId, required bool pinned}) =>
      _api.setMessagePinned(messageId: messageId, pinned: pinned);

  Future<MpesaStkPushResult> initiateMpesaStkPush(
      {required String phone,
      required int amountUsdCents,
      String? idempotencyKey}) {
    if (wallet == null) throw StateError('no active wallet');
    return _api.initiateMpesaStkPush(
        walletId: wallet!.id,
        phone: phone,
        amountUsdCents: amountUsdCents,
        idempotencyKey: idempotencyKey);
  }

  Future<MpesaDepositStatus> pollMpesaDeposit(String checkoutRequestId) {
    if (wallet == null) throw StateError('no active wallet');
    return _api.pollMpesaDeposit(
        walletId: wallet!.id, checkoutRequestId: checkoutRequestId);
  }

  Future<CardTopupCheckout> createCardTopupCheckout(int amountUsdCents) {
    if (wallet == null) throw StateError('no active wallet');
    return _api.createCardTopupCheckout(
        walletId: wallet!.id, amountUsdCents: amountUsdCents);
  }

  Future<CardTopupStatus> pollCardTopup(String topupId) {
    if (wallet == null) throw StateError('no active wallet');
    return _api.pollCardTopup(walletId: wallet!.id, topupId: topupId);
  }

  Future<List<Conversation>> listConversations() {
    if (wallet == null) throw StateError('no active wallet');
    return _api.listConversations(wallet!.id);
  }

  Future<void> broadcastToGroup({
    required String groupId,
    required int amountPerMemberUsdCents,
    required List<String> memberWalletIds,
  }) async {
    if (wallet == null) throw StateError('no active wallet');
    await _api.broadcastToGroup(
      groupId: groupId,
      senderWalletId: wallet!.id,
      amountPerMemberUsdCents: amountPerMemberUsdCents,
      memberWalletIds: memberWalletIds,
    );
    await refresh();
  }

  /// Send-to-non-user — see `SendScreen`'s branch for a phone/email
  /// recipient and `PendingClaimsScreen`. Refreshes the wallet balance
  /// (the create call debits it server-side) and the claim list together
  /// so the "N waiting to be claimed" home banner picks it up immediately.
  Future<EscrowClaim> createEscrow(
      {required String recipientAddr,
      required String recipientKind,
      required int amountUsdCents}) async {
    if (wallet == null) throw StateError('no active wallet');
    final claim = await _api.createEscrow(
      walletId: wallet!.id,
      recipientAddr: recipientAddr,
      recipientKind: recipientKind,
      amountUsdCents: amountUsdCents,
    );
    await refresh(); // now also reloads escrowClaims
    return claim;
  }

  Future<void> loadEscrow() async {
    if (wallet == null) return;
    escrowClaims = await _api.listEscrow(wallet!.id);
    notifyListeners();
  }

  Future<void> cancelEscrow(String claimId) async {
    if (wallet == null) throw StateError('no active wallet');
    await _api.cancelEscrow(walletId: wallet!.id, claimId: claimId);
    await refresh(); // now also reloads escrowClaims
  }

  Future<List<AlertPreference>> getAlertPreferences() {
    if (wallet == null) throw StateError('no active wallet');
    return _api.getAlertPreferences(wallet!.id);
  }

  Future<List<AlertPreference>> updateAlertPreferences(
      List<AlertPreference> preferences) {
    if (wallet == null) throw StateError('no active wallet');
    return _api.updateAlertPreferences(wallet!.id, preferences);
  }

  Future<List<RecoverySummary>> listRecoveryHistory() {
    if (wallet == null) throw StateError('no active wallet');
    return _api.listRecovery(wallet!.id);
  }

  Future<RecoveryStatus> startRecovery(
          {required String fullHandle, bool reportedStolen = false}) =>
      _api.startRecovery(
          fullHandle: fullHandle, reportedStolen: reportedStolen);

  Future<RecoveryStatus> getRecovery(String id) => _api.getRecovery(id);

  Future<RecoveryStatus> approveRecovery(String id, String guardianType) =>
      _api.approveRecovery(id, guardianType);

  Future<RecoveryStatus> cancelRecovery(String id) => _api.cancelRecovery(id);

  /// Wipes the persisted session (wallet id, private key, PIN hash,
  /// biometric flag) and resets in-memory state. There's no server-side
  /// "log out" — the private key only ever lived on this device, so this
  /// is the only place the app can forget it.
  Future<void> signOut() async {
    await _storage.clear();
    wallet = null;
    transactions = const [];
    contacts = const [];
    groups = const [];
    escrowClaims = const [];
    invites = const [];
    conversations = const [];
    lastReadAt = {};
    _lastSeenMessageAt.clear();
    _messagePollPrimed = false;
    hideSavingsEnabled = false;
    savingsRevealed = false;
    _tapResetTimer?.cancel();
    _revealTimer?.cancel();
    state = WalletLoadState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _tapResetTimer?.cancel();
    _revealTimer?.cancel();
    _balanceReconnectTimer?.cancel();
    _balanceSub?.cancel();
    _balanceSocket?.sink.close();
    _messagePollTimer?.cancel();
    super.dispose();
  }
}
