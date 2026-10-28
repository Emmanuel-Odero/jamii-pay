import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/api_client.dart';

/// Remote-push registration and tap routing — the Dart half of the native
/// push plumbing (iOS `PushPlugin`, server `crates/server/src/push.rs`).
///
/// Flow: every wallet-active launch calls [syncWallet], which asks iOS for
/// the APNs device token (permission prompt included) and uploads it —
/// re-upload each launch, because reinstalls rotate tokens and the old row
/// only dies when Apple 410s it. Taps (terminated-launch or suspended)
/// route to the Notifications screen via [onNotificationTap], bound by
/// `WalletFlow` (the only place that owns that navigation).
///
/// All methods are best-effort and swallow platform/network errors: push
/// is a bonus over local notifications, never a gate. Non-iOS builds
/// (simulator without push, Android until FCM lands, tests) simply no-op.
class PushService {
  const PushService._();

  static const _channel = MethodChannel('jamiipay/push');
  static bool _tapHandlerSet = false;
  static String? _syncedKey;

  /// Binds tap routing. Called once from `WalletFlow.initState`, cleared
  /// on dispose. Also drains a launch payload if the app started from a
  /// push tap — the caller opens Notifications when it returns true.
  static void bindTapHandler(Future<void> Function() onTap) {
    if (!_tapHandlerSet) {
      _tapHandlerSet = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onNotificationOpened') {
          await onTap();
        }
      });
    }
  }

  /// Reads and clears the launch payload, if any. Returns its `type`
  /// (`balance`, `message`, `recovery`) or null.
  static Future<String?> drainLaunchType() async {
    try {
      final m =
          await _channel.invokeMapMethod<String, dynamic>('getLaunchNotification');
      final type = m?['type'];
      return type is String ? type : (m == null ? null : 'unknown');
    } on PlatformException catch (e) {
      debugPrint('PushService.drainLaunchType: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Registers this device for the wallet and uploads the token.
  /// Deduplicated per (wallet, token) pair per process life — safe to call
  /// from every initState without spamming the server.
  static Future<void> syncWallet(String? walletId, JamiiPayApiClient api) async {
    if (walletId == null || walletId.isEmpty) return;
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('register');
      final token = m?['token'];
      if (token is! String || token.isEmpty) return;
      final key = '$walletId:$token';
      if (key == _syncedKey) return;
      await api.registerPushToken(walletId: walletId, token: token);
      _syncedKey = key;
    } on PlatformException catch (e) {
      debugPrint('PushService.syncWallet unavailable: ${e.message}');
    } on MissingPluginException {
      // Simulator without push / tests.
    } catch (e) {
      // Network or server error — next launch retries. Never surfaces:
      // push registration must not interrupt a wallet session.
      debugPrint('PushService.syncWallet failed: $e');
    }
  }
}
