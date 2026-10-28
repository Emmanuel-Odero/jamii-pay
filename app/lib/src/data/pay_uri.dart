/// The `jamiipay://pay/<fullHandle>` deep link — same scheme
/// `ReceiveScreen` already encodes into its QR (`data:
/// 'jamiipay://pay/$fullHandle'`), extended here with an optional
/// `?amount=` query param so a receiver can request a specific amount
/// without the sender having to type it in after scanning.
///
/// Also accepts universal links `https://jamiipay.com/pay/<handle>` and
/// `https://claim.jamiipay.com/<code>` path forms so QRs scanned from the
/// system camera / shared links open the app instead of failing.
class ParsedPayUri {
  const ParsedPayUri(
      {required this.fullHandle, this.amountUsd, this.amountTampered = false});

  final String fullHandle;

  /// Present only when the QR was generated with a requested amount (see
  /// `ReceiveScreen`'s "Request an amount" field). `null` means the
  /// sender picks how much to pay after scanning.
  final double? amountUsd;

  /// True when `?amount=` was present but unparseable — the UI must warn
  /// ("amount looked tampered, please confirm") rather than silently
  /// dropping it as before.
  final bool amountTampered;
}

/// Returns `null` for anything that isn't a well-formed
/// `jamiipay://pay/...` link or `https://jamiipay.com/pay/...` universal
/// link — a scanned code from some other app/QR (a URL, a WiFi config,
/// a boarding pass) should fail closed, not throw or half-parse into
/// garbage. Callers must surface "Not a JamiiPay code" instead of doing
/// nothing (the old silent-ignore made the camera look broken).
ParsedPayUri? parsePayUri(String raw) {
  final trimmed = raw.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  // Custom scheme.
  if (uri.scheme == 'jamiipay' && uri.host == 'pay') {
    return _fromParts(uri.pathSegments, uri.queryParameters['amount']);
  }
  // Universal links: https://jamiipay.com/pay/<handle>?amount=.. and
  // https://claim.jamiipay.com/<code> is handled by the claim page, not here.
  if ((uri.scheme == 'https' || uri.scheme == 'http') &&
      (uri.host == 'jamiipay.com' || uri.host == 'www.jamiipay.com') &&
      uri.pathSegments.length >= 2 &&
      uri.pathSegments[0] == 'pay') {
    return _fromParts(
        uri.pathSegments.sublist(1), uri.queryParameters['amount']);
  }
  return null;
}

ParsedPayUri? _fromParts(List<String> segments, String? amountParam) {
  if (segments.isEmpty || segments.first.isEmpty) return null;
  final fullHandle = segments.first.trim().toLowerCase();

  final amountUsd =
      amountParam == null ? null : double.tryParse(amountParam.trim());
  final tampered = amountParam != null &&
      (amountUsd == null || amountUsd <= 0 || amountUsd > 1000000);
  // A present-but-unparseable `amount` (corrupted/tampered QR) is treated
  // as absent for value purposes BUT flagged so the UI can warn.

  return ParsedPayUri(
      fullHandle: fullHandle,
      amountUsd: amountUsd != null && amountUsd > 0 ? amountUsd : null,
      amountTampered: tampered);
}

/// Builds the QR payload — the inverse of [parsePayUri]. `amountUsd` is
/// omitted from the URI entirely when null, so an un-amounted QR stays
/// byte-identical to what `ReceiveScreen` always generated.
String buildPayUri(String fullHandle, {double? amountUsd}) {
  final clean = fullHandle.trim().toLowerCase();
  if (amountUsd == null || amountUsd <= 0) return 'jamiipay://pay/$clean';
  return 'jamiipay://pay/$clean?amount=${amountUsd.toStringAsFixed(2)}';
}

/// Universal-link form for sharing outside the app (system camera,
/// WhatsApp, SMS): `https://jamiipay.com/pay/<handle>?amount=..`.
String buildUniversalPayLink(String fullHandle, {double? amountUsd}) {
  final clean = fullHandle.trim().toLowerCase();
  if (amountUsd == null || amountUsd <= 0) {
    return 'https://jamiipay.com/pay/$clean';
  }
  return 'https://jamiipay.com/pay/$clean?amount=${amountUsd.toStringAsFixed(2)}';
}
