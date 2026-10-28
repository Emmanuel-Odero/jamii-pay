// One-off verification script (not part of the app) — renders a real QR
// code image the same way `WalletKeyBackupScreen` does (via the `qr`
// package that `qr_flutter` wraps) and decodes it back with the exact
// `decodeQrFromImageBytes` function `RestoreUploadScreen` uses. This is
// the one link in the "upload the key, unlock it" chain that unit tests
// can't cover on their own (image rendering + a real barcode decode),
// since the cryptography itself is already covered by
// `crates/wallet-core/src/api.rs`'s `restore_from_key_tests`.
//
// Run with: dart run tool/verify_qr_roundtrip.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

import '../lib/src/data/qr_image_decoder.dart';
import '../lib/src/data/wallet_key_backup_codec.dart';
import '../lib/src/bridge/api.dart' show EncryptedKeyBackup;

/// Renders a `qr` package `QrCode` to PNG bytes — the pure-Dart
/// equivalent of what `qr_flutter`'s `CustomPainter` draws to a Flutter
/// canvas, since this script has no Flutter widget tree to paint into.
Uint8List renderQrToPng(String data, {int errorCorrectLevel = QrErrorCorrectLevel.H, int scale = 8, int margin = 4}) {
  final qrCode = QrCode.fromData(data: data, errorCorrectLevel: errorCorrectLevel);
  final qrImage = QrImage(qrCode);
  final moduleCount = qrImage.moduleCount;
  final size = (moduleCount + margin * 2) * scale;

  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));

  for (var row = 0; row < moduleCount; row++) {
    for (var col = 0; col < moduleCount; col++) {
      if (qrImage.isDark(row, col)) {
        final x0 = (col + margin) * scale;
        final y0 = (row + margin) * scale;
        img.fillRect(image, x1: x0, y1: y0, x2: x0 + scale - 1, y2: y0 + scale - 1, color: img.ColorRgb8(0, 0, 0));
      }
    }
  }

  return Uint8List.fromList(img.encodePng(image));
}

Future<void> main() async {
  var failures = 0;
  void check(String label, bool ok) {
    print('${ok ? "✓" : "✗ FAIL"}  $label');
    if (!ok) failures++;
  }

  // Fabricated but shape-correct backup — the point here is exercising
  // the QR render→photo→decode→JSON-parse pipeline, not the crypto
  // (which `restore_from_key_tests` already covers in Rust).
  const backup = EncryptedKeyBackup(
    addressHex: '0x1234567890abcdef1234567890abcdef12345678',
    saltHex: 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4',
    nonceHex: 'aabbccddeeff001122334455',
    ciphertextHex: '9f8e7d6c5b4a39281706f5e4d3c2b1a0f1e2d3c4b5a69788',
  );

  final payload = WalletKeyBackupCodec.encode(backup);
  print('Encoded payload (${payload.length} bytes): $payload');

  // Render at a size representative of what a phone screenshot/share
  // would actually produce (matches `WalletKeyBackupScreen`'s 190x190
  // logical card scaled up), then write it to disk so it can be inspected
  // manually too.
  final pngBytes = renderQrToPng(payload);
  final outFile = await File('/tmp/verify_qr_roundtrip.png').writeAsBytes(pngBytes);
  print('Wrote rendered QR to ${outFile.path} (${pngBytes.length} bytes)');

  final decoded = decodeQrFromImageBytes(pngBytes);
  check('QR image decodes to a non-null string', decoded != null);
  check('Decoded string matches the original payload exactly', decoded == payload);

  if (decoded != null) {
    try {
      final roundTripped = WalletKeyBackupCodec.decode(decoded);
      check('address_hex round-trips', roundTripped.addressHex == backup.addressHex);
      check('salt_hex round-trips', roundTripped.saltHex == backup.saltHex);
      check('nonce_hex round-trips', roundTripped.nonceHex == backup.nonceHex);
      check('ciphertext_hex round-trips', roundTripped.ciphertextHex == backup.ciphertextHex);
    } catch (e) {
      check('WalletKeyBackupCodec.decode did not throw', false);
      print('  error: $e');
    }
  }

  // Also confirm a photo of *something else* is correctly rejected,
  // matching `RestoreUploadScreen`'s "Couldn't find a QR code" path.
  final blankImage = img.Image(width: 200, height: 200);
  img.fill(blankImage, color: img.ColorRgb8(255, 255, 255));
  final blankPng = Uint8List.fromList(img.encodePng(blankImage));
  check('A blank image correctly decodes to null (no QR found)', decodeQrFromImageBytes(blankPng) == null);

  print('');
  if (failures == 0) {
    print('All checks passed — the QR render → decode → JSON-parse pipeline is sound.');
  } else {
    print('$failures check(s) FAILED.');
    exit(1);
  }
}
