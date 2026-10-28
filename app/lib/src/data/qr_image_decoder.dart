import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing_lib/common.dart';
import 'package:zxing_lib/qrcode.dart';
import 'package:zxing_lib/zxing.dart';

/// Decodes a QR code from a still image file's bytes — used by
/// `RestoreUploadScreen` to read the wallet-key backup image someone
/// downloaded from `WalletKeyBackupScreen`.
///
/// Deliberately a pure-Dart decoder (`zxing_lib`) rather than a native
/// ML-Kit-backed plugin: this only ever needs to read one still image a
/// user picks from their Photos library, never a live camera feed, so the
/// native plugin's main advantage (fast frame-by-frame scanning) buys
/// nothing here — and it costs a real native-build dependency (CocoaPods,
/// per-platform architecture support) for a one-shot decode. Returns
/// `null` if no QR code is found in the image.
String? decodeQrFromImageBytes(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;

  // Downsize very large photos (a full-resolution Photos screenshot can
  // be 3000px+ per side) — decoding is O(width*height), and a QR's own
  // modules are coarse enough that this doesn't hurt recognition.
  final decoded =
      image.width > 1200 ? img.copyResize(image, width: 1200) : image;

  final pixels = List<int>.generate(decoded.width * decoded.height, (i) {
    final x = i % decoded.width;
    final y = i ~/ decoded.width;
    final pixel = decoded.getPixel(x, y);
    return (0xFF << 24) |
        (pixel.r.toInt() << 16) |
        (pixel.g.toInt() << 8) |
        pixel.b.toInt();
  }, growable: false);

  final source = RGBLuminanceSource(decoded.width, decoded.height, pixels);
  final bitmap = BinaryBitmap(HybridBinarizer(source));
  try {
    return QRCodeReader().decode(bitmap).text;
  } catch (_) {
    return null;
  }
}
