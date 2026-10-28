import 'dart:convert';

import '../bridge/api.dart' as bridge;

/// QR payload formats for wallet-key backups.
///
/// - **v2 (current):** a split-share envelope. The QR holds only an
///   Argon2id-wrapped random share `S1` plus the `backup_id`; the
///   complementary share `S2` lives on the server release oracle. `S1`
///   alone is uniformly random — brute-forcing the QR's PIN yields nothing
///   usable. Restores complete only via app + server together.
/// - **v1 (legacy, decode-only):** the whole key under PBKDF2-100k. Still
///   decodable so already-printed backups keep working, but new exports
///   must never produce it — it falls to offline brute force in minutes.
///
/// Short keys keep the encoded string small enough that the QR stays at a
/// low-ish version even with error-correction level H (needed to survive
/// the logo medallion — see `WalletKeyBackupScreen`).
class WalletKeyBackupCodec {
  const WalletKeyBackupCodec._();

  static const v1 = 1;
  static const v2 = 2;

  static String encode(bridge.EncryptedKeyBackup backup) {
    return jsonEncode({
      'v': v1,
      'addr': backup.addressHex,
      's': backup.saltHex,
      'n': backup.nonceHex,
      'c': backup.ciphertextHex,
    });
  }

  /// `qrPayload` is the v2 envelope JSON produced by
  /// `createSplitBackup` — embedded verbatim, already versioned.
  static String encodeV2(String qrPayload) => qrPayload;

  /// Identifies a scanned QR without starting a restore: version, address,
  /// and (v2) backup id. Throws [FormatException] for non-backup QRs.
  /// v1 and v2 both inspect cleanly — support for old backups starts here.
  static BackupInfo inspect(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('That QR code is not a JamiiPay wallet key.');
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('That QR code is not a JamiiPay wallet key.');
    }
    final version = json['v'];
    if (version == v2 &&
        json['id'] is String &&
        json['addr'] is String &&
        json['s'] is String &&
        json['n'] is String &&
        json['c'] is String) {
      return BackupInfo(
        version: v2,
        addressHex: json['addr'] as String,
        backupId: json['id'] as String,
      );
    }
    if (version == v1 &&
        json['addr'] is String &&
        json['s'] is String &&
        json['n'] is String &&
        json['c'] is String) {
      return BackupInfo(version: v1, addressHex: json['addr'] as String);
    }
    throw const FormatException('That QR code is not a JamiiPay wallet key.');
  }

  /// Throws [FormatException] on anything that isn't a wallet-key backup
  /// payload — a photo of something else, a stale/foreign QR code, etc.
  static bridge.EncryptedKeyBackup decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('That QR code is not a JamiiPay wallet key.');
    }
    if (json is! Map<String, dynamic> ||
        json['v'] != v1 ||
        json['addr'] is! String ||
        json['s'] is! String ||
        json['n'] is! String ||
        json['c'] is! String) {
      if (json is Map<String, dynamic> && json['v'] == v2) {
        throw const FormatException(
            'That is a newer split backup — update the app to restore it.');
      }
      throw const FormatException('That QR code is not a JamiiPay wallet key.');
    }
    return bridge.EncryptedKeyBackup(
      addressHex: json['addr'] as String,
      saltHex: json['s'] as String,
      nonceHex: json['n'] as String,
      ciphertextHex: json['c'] as String,
    );
  }
}

/// What a scanned QR *is*, without committing to a restore path.
/// Used by the upload screen and support flows to identify a backup before
/// any PIN is asked for: version, wallet address, and (v2 only) backup id.
class BackupInfo {
  const BackupInfo({
    required this.version,
    required this.addressHex,
    this.backupId,
  });

  /// 1 = legacy whole-key envelope, 2 = split-share envelope.
  final int version;
  final String addressHex;

  /// v2 only — the server-side identity of this backup (release oracle +
  /// revocation). Null for v1, which predates server registration.
  final String? backupId;

  bool get isLegacy => version == WalletKeyBackupCodec.v1;

  /// Human label for cards, banners, and support: `v2 split backup`,
  /// `v1 legacy backup`.
  String get label =>
      isLegacy ? 'v1 legacy backup' : 'v2 split backup';
}

/// A decoded v2 split envelope — the QR-side half of a restore.
class SplitBackupEnvelope {
  const SplitBackupEnvelope({
    required this.backupId,
    required this.addressHex,
    required this.saltHex,
    required this.nonceHex,
    required this.ciphertextHex,
  });

  final String backupId;
  final String addressHex;
  final String saltHex;
  final String nonceHex;
  final String ciphertextHex;

  /// Throws [FormatException] unless `raw` is a v2 envelope.
  static SplitBackupEnvelope decodeV2(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('That QR code is not a JamiiPay wallet key.');
    }
    if (json is! Map<String, dynamic> ||
        json['v'] != WalletKeyBackupCodec.v2 ||
        json['id'] is! String ||
        json['addr'] is! String ||
        json['s'] is! String ||
        json['n'] is! String ||
        json['c'] is! String) {
      throw const FormatException('That QR code is not a JamiiPay wallet key.');
    }
    return SplitBackupEnvelope(
      backupId: json['id'] as String,
      addressHex: json['addr'] as String,
      saltHex: json['s'] as String,
      nonceHex: json['n'] as String,
      ciphertextHex: json['c'] as String,
    );
  }
}
