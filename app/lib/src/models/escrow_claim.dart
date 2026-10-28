/// Mirrors `crates/server`'s `EscrowResponse` — see
/// `crates/server/src/routes/escrow.rs`.
class EscrowClaim {
  const EscrowClaim({
    required this.id,
    required this.recipientAddr,
    required this.recipientKind,
    required this.amountUsdCents,
    required this.status,
    required this.expiresAt,
    this.claimCode,
  });

  final String id;
  final String recipientAddr;
  final String recipientKind; // phone | email
  final int amountUsdCents;
  final String status; // pending | claimed | expired | cancelled
  final DateTime expiresAt;

  /// Only ever set on the response to creating a claim — the shareable
  /// `claim.jamiipay.com/<code>` link is built from this, once.
  final String? claimCode;

  double get amountUsd => amountUsdCents / 100;
  Duration get timeLeft => expiresAt.difference(DateTime.now());

  factory EscrowClaim.fromJson(Map<String, dynamic> json) {
    return EscrowClaim(
      id: json['id'] as String,
      recipientAddr: json['recipient_addr'] as String,
      recipientKind: json['recipient_kind'] as String,
      amountUsdCents: (json['amount_usd_cents'] as num).toInt(),
      status: json['status'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
      claimCode: json['claim_code'] as String?,
    );
  }
}
