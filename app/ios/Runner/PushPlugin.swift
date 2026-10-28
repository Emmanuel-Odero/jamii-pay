import Flutter
import UIKit
import UserNotifications

/// Remote-push registration and launch-payload plumbing (Apple Push
/// Notification service). The server-side sender lives in
/// `crates/server/src/push.rs`; this file is the device half.
///
/// Responsibilities, deliberately narrow:
/// - `register`: asks the user for alert/badge/sound permission, then
///   registers with APNs. Resolves `{token, granted}` — the Dart side
///   uploads `token` to the server on every launch (tokens rotate on
///   reinstall). Rejected/failed registration resolves
///   `{token: null, granted: false}`, never an error: pushes are a
///   bonus, local notifications keep working regardless.
/// - `getLaunchNotification`: returns the push payload that launched (or
///   woked) the app, once, then clears it. Dart routes it (Notifications
///   screen) on startup.
/// - Foreground remote banners are intentionally NOT handled here: while
///   the app is foregrounded, the live socket + poller already raise
///   *local* banners with fresher state. Taking over
///   `UNUserNotificationCenter.delegate` would break those — so this
///   plugin leaves the notification-center delegate alone and only uses
///   the `UIApplicationDelegate` remote callbacks.
///
/// Taps while suspended come through
/// `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
/// (forwarded by AppDelegate): the payload is stashed and, if Dart is
/// listening, forwarded immediately via `onNotificationOpened`.
public class PushPlugin: NSObject, FlutterPlugin {
  private static let channelName = "jamiipay/push"
  private static var shared: PushPlugin?

  private var channel: FlutterMethodChannel?
  private var pendingResult: FlutterResult?
  private var launchPayload: [String: Any]?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = PushPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    shared = instance
  }

  public static func handleLaunchOptions(_ launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
    if let remote = launchOptions?[.remoteNotification] as? [String: Any] {
      shared?.launchPayload = remote
    }
  }

  public static func didRegisterForRemoteNotifications(deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    shared?.pendingResult?(["token": token, "granted": true])
    shared?.pendingResult = nil
  }

  public static func didFailToRegister(error: Error) {
    shared?.pendingResult?(["token": nil, "granted": false])
    shared?.pendingResult = nil
  }

  public static func didReceiveRemoteNotification(userInfo: [String: Any]) {
    shared?.launchPayload = userInfo
    shared?.channel?.invokeMethod("onNotificationOpened", arguments: userInfo)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "register":
      requestAuthorization(result: result)
    case "getLaunchNotification":
      if let payload = launchPayload {
        launchPayload = nil
        result(payload)
      } else {
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestAuthorization(result: @escaping FlutterResult) {
    // One pending registration at a time — a second tap while the system
    // sheet is up just reuses the first answer.
    if pendingResult != nil { return }
    pendingResult = result
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
      guard granted else {
        DispatchQueue.main.async {
          self.pendingResult?(["token": nil, "granted": false])
          self.pendingResult = nil
        }
        return
      }
      DispatchQueue.main.async {
        UIApplication.shared.registerForRemoteNotifications()
      }
      // Resolution happens in didRegister/didFail above. If the device
      // has no APNs route (simulator, airplane mode), neither fires —
      // the 15s watchdog below fails closed instead of hanging Dart.
      DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
        if self.pendingResult != nil {
          self.pendingResult?(["token": nil, "granted": false])
          self.pendingResult = nil
        }
      }
    }
  }
}
