import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// System-level alerts (banner + sound, on the lock screen and in
/// Notification Center) for events the in-app Notifications screen
/// already tracks but that a person shouldn't have to have the app open
/// to notice — a new chat message, money arriving.
///
/// **Scope, stated plainly:** this is *local* notification only —
/// scheduled entirely on-device by [WalletStore]'s own polling
/// (`_pollConversations`) and its live-balance WebSocket. It fires
/// while the app is running, foregrounded or backgrounded. It does
/// **not** fire once the app has been fully force-quit or the phone
/// rebooted — that needs real remote push (Apple Push Notification
/// service), which requires an Apple Developer Program account, a push
/// certificate/key, and a server-side sender; a materially bigger,
/// credential-gated project on top of this, not a small addition.
abstract final class LocalNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static int _nextId = 0;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _plugin.initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  /// Current iOS permission state, for the Settings diagnostics row.
  /// Null when the platform side has no answer (non-Apple builds).
  static Future<NotificationsEnabledOptions?> checkPermissions() async {
    final impl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (impl == null) return null;
    return impl.checkPermissions();
  }

  static Future<void> show(
      {required String title, required String body, int? badgeCount}) async {
    if (!_initialized) {
      debugPrint('LocalNotifications.show before init — dropped: $title');
      return; // init() failing/not-yet-run shouldn't crash a caller
    }
    try {
      await _plugin.show(
        _nextId++,
        title,
        body,
        NotificationDetails(
          iOS: DarwinNotificationDetails(
            // Legacy `presentAlert` alone is not enough on iOS 14+:
            // foreground banners need `presentBanner` + `presentList`
            // explicitly, otherwise a foregrounded app stays silent.
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentBadge: true,
            presentSound: true,
            // The app-icon badge is set ONLY here — nothing else in the
            // app writes it, which is why it never appeared before.
            badgeNumber: badgeCount,
          ),
          android: const AndroidNotificationDetails(
              'jamiipay_default', 'JamiiPay',
              importance: Importance.high, priority: Priority.high),
        ),
      );
    } catch (e) {
      // Never crash a money/message flow over a banner — but never vanish
      // silently either: without this log, a failing plugin looks exactly
      // like "notifications don't work" with nothing to grep for.
      debugPrint('LocalNotifications.show failed: $e');
    }
  }
}
