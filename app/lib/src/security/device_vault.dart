import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hardware-bound wrapping for the session private key — the Dart half of
/// the native DeviceVault (iOS Secure Enclave, Android StrongBox/TEE).
///
/// Contract, both platforms: `generateKey` creates (or returns) a
/// non-exportable P-256 device key and reports whether it is hardware
/// backed; `wrap` ECIES-encrypts small blobs to it; `unwrap` decrypts.
/// The wrapped private key in the Keychain is ciphertext: extraction
/// requires the physical secure element that wrapped it.
///
/// Every method is best-effort and returns null when the platform side is
/// missing (web/desktop builds, unit tests) — callers fall back to the
/// previous Keychain-direct storage and record `hardwareBacked: false`,
/// never crash. The fallback is explicit in the stored flag and reported
/// to the server at wallet creation, so policy can distinguish the two.
class DeviceVault {
  const DeviceVault._();

  static const _channel = MethodChannel('jamiipay/device_vault');

  /// Ensures the device key exists. Returns `(publicKeyBase64,
  /// hardwareBacked)`, or null when the vault is unavailable.
  static Future<({String publicKeyBase64, bool hardwareBacked})?>
      ensureKey() async {
    try {
      final m =
          await _channel.invokeMapMethod<String, dynamic>('generateKey');
      if (m == null) return null;
      final pubKey = m['publicKeyBase64'];
      if (pubKey is! String || pubKey.isEmpty) return null;
      final backed = m['enclave'];
      return (
        publicKeyBase64: pubKey,
        hardwareBacked: backed is bool ? backed : false,
      );
    } on PlatformException catch (e) {
      debugPrint('DeviceVault.ensureKey unavailable: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Wraps `plaintext` (base64) to the device key. Returns the blob
  /// (base64), or null when unavailable.
  static Future<String?> wrap(String dataBase64) async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>(
          'wrap', {'dataBase64': dataBase64});
      final blob = m?['blobBase64'];
      return blob is String && blob.isNotEmpty ? blob : null;
    } on PlatformException catch (e) {
      debugPrint('DeviceVault.wrap failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Unwraps a blob produced by [wrap]. Returns the plaintext (base64), or
  /// null when unavailable or when the device key is gone (new device,
  /// wiped keychain — restore from backup instead).
  static Future<String?> unwrap(String blobBase64) async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>(
          'unwrap', {'blobBase64': blobBase64});
      final data = m?['dataBase64'];
      return data is String && data.isNotEmpty ? data : null;
    } on PlatformException catch (e) {
      debugPrint('DeviceVault.unwrap failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Helpers for the hex private keys this app stores.
  static Future<String?> wrapHex(String hexKey) async {
    final bytes = _hexToBytes(hexKey);
    if (bytes == null) return null;
    return wrap(base64Encode(bytes));
  }

  static Future<String?> unwrapHex(String blobBase64) async {
    final b64 = await unwrap(blobBase64);
    if (b64 == null) return null;
    try {
      return _bytesToHex(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  static List<int>? _hexToBytes(String hex) {
    if (hex.length.isOdd) return null;
    try {
      return List.generate(
          hex.length ~/ 2,
          (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16));
    } catch (_) {
      return null;
    }
  }

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
