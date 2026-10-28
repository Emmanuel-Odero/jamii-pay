import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Local view model backing [TxRow] and the activity feed. Built from
/// `GET /wallets/:id/transactions` via [Transaction.fromJson] — the
/// glyph/colour fields are a presentation mapping over the server's
/// `kind`/`direction`, not stored server-side.
class Transaction {
  const Transaction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amountUsd,
    required this.glyph,
    required this.glyphBackground,
    required this.glyphColor,
    required this.createdAt,
    this.amountLocal,
    this.fxRate,
    this.pending = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final double amountUsd;
  final String? amountLocal;
  /// Raw server `fx_rate` (e.g. "128.240000 KES/$") — shown verbatim on
  /// the receipt sheet so users can audit the spread.
  final String? fxRate;
  final IconData glyph;
  final Color glyphBackground;
  final Color glyphColor;
  final bool pending;
  final DateTime createdAt;

  /// Maps the server's `{id, direction, counterparty_name, amount_usd_cents,
  /// amount_local_minor, local_currency, fx_rate, kind, status, created_at}`
  /// shape onto the display model above.
  factory Transaction.fromJson(Map<String, dynamic> json) {
    final direction = json['direction'] as String; // "in" | "out"
    final kind =
        json['kind'] as String; // transfer | cash_out | bill_pay | airtime
    final status = json['status'] as String; // pending | settled | failed
    final counterparty = json['counterparty_name'] as String?;
    final amountUsdCents = (json['amount_usd_cents'] as num).toInt();
    final amountUsd = amountUsdCents / 100 * (direction == 'out' ? -1 : 1);

    final localMinor = json['amount_local_minor'] as num?;
    final localCurrency = json['local_currency'] as String?;
    final fxRate = json['fx_rate'] as String?;
    final amountLocal = localMinor != null && localCurrency != null
        ? '$localCurrency ${_formatLocal(localMinor.toInt())}'
        : null;

    final createdAt = DateTime.parse(json['created_at'] as String).toLocal();
    final time = '${_two(createdAt.hour)}:${_two(createdAt.minute)}';
    final subtitle = fxRate != null && direction == 'in'
        ? '$time · $fxRate ${localCurrency ?? ''}/\$'
        : time;

    final (glyph, bg, color) = _presentation(kind: kind, direction: direction);

    return Transaction(
      id: json['id'] as String,
      title:
          _title(kind: kind, direction: direction, counterparty: counterparty),
      subtitle: subtitle,
      amountUsd: amountUsd,
      amountLocal: amountLocal,
      fxRate: fxRate,
      glyph: glyph,
      glyphBackground: bg,
      glyphColor: color,
      pending: status == 'pending',
      createdAt: createdAt,
    );
  }

  static String _title(
      {required String kind, required String direction, String? counterparty}) {
    switch (kind) {
      case 'cash_out':
        return 'Cash out to M-Pesa';
      case 'bill_pay':
        return counterparty ?? 'Bill payment';
      case 'airtime':
        return 'Airtime top-up';
      default:
        if (counterparty == null)
          return direction == 'in' ? 'Received' : 'Sent';
        return direction == 'in' ? 'From $counterparty' : 'To $counterparty';
    }
  }

  static (IconData, Color, Color) _presentation(
      {required String kind, required String direction}) {
    if (kind == 'cash_out')
      return (
        Icons.sync_alt,
        AppColors.amber.withValues(alpha: 0.18),
        AppColors.amber
      );
    if (kind == 'bill_pay')
      return (
        Icons.receipt_long_outlined,
        AppColors.blue.withValues(alpha: 0.18),
        AppColors.blue
      );
    if (direction == 'in')
      return (
        Icons.arrow_downward,
        AppColors.green.withValues(alpha: 0.18),
        AppColors.green
      );
    return (
      Icons.arrow_upward,
      AppColors.blue.withValues(alpha: 0.18),
      AppColors.blue
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _formatLocal(int minorUnits) {
    final whole = minorUnits ~/ 100;
    final s = whole.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
