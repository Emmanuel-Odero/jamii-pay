/// Mirrors `crates/server`'s `WalletResponse` — see
/// `crates/server/src/routes/wallets.rs`.
class Wallet {
  const Wallet({
    required this.id,
    required this.evmAddress,
    required this.fullHandle,
    required this.everydayBalanceUsdCents,
    required this.savingsBalanceUsdCents,
    required this.guardians,
  });

  final String id;
  final String evmAddress;
  final String fullHandle;
  final int everydayBalanceUsdCents;
  final int savingsBalanceUsdCents;
  final List<String> guardians;

  double get everydayBalanceUsd => everydayBalanceUsdCents / 100;
  double get savingsBalanceUsd => savingsBalanceUsdCents / 100;

  String get handleBase => fullHandle.substring(0, fullHandle.length - 1);
  String get handleCheckDigit => fullHandle.substring(fullHandle.length - 1);

  Wallet copyWith(
          {int? everydayBalanceUsdCents, int? savingsBalanceUsdCents}) =>
      Wallet(
        id: id,
        evmAddress: evmAddress,
        fullHandle: fullHandle,
        everydayBalanceUsdCents:
            everydayBalanceUsdCents ?? this.everydayBalanceUsdCents,
        savingsBalanceUsdCents:
            savingsBalanceUsdCents ?? this.savingsBalanceUsdCents,
        guardians: guardians,
      );

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      id: json['id'] as String,
      evmAddress: json['evm_address'] as String,
      fullHandle: json['full_handle'] as String,
      everydayBalanceUsdCents:
          (json['everyday_balance_usd_cents'] as num).toInt(),
      savingsBalanceUsdCents:
          (json['savings_balance_usd_cents'] as num).toInt(),
      guardians: (json['guardians'] as List).cast<String>(),
    );
  }
}

/// Mirrors `POST /wallets/:id/savings/{move,withdraw}`'s response.
class SavingsTransferResult {
  const SavingsTransferResult(
      {required this.everydayBalanceUsd, required this.savingsBalanceUsd});
  final double everydayBalanceUsd;
  final double savingsBalanceUsd;

  factory SavingsTransferResult.fromJson(Map<String, dynamic> json) =>
      SavingsTransferResult(
        everydayBalanceUsd: (json['everyday_balance_usd_cents'] as num) / 100,
        savingsBalanceUsd: (json['savings_balance_usd_cents'] as num) / 100,
      );
}

/// Mirrors `POST /wallets/:id/mpesa/stk-push`'s response.
class MpesaStkPushResult {
  const MpesaStkPushResult(
      {required this.checkoutRequestId, required this.amountKes});
  final String checkoutRequestId;
  final double amountKes;

  factory MpesaStkPushResult.fromJson(Map<String, dynamic> json) =>
      MpesaStkPushResult(
          checkoutRequestId: json['checkout_request_id'] as String,
          amountKes: (json['amount_kes'] as num).toDouble());
}

/// Mirrors `GET /wallets/:id/mpesa/deposits/:id`'s response.
class MpesaDepositStatus {
  const MpesaDepositStatus(
      {required this.status,
      required this.resultDesc,
      required this.everydayBalanceUsdCents});
  final String status; // pending | completed | failed
  final String? resultDesc;
  final int? everydayBalanceUsdCents;

  factory MpesaDepositStatus.fromJson(Map<String, dynamic> json) =>
      MpesaDepositStatus(
        status: json['status'] as String,
        resultDesc: json['result_desc'] as String?,
        everydayBalanceUsdCents:
            (json['everyday_balance_usd_cents'] as num?)?.toInt(),
      );
}

/// Mirrors `POST /wallets/:id/topup/card/checkout`'s response.
class CardTopupCheckout {
  const CardTopupCheckout({required this.checkoutUrl, required this.topupId});
  final String checkoutUrl;
  final String topupId;

  factory CardTopupCheckout.fromJson(Map<String, dynamic> json) =>
      CardTopupCheckout(
          checkoutUrl: json['checkout_url'] as String,
          topupId: json['topup_id'] as String);
}

/// Mirrors `GET /wallets/:id/topup/card/:id`'s response.
class CardTopupStatus {
  const CardTopupStatus(
      {required this.status, required this.everydayBalanceUsdCents});
  final String status; // pending | completed | failed
  final int? everydayBalanceUsdCents;

  factory CardTopupStatus.fromJson(Map<String, dynamic> json) =>
      CardTopupStatus(
        status: json['status'] as String,
        everydayBalanceUsdCents:
            (json['everyday_balance_usd_cents'] as num?)?.toInt(),
      );
}

/// Mirrors `POST /wallets/:id/cash-out`'s response.
class CashOutResult {
  const CashOutResult(
      {required this.everydayBalanceUsd,
      required this.amountKes,
      required this.rate});

  final double everydayBalanceUsd;
  final double amountKes;
  final double rate;

  factory CashOutResult.fromJson(Map<String, dynamic> json) {
    return CashOutResult(
      everydayBalanceUsd: (json['everyday_balance_usd_cents'] as num) / 100,
      amountKes: (json['amount_kes_minor'] as num) / 100,
      rate: (json['rate'] as num).toDouble(),
    );
  }
}

/// Mirrors `GET /wallets/:id/recovery`'s `RecoverySummary` — see
/// `crates/server/src/routes/recovery.rs`. Feeds the Notifications
/// screen's "recovery started" entries.
class RecoverySummary {
  const RecoverySummary(
      {required this.id, required this.status, required this.startedAt});

  final String id;
  final String status;
  final DateTime startedAt;

  factory RecoverySummary.fromJson(Map<String, dynamic> json) {
    return RecoverySummary(
      id: json['id'] as String,
      status: json['status'] as String,
      startedAt: DateTime.parse(json['started_at'] as String).toLocal(),
    );
  }
}

/// Material for one v2 split backup: `qrPayload` is the only thing ever
/// embedded in the QR image (PIN-wrapped random share `S1` + `backupId`);
/// `s2Hex` is uploaded to the server release oracle at export time and
/// must never be written into the QR, a screenshot, or a log.
class SplitBackupMaterial {
  const SplitBackupMaterial({
    required this.backupId,
    required this.qrPayload,
    required this.s2Hex,
    required this.addressHex,
  });

  final String backupId;
  final String qrPayload;
  final String s2Hex;
  final String addressHex;
}

/// Mirrors `POST /wallets/verify-pin`'s response — just enough to load
/// the matched wallet by id in `RestoreFromKeyScreen`.
class PinVerification {
  const PinVerification({required this.id, required this.fullHandle});

  final String id;
  final String fullHandle;

  factory PinVerification.fromJson(Map<String, dynamic> json) {
    return PinVerification(
        id: json['id'] as String, fullHandle: json['full_handle'] as String);
  }
}

/// Mirrors `GET /handles/availability`'s response.
class HandleAvailability {
  const HandleAvailability(
      {required this.available,
      this.fullHandle,
      this.checkDigit,
      this.suggestions = const []});

  final bool available;
  final String? fullHandle;
  final String? checkDigit;
  final List<String> suggestions;

  factory HandleAvailability.fromJson(Map<String, dynamic> json) {
    return HandleAvailability(
      available: json['available'] as bool,
      fullHandle: json['full_handle'] as String?,
      checkDigit: json['check_digit'] as String?,
      suggestions: (json['suggestions'] as List? ?? const []).cast<String>(),
    );
  }
}

/// Mirrors `crates/server`'s `RecoveryResponse`.
class RecoveryStatus {
  const RecoveryStatus({
    required this.id,
    required this.status,
    required this.threshold,
    required this.approvals,
    required this.guardians,
    required this.startedAt,
    this.waitCompletesAt,
  });

  final String id;
  final String status; // pending_approvals | waiting | completed | cancelled
  final int threshold;
  final List<String> approvals;

  /// The wallet's configured guardian types — sourced from the server, not
  /// a local `Wallet` object, because the device running recovery may have
  /// no session at all (that's the point: it's how you get back in without
  /// one).
  final List<String> guardians;
  final DateTime startedAt;
  final DateTime? waitCompletesAt;

  factory RecoveryStatus.fromJson(Map<String, dynamic> json) {
    return RecoveryStatus(
      id: json['id'] as String,
      status: json['status'] as String,
      threshold: (json['threshold'] as num).toInt(),
      approvals: (json['approvals'] as List).cast<String>(),
      guardians: (json['guardians'] as List? ?? const []).cast<String>(),
      startedAt: DateTime.parse(json['started_at'] as String),
      waitCompletesAt: json['wait_completes_at'] == null
          ? null
          : DateTime.parse(json['wait_completes_at'] as String),
    );
  }
}
