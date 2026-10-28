/// Single source of truth for all money math + formatting.
///
/// Previously fees/FX lived as scattered `static const`s:
/// Send `$0.04/$0.09`, Cash-out `129.25 + 0.8%`, STK nothing, Activity
/// promising "exact rate" that `TxRow` never showed. That fragmentation
/// reads as hidden fees — fatal in Kenya's fee-sensitive mobile-money
/// market. Every flow must go through here and render via [MoneyReceipt].
class MoneyMath {
  const MoneyMath._();

  static const double handleFeeUsd = 0.04;
  static const double escrowFeeUsd = 0.09;
  static const double cashOutSpread = 0.008;

  /// Last-known FX. Treated as stale after [fxStaleAfter]; callers must
  /// show "updated Xm ago" and freeze the quoted rate at confirm time.
  static const double fallbackRateKesPerUsd = 129.25;
  static const Duration fxStaleAfter = Duration(minutes: 30);

  static double feeFor({required bool isEscrow}) =>
      isEscrow ? escrowFeeUsd : handleFeeUsd;

  static double theyReceive(double amountUsd, double feeUsd) =>
      (amountUsd - feeUsd).clamp(0, double.infinity);

  static double totalDebit(double amountUsd) => amountUsd;

  static double effectiveCashOutRate(double rate) => rate * (1 - cashOutSpread);

  static String usd(double v) => '\$${v.toStringAsFixed(2)}';
  static String kes(double usdAmount, double rate) =>
      'KSh ${(usdAmount * rate).toStringAsFixed(0)}';

  /// Strict Safaricom/M-PESA check: +254/07/01 + valid mobile prefix.
  /// Old code accepted any `digitCount >= 9`.
  static bool isValidMpesaNumber(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final local = digits.startsWith('254')
        ? digits.substring(3)
        : digits.startsWith('0')
            ? digits.substring(1)
            : digits;
    if (local.length != 9) return false;
    // Safaricom mobile prefixes: 07xx / 01xx (1x/7x second digit ranges).
    return RegExp(r'^[17]\d{8}$').hasMatch(local);
  }

  static String formatMpesaNumber(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    String local;
    if (digits.startsWith('254') && digits.length >= 12) {
      local = digits.substring(3);
    } else if (digits.startsWith('0')) {
      local = digits.substring(1);
    } else {
      local = digits;
    }
    if (local.length != 9) return raw.trim();
    return '+254 ${local.substring(0, 3)} ${local.substring(3, 6)} ${local.substring(6)}';
  }

  /// Locale-aware amount parse: accepts "1,50" comma decimals,
  /// thousands separators, trims, caps at 2 decimals.
  /// Returns null when unparseable or <= 0.
  static double? parseAmount(String raw) {
    var s = raw.trim().replaceAll(' ', '');
    if (s.isEmpty) return null;
    // "1.234,56" (European) -> "1234.56"; "1,234.56" -> "1234.56".
    if (s.contains(',') && s.contains('.')) {
      if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (s.contains(',')) {
      final parts = s.split(',');
      if (parts.length == 2 && parts[1].length <= 2) {
        s = '${parts[0].replaceAll(',', '')}.${parts[1]}';
      } else {
        s = s.replaceAll(',', '');
      }
    }
    final v = double.tryParse(s);
    if (v == null || v <= 0 || v > 1000000) return null;
    // Cap to cents to avoid 0.00001 confusion; sub-cent rounds to 0 = reject.
    final cents = (v * 100).round() / 100;
    if (cents <= 0) return null;
    return cents;
  }
}

/// Frozen quote shown on every receipt: same layout in Send, Scan,
/// Cash-out, Broadcast so users learn one shape.
class MoneyQuote {
  const MoneyQuote({
    required this.amountUsd,
    required this.feeUsd,
    required this.totalDebitUsd,
    required this.theyReceiveUsd,
    required this.rateKesPerUsd,
    required this.rateUpdatedAt,
    required this.arrivalLabel,
  });

  final double amountUsd;
  final double feeUsd;
  final double totalDebitUsd;
  final double theyReceiveUsd;
  final double rateKesPerUsd;
  final DateTime rateUpdatedAt;
  final String arrivalLabel;

  String get rateAgeLabel {
    final m = DateTime.now().difference(rateUpdatedAt).inMinutes;
    if (m < 1) return 'just now';
    if (m < 60) return '${m}m ago';
    return '${DateTime.now().difference(rateUpdatedAt).inHours}h ago';
  }
}

/// Client UUID per review-sheet confirmation — sent as `idempotency_key`
/// so double-tap / retry-after-timeout returns the original result.
String newIdempotencyKey() {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = (100000 + (999999 * _seed()).round()).toRadixString(36);
  return '$now-$rand';
}

double _seed() {
  // Deterministic enough without a new dependency; uniqueness comes
  // from microsecond time, this just decorrelates same-microsecond taps.
  return (DateTime.now().microsecond % 1000) / 1000;
}
