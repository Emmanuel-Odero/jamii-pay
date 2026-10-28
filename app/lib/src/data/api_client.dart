import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/alert_preference.dart';
import '../models/contact.dart';
import '../models/escrow_claim.dart';
import '../models/conversation.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';

/// Thrown for any non-2xx response. The server always replies with
/// `{"error": "message"}` on failure (`crates/server/src/error.rs`).
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thin wrapper over `crates/server`'s HTTP API. The default `baseUrl`
/// would ideally point at the dev Mac's Bonjour/mDNS name rather than
/// `localhost`, because `localhost` on a physical iPhone means the phone
/// itself, not the Mac — `<hostname>.local` resolving over whatever local
/// network the two devices currently share (home Wi-Fi, or the Mac
/// tethered to the iPhone's Personal Hotspot) avoids a hardcoded LAN IP
/// that changes per network.
///
/// That mDNS name is currently unreliable on this dev Mac, though: it has
/// several active network interfaces (Wi-Fi plus what looks like Internet
/// Sharing), and `<hostname>.local` was resolving to addresses on those
/// *other* interfaces — reachable from the Mac itself (so the iOS
/// Simulator, sharing the host's network stack, never noticed), but not
/// from a physical iPhone on the same Wi-Fi, which could only ever reach
/// the Wi-Fi (`en0`) address. Pinned to that direct IP for now so the
/// physical-device build actually works; **this will need updating**
/// (`ipconfig getifaddr en0` on the Mac) whenever the Mac's IP changes —
/// switch back to the `.local` hostname if/once the multi-interface mDNS
/// confusion is resolved (e.g. Internet Sharing turned off). Current Wi-Fi
/// IP as of Sep 2026: 192.168.1.221 (`ipconfig getifaddr en0` on the Mac
/// to re-check). Prefer passing
/// --dart-define=API_BASE=http://<current-ip>:8081 at build time over
/// editing the default below. Port 8081,
/// not the more usual 8080 — see `docker/docker-compose.yml`'s `server`
/// service comment for why.
class JamiiPayApiClient {
  JamiiPayApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ??
            const String.fromEnvironment(
              'API_BASE',
              // Fallback for local runs without --dart-define: the Mac's
              // Wi-Fi IP. Pass --dart-define=API_BASE=http://<ip>:8081 to
              // point at another network (e.g. the 192.168.2.1 hotspot
              // bridge when the phone is on the Mac's hotspot).
              defaultValue: 'http://192.168.1.221:8081',
            ),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// Every request fails fast instead of hanging the splash screen (or
  /// any other flow) when the server is unreachable — e.g. the dev Mac's
  /// Wi-Fi IP changed and the baked-in API_BASE is stale. 10s is generous
  /// on LAN, and callers already degrade (offline banner, FX fallback).
  static const _timeout = Duration(seconds: 10);

  Future<http.Response> _get(Uri url) =>
      _client.get(url).timeout(_timeout);
  Future<http.Response> _post(Uri url,
          {Map<String, String>? headers, Object? body}) =>
      _client.post(url, headers: headers, body: body).timeout(_timeout);
  Future<http.Response> _put(Uri url,
          {Map<String, String>? headers, Object? body}) =>
      _client.put(url, headers: headers, body: body).timeout(_timeout);
  Future<http.Response> _delete(Uri url) =>
      _client.delete(url).timeout(_timeout);

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<HandleAvailability> checkHandleAvailability(String base) async {
    final res =
        await _get(_uri('/handles/availability', {'base': base}));
    return HandleAvailability.fromJson(_decode(res));
  }

  /// Live FX quote — single source of truth (see `routes/fx.rs`).
  /// Falls back to the static constants on any failure; callers must
  /// still show "updated Xm ago" from the returned timestamp.
  Future<FxRate> getFxRate() async {
    final res = await _get(_uri('/fx/rate'));
    return FxRate.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<Wallet> createWallet({
    required String evmAddress,
    required String handleBase,
    required List<String> guardians,
    required String pinHash,
    String? deviceKeyPub,
    bool deviceEnclave = false,
  }) async {
    final res = await _post(
      _uri('/wallets'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'evm_address': evmAddress,
        'handle_base': handleBase,
        'guardians': guardians,
        'pin_hash': pinHash,
        if (deviceKeyPub != null) 'device_key_pub': deviceKeyPub,
        'device_enclave': deviceEnclave,
      }),
    );
    return Wallet.fromJson(_decode(res));
  }

  /// Rotates the wallet's device key after wallet-PIN proof. Revokes every
  /// escrowed backup server-side (v1 whole-key QRs included) — the caller
  /// must prompt a fresh v2 export afterwards and, where the smart account
  /// is live, point its owner at the new address. Throws [ApiException]
  /// (401 wrong PIN, 404 unknown wallet, 409 address taken).
  Future<Wallet> rotateWalletKey({
    required String walletId,
    required String newEvmAddress,
    required String pinHash,
    String? deviceKeyPub,
    bool deviceEnclave = false,
  }) async {
    final res = await _post(
      _uri('/wallets/$walletId/rotate-key'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'new_evm_address': newEvmAddress,
        'pin_hash': pinHash,
        if (deviceKeyPub != null) 'device_key_pub': deviceKeyPub,
        'device_enclave': deviceEnclave,
      }),
    );
    return Wallet.fromJson(_decode(res));
  }

  /// The second factor in "restore from wallet key" — see
  /// `RestoreFromKeyScreen`. Throws [ApiException] (401) on a wrong PIN,
  /// (404) if no wallet is registered under the given address at all.
  Future<PinVerification> verifyPin(
      {required String evmAddress, required String pinHash}) async {
    final res = await _post(
      _uri('/wallets/verify-pin'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'evm_address': evmAddress, 'pin_hash': pinHash}),
    );
    return PinVerification.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<Wallet> getWallet(String id) async {
    final res = await _get(_uri('/wallets/$id'));
    return Wallet.fromJson(_decode(res));
  }

  /// Stores the server-side share (`S2`) of a v2 split backup. Called once,
  /// during export, before the QR is ever shown — if this fails, there is
  /// no restorable backup, so callers must fail the export, not show the QR.
  Future<void> storeBackupShare(
      {required String walletId,
      required String backupId,
      required String s2Hex}) async {
    final res = await _post(
      _uri('/wallets/$walletId/backups'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'backup_id': backupId, 's2_hex': s2Hex}),
    );
    _decode(res);
  }

  /// Release-oracle call for v2 restores: proves wallet-PIN knowledge and,
  /// on success, returns the server-held share `S2`. Throws [ApiException]
  /// (401 wrong PIN, 423 locked after too many attempts, 410 revoked).
  ///
  /// Legacy path — only for backups with no OPAQUE password file. New
  /// backups authenticate via the OPAQUE login endpoints below; the server
  /// answers 409 for those here.
  Future<String> releaseBackupShare(
      {required String backupId, required String pinHash}) async {
    final res = await _post(
      _uri('/backups/$backupId/release'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'pin_hash': pinHash}),
    );
    final body = _decode(res) as Map<String, dynamic>;
    return body['s2_hex'] as String;
  }

  /// Registers an APNs/FCM device token for remote push. Best-effort by
  /// contract — callers (PushService) swallow all errors.
  Future<void> registerPushToken(
      {required String walletId,
      required String token,
      String platform = 'ios'}) async {
    final res = await _post(
      _uri('/wallets/$walletId/push-tokens'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token, 'platform': platform}),
    );
    _decode(res);
  }

  /// OPAQUE registration step 1 (export): turns the blinded request into a
  /// server response. Returns `response_b64`.
  Future<String> opaqueRegisterStart(
      {required String walletId,
      required String backupId,
      required String requestB64}) async {
    final res = await _post(
      _uri('/wallets/$walletId/backups/opaque/register/start'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'backup_id': backupId, 'request_b64': requestB64}),
    );
    return (_decode(res) as Map<String, dynamic>)['response_b64'] as String;
  }

  /// OPAQUE registration step 2 (export): stores the password file.
  Future<void> opaqueRegisterFinish(
      {required String walletId,
      required String backupId,
      required String uploadB64}) async {
    final res = await _post(
      _uri('/wallets/$walletId/backups/opaque/register/finish'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'backup_id': backupId, 'upload_b64': uploadB64}),
    );
    _decode(res);
  }

  /// OPAQUE login step 1 (restore): opens a pending login, returns
  /// `(loginId, responseB64)`. Throws 404 when the backup predates OPAQUE
  /// (caller falls back to [releaseBackupShare]).
  Future<(String, String)> opaqueLoginStart(
      {required String backupId, required String requestB64}) async {
    final res = await _post(
      _uri('/backups/$backupId/opaque/login/start'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'request_b64': requestB64}),
    );
    final body = _decode(res) as Map<String, dynamic>;
    return (
      body['login_id'] as String,
      body['response_b64'] as String,
    );
  }

  /// OPAQUE login step 2 (restore): verifies the finalization, returns
  /// `s2_hex` on success. Same 401/423/410 semantics as [releaseBackupShare].
  Future<String> opaqueLoginFinish(
      {required String backupId,
      required String loginId,
      required String finalizationB64}) async {
    final res = await _post(
      _uri('/backups/$backupId/opaque/login/finish'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'login_id': loginId, 'finalization_b64': finalizationB64}),
    );
    return (_decode(res) as Map<String, dynamic>)['s2_hex'] as String;
  }

  Future<List<Transaction>> listTransactions(String walletId) async {
    final res = await _get(_uri('/wallets/$walletId/transactions'));
    final body = _decode(res);
    final list =
        body is List ? body : (body['transactions'] as List? ?? const []);
    return list
        .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The Send screen's real backend — debits `walletId`'s everyday balance
  /// (amount + flat fee), credits the recipient, and returns the sender's
  /// updated balance. Throws [ApiException] with the server's message on
  /// insufficient balance, an unknown recipient, or a self-send attempt.
  /// `idempotencyKey` is a client UUID per review-sheet confirmation —
  /// same key returns the original result instead of double-sending.
  Future<double> transfer({
    required String walletId,
    required String recipientFullHandle,
    required int amountUsdCents,
    String? idempotencyKey,
  }) async {
    final res = await _post(
      _uri('/wallets/$walletId/transfers'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'recipient_full_handle': recipientFullHandle,
        'amount_usd_cents': amountUsdCents,
        if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
          'idempotency_key': idempotencyKey,
      }),
    );
    final body = _decode(res) as Map<String, dynamic>;
    return (body['sender_everyday_balance_usd_cents'] as num) / 100;
  }

  /// Real backend for the Cash-out flow — see `CashOutScreen`/
  /// `WalletStore.cashOut`. Throws [ApiException] on insufficient
  /// balance or an invalid number.
  Future<CashOutResult> cashOut({
    required String walletId,
    required String mpesaNumber,
    required int amountUsdCents,
    String? idempotencyKey,
  }) async {
    final res = await _post(
      _uri('/wallets/$walletId/cash-out'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'mpesa_number': mpesaNumber,
        'amount_usd_cents': amountUsdCents,
        if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
          'idempotency_key': idempotencyKey,
      }),
    );
    return CashOutResult.fromJson(_decode(res) as Map<String, dynamic>);
  }

  /// Real backend for the Contacts screen. Throws [ApiException] (404) if
  /// a `handle`-kind entry doesn't resolve to a real registered wallet.
  Future<Contact> createContact({
    required String walletId,
    required String name,
    required ContactKind kind,
    required String value,
  }) async {
    final res = await _post(
      _uri('/wallets/$walletId/contacts'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'name': name, 'contact_kind': kind.name, 'contact_value': value}),
    );
    return Contact.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<List<Contact>> listContacts(String walletId) async {
    final res = await _get(_uri('/wallets/$walletId/contacts'));
    final body = _decode(res) as List;
    return body
        .map((e) => Contact.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteContact(
      {required String walletId, required String contactId}) async {
    final res =
        await _delete(_uri('/wallets/$walletId/contacts/$contactId'));
    _decode(res);
  }

  /// Real backend for Groups/Chamas — see `crates/server/src/routes/groups.rs`.
  Future<Group> createGroup({
    required String ownerWalletId,
    required String name,
    required GroupKind kind,
    required GroupPowerScheme powerScheme,
    required List<String> memberContactIds,
  }) async {
    final res = await _post(
      _uri('/groups'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'owner_wallet_id': ownerWalletId,
        'name': name,
        'kind': kind.name,
        'power_scheme': powerScheme.name,
        'member_contact_ids': memberContactIds,
      }),
    );
    return Group.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<List<Group>> listGroups(String walletId) async {
    final res = await _get(_uri('/wallets/$walletId/groups'));
    final body = _decode(res) as List;
    return body.map((e) => Group.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Group> getGroup(String groupId) async {
    final res = await _get(_uri('/groups/$groupId'));
    return Group.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<Group> contributeToGroup(
      {required String groupId,
      required String walletId,
      required int amountUsdCents}) async {
    final res = await _post(
      _uri('/groups/$groupId/contribute'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'wallet_id': walletId, 'amount_usd_cents': amountUsdCents}),
    );
    return Group.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<GroupWithdrawal> openWithdrawal(
      {required String groupId,
      required int amountUsdCents,
      required String payeeName}) async {
    final res = await _post(
      _uri('/groups/$groupId/withdrawals'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'amount_usd_cents': amountUsdCents, 'payee_name': payeeName}),
    );
    return GroupWithdrawal.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<GroupWithdrawal> getWithdrawal(
      {required String groupId, required String requestId}) async {
    final res =
        await _get(_uri('/groups/$groupId/withdrawals/$requestId'));
    return GroupWithdrawal.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<GroupWithdrawal> castVote({
    required String groupId,
    required String requestId,
    required String memberId,
    required VoteChoice choice,
  }) async {
    final res = await _post(
      _uri('/groups/$groupId/withdrawals/$requestId/vote'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'member_id': memberId, 'choice': choice.name}),
    );
    return GroupWithdrawal.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<GroupWithdrawal> executeWithdrawal(
      {required String groupId, required String requestId}) async {
    final res = await _client
        .post(_uri('/groups/$groupId/withdrawals/$requestId/execute'));
    return GroupWithdrawal.fromJson(_decode(res) as Map<String, dynamic>);
  }

  /// Opens an invite to add someone as a group member — either an
  /// existing Contacts entry (`contactId`) or anyone by payment handle
  /// (`handle`), contact or not. Exactly one of the two should be set.
  /// Same tally, same `/withdrawals/:id/{vote,execute}` endpoints as a
  /// money withdrawal once accepted. See `GroupProposalAction`.
  Future<GroupWithdrawal> proposeAddMember(
      {required String groupId, String? contactId, String? handle}) async {
    assert(contactId != null || handle != null);
    final res = await _post(
      _uri('/groups/$groupId/proposals/add-member'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (contactId != null) 'contact_id': contactId,
        if (handle != null) 'handle': handle
      }),
    );
    return GroupWithdrawal.fromJson(_decode(res) as Map<String, dynamic>);
  }

  /// Real backend for the 66-char chat feature — see
  /// `crates/server/src/routes/messages.rs`.
  Future<ChatMessage> sendGroupMessage({
    required String groupId,
    required String senderWalletId,
    required String body,
    String? replyToId,
  }) async {
    final res = await _post(
      _uri('/groups/$groupId/messages'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sender_wallet_id': senderWalletId,
        'body': body,
        if (replyToId != null) 'reply_to_id': replyToId
      }),
    );
    return ChatMessage.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<List<ChatMessage>> listGroupMessages(String groupId) async {
    final res = await _get(_uri('/groups/$groupId/messages'));
    final body = _decode(res) as List;
    return body
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> sendDirectMessage({
    required String walletId,
    required String otherWalletId,
    required String body,
    String? replyToId,
  }) async {
    final res = await _post(
      _uri('/wallets/$walletId/messages/direct/$otherWalletId'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sender_wallet_id': walletId,
        'body': body,
        if (replyToId != null) 'reply_to_id': replyToId
      }),
    );
    return ChatMessage.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<List<ChatMessage>> listDirectMessages(
      {required String walletId, required String otherWalletId}) async {
    final res = await _client
        .get(_uri('/wallets/$walletId/messages/direct/$otherWalletId'));
    final body = _decode(res) as List;
    return body
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Prompts `phone` to pay via M-Pesa STK Push — see
  /// `routes/mpesa.rs::initiate_stk_push`. Returns immediately with a
  /// tracking id; poll [pollMpesaDeposit] for the real result once the
  /// person enters their PIN on their phone.
  Future<MpesaStkPushResult> initiateMpesaStkPush(
      {required String walletId,
      required String phone,
      required int amountUsdCents,
      String? idempotencyKey}) async {
    final res = await _post(
      _uri('/wallets/$walletId/mpesa/stk-push'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'amount_usd_cents': amountUsdCents,
        if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
          'idempotency_key': idempotencyKey,
      }),
    );
    return MpesaStkPushResult.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<MpesaDepositStatus> pollMpesaDeposit(
      {required String walletId, required String checkoutRequestId}) async {
    final res = await _client
        .get(_uri('/wallets/$walletId/mpesa/deposits/$checkoutRequestId'));
    return MpesaDepositStatus.fromJson(_decode(res) as Map<String, dynamic>);
  }

  /// Opens a Stripe Checkout session for a card top-up (credit/debit/
  /// prepaid/virtual — see `routes/card_topup.rs`). Returns a URL to
  /// launch in the browser; poll [pollCardTopup] for the real result
  /// once the person completes (or abandons) payment on Stripe's page.
  Future<CardTopupCheckout> createCardTopupCheckout(
      {required String walletId, required int amountUsdCents}) async {
    final res = await _post(
      _uri('/wallets/$walletId/topup/card/checkout'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'amount_usd_cents': amountUsdCents}),
    );
    return CardTopupCheckout.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<CardTopupStatus> pollCardTopup(
      {required String walletId, required String topupId}) async {
    final res =
        await _get(_uri('/wallets/$walletId/topup/card/$topupId'));
    return CardTopupStatus.fromJson(_decode(res) as Map<String, dynamic>);
  }

  /// The inbox's data source — every direct/group thread this wallet is
  /// party to, newest first. See `list_conversations`.
  Future<List<Conversation>> listConversations(String walletId) async {
    final res = await _get(_uri('/wallets/$walletId/conversations'));
    final body = _decode(res) as List;
    return body
        .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setMessagePinned(
      {required String messageId, required bool pinned}) async {
    final res = await _post(
      _uri('/messages/$messageId/pin'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'pinned': pinned}),
    );
    _decode(res);
  }

  /// Whether the invitee accepts or declines an `add_member` proposal —
  /// only the invited wallet may call this. See `respond_to_invite`.
  Future<void> respondToInvite(
      {required String groupId,
      required String requestId,
      required String walletId,
      required bool accept}) async {
    final res = await _post(
      _uri('/groups/$groupId/invites/$requestId/respond'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'wallet_id': walletId, 'accept': accept}),
    );
    _decode(res);
  }

  Future<List<GroupInvite>> listInvites(String walletId) async {
    final res = await _get(_uri('/wallets/$walletId/invites'));
    final body = _decode(res) as List;
    return body
        .map((e) => GroupInvite.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Real backend for "Move to savings" / "Withdraw from savings" — see
  /// `routes/wallets.rs`'s `move_to_savings`/`withdraw_from_savings`.
  Future<SavingsTransferResult> moveToSavings(
      {required String walletId, required int amountUsdCents}) async {
    final res = await _post(
      _uri('/wallets/$walletId/savings/move'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'amount_usd_cents': amountUsdCents}),
    );
    return SavingsTransferResult.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<SavingsTransferResult> withdrawFromSavings(
      {required String walletId, required int amountUsdCents}) async {
    final res = await _post(
      _uri('/wallets/$walletId/savings/withdraw'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'amount_usd_cents': amountUsdCents}),
    );
    return SavingsTransferResult.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<GroupWithdrawal> proposeRemoveMember(
      {required String groupId, required String memberId}) async {
    final res = await _post(
      _uri('/groups/$groupId/proposals/remove-member'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'member_id': memberId}),
    );
    return GroupWithdrawal.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<double> broadcastToGroup({
    required String groupId,
    required String senderWalletId,
    required int amountPerMemberUsdCents,
    required List<String> memberWalletIds,
  }) async {
    final res = await _post(
      _uri('/groups/$groupId/broadcast'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sender_wallet_id': senderWalletId,
        'amount_per_member_usd_cents': amountPerMemberUsdCents,
        'member_wallet_ids': memberWalletIds,
      }),
    );
    final body = _decode(res) as Map<String, dynamic>;
    return (body['sender_everyday_balance_usd_cents'] as num) / 100;
  }

  /// Real backend for send-to-non-user — see
  /// `crates/server/src/routes/escrow.rs`. `claimCode` on the response is
  /// only ever present here, right after creation.
  Future<EscrowClaim> createEscrow({
    required String walletId,
    required String recipientAddr,
    required String recipientKind,
    required int amountUsdCents,
  }) async {
    final res = await _post(
      _uri('/wallets/$walletId/escrow'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'recipient_addr': recipientAddr,
        'recipient_kind': recipientKind,
        'amount_usd_cents': amountUsdCents
      }),
    );
    return EscrowClaim.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<List<EscrowClaim>> listEscrow(String walletId) async {
    final res = await _get(_uri('/wallets/$walletId/escrow'));
    final body = _decode(res) as List;
    return body
        .map((e) => EscrowClaim.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> cancelEscrow(
      {required String walletId, required String claimId}) async {
    final res =
        await _post(_uri('/wallets/$walletId/escrow/$claimId/cancel'));
    _decode(res);
  }

  Future<List<AlertPreference>> getAlertPreferences(String walletId) async {
    final res = await _get(_uri('/wallets/$walletId/alert-preferences'));
    final body = _decode(res) as List;
    return body
        .map((e) => AlertPreference.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Throws [ApiException] (400) if `preferences` includes
  /// `recovery_started` — the server refuses that edit outright.
  Future<List<AlertPreference>> updateAlertPreferences(
      String walletId, List<AlertPreference> preferences) async {
    final res = await _put(
      _uri('/wallets/$walletId/alert-preferences'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'preferences': preferences.map((p) => p.toJson()).toList()}),
    );
    final body = _decode(res) as List;
    return body
        .map((e) => AlertPreference.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Feeds the Notifications screen — see `NotificationsScreen`.
  Future<List<RecoverySummary>> listRecovery(String walletId) async {
    final res = await _get(_uri('/wallets/$walletId/recovery'));
    final body = _decode(res) as List;
    return body
        .map((e) => RecoverySummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RecoveryStatus> startRecovery(
      {required String fullHandle, bool reportedStolen = false}) async {
    final res = await _post(
      _uri('/recovery'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'full_handle': fullHandle, 'reported_stolen': reportedStolen}),
    );
    return RecoveryStatus.fromJson(_decode(res));
  }

  Future<RecoveryStatus> getRecovery(String id) async {
    final res = await _get(_uri('/recovery/$id'));
    return RecoveryStatus.fromJson(_decode(res));
  }

  Future<RecoveryStatus> approveRecovery(String id, String guardianType) async {
    final res = await _post(
      _uri('/recovery/$id/approvals'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'guardian_type': guardianType}),
    );
    return RecoveryStatus.fromJson(_decode(res));
  }

  Future<RecoveryStatus> cancelRecovery(String id) async {
    final res = await _post(_uri('/recovery/$id/cancel'));
    return RecoveryStatus.fromJson(_decode(res));
  }

  dynamic _decode(http.Response res) {
    final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = body is Map<String, dynamic>
          ? (body['error'] as String? ?? res.body)
          : res.body;
      throw ApiException(res.statusCode, message);
    }
    return body;
  }
}

/// Mirrors `GET /fx/rate` — see `crates/server/src/routes/fx.rs`.
/// Same constants the app used to hardcode, now served with a timestamp
/// so every review sheet can show "updated Xm ago" and freeze the quote.
class FxRate {
  const FxRate({
    required this.rate,
    required this.spread,
    required this.effectiveCashoutRate,
    required this.handleFeeUsdCents,
    required this.escrowFeeUsdCents,
    required this.updatedAt,
  });

  final double rate;
  final double spread;
  final double effectiveCashoutRate;
  final int handleFeeUsdCents;
  final int escrowFeeUsdCents;
  final DateTime updatedAt;

  factory FxRate.fromJson(Map<String, dynamic> json) => FxRate(
        rate: (json['rate'] as num).toDouble(),
        spread: (json['spread'] as num).toDouble(),
        effectiveCashoutRate:
            (json['effective_cashout_rate'] as num).toDouble(),
        handleFeeUsdCents: (json['handle_fee_usd_cents'] as num).toInt(),
        escrowFeeUsdCents: (json['escrow_fee_usd_cents'] as num).toInt(),
        updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      );

  factory FxRate.fallback() => FxRate(
        rate: 129.25,
        spread: 0.008,
        effectiveCashoutRate: 129.25 * (1 - 0.008),
        handleFeeUsdCents: 4,
        escrowFeeUsdCents: 9,
        updatedAt: DateTime.now(),
      );
}
