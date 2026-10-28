import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App-icon badge writer. The notification plugin sets the badge when a
/// banner is delivered (`badgeNumber`) but offers no API to change it
/// afterwards — without this, the badge would stick forever once shown.
/// Served by the native DeviceVault channel (`setBadge`); Android is a
/// deliberate no-op (dots are automatic there).
class DeviceBadge {
  const DeviceBadge._();

  static const _channel = MethodChannel('jamiipay/device_vault');

  static Future<void> set(int count) async {
    try {
      await _channel.invokeMethod('setBadge', {'count': count});
    } on PlatformException catch (e) {
      debugPrint('DeviceBadge.set failed: ${e.message}');
    } on MissingPluginException {
      // Web/desktop/test — no icon badge exists.
    }
  }

  static Future<void> clear() => set(0);
}
