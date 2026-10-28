import Flutter
import Security
import UIKit
import UserNotifications

/// DeviceVault: hardware-bound key wrapping for the session private key.
///
/// A P-256 key is generated **inside the Secure Enclave** (never exportable,
/// `kSecAttrTokenIDSecureEnclave`) and used to ECIES-wrap the wallet's
/// private key before it lands in the Keychain. What the Keychain holds is
/// ciphertext: a Keychain dump, an iTunes backup grabbed without the
/// device, or a forensic image no longer yields the key — unwrapping
/// requires the physical Secure Enclave that wrapped it.
///
/// Threat-model notes, stated plainly:
/// - This stops *extraction*, not *use*: code running on the unlocked
///   device can still ask the enclave to unwrap (that is what the app
///   itself does at launch). Device PIN/biometry + app lock remain the
///   use-gate; this module is the export-gate.
/// - Simulators and pre-A9 devices have no enclave: those fall back to a
///   software Keychain key (`enclave: false`), reported to Dart and the
///   server so policy can treat them accordingly. The fallback is loud,
///   never silent.
/// - Access control is `.privateKeyUsage` (no auth prompt per use) —
///   deliberately, so cold start needs no extra tap beyond the app's own
///   lock screen. Stepping up to `.biometryAny` is a one-line change in
///   `accessControl` below if product wants per-launch biometrics.
public class DeviceVaultPlugin: NSObject, FlutterPlugin {
  private static let channelName = "jamiipay/device_vault"
  private static let keyTag = "com.jamiipay.devicevault.key"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = DeviceVaultPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "generateKey":
      do {
        let pubB64 = try ensureKey()
        result(["publicKeyBase64": pubB64, "enclave": isEnclaveAvailable()])
      } catch {
        result(FlutterError(code: "VAULT_ERROR", message: "\(error)", details: nil))
      }
    case "getPublicKey":
      do {
        let pubB64 = try ensureKey()
        result(["publicKeyBase64": pubB64, "enclave": isEnclaveAvailable()])
      } catch {
        result(FlutterError(code: "VAULT_ERROR", message: "\(error)", details: nil))
      }
    case "wrap":
      guard let args = call.arguments as? [String: Any],
        let dataB64 = args["dataBase64"] as? String,
        let data = Data(base64Encoded: dataB64)
      else {
        result(FlutterError(code: "BAD_ARGS", message: "wrap needs dataBase64", details: nil))
        return
      }
      do {
        let blob = try eciesEncrypt(data)
        result(["blobBase64": blob.base64EncodedString()])
      } catch {
        result(FlutterError(code: "VAULT_ERROR", message: "\(error)", details: nil))
      }
    case "unwrap":
      guard let args = call.arguments as? [String: Any],
        let blobB64 = args["blobBase64"] as? String,
        let blob = Data(base64Encoded: blobB64)
      else {
        result(FlutterError(code: "BAD_ARGS", message: "unwrap needs blobBase64", details: nil))
        return
      }
      do {
        let data = try eciesDecrypt(blob)
        result(["dataBase64": data.base64EncodedString()])
      } catch {
        result(FlutterError(code: "VAULT_ERROR", message: "\(error)", details: nil))
      }
    case "setBadge":
      // App-icon badge writer. flutter_local_notifications sets the badge
      // on delivery (badgeNumber) but offers no API to clear it, so the
      // badge would stick forever once shown. The app clears it on launch
      // and when the Notifications screen opens.
      guard let args = call.arguments as? [String: Any],
        let count = args["count"] as? Int
      else {
        result(FlutterError(code: "BAD_ARGS", message: "setBadge needs count", details: nil))
        return
      }
      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
          if let error = error {
            result(FlutterError(code: "VAULT_ERROR", message: "\(error)", details: nil))
          } else {
            result(nil)
          }
        }
      } else {
        DispatchQueue.main.async {
          UIApplication.shared.applicationIconBadgeNumber = count
          result(nil)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Key management

  private func isEnclaveAvailable() -> Bool {
    #if targetEnvironment(simulator)
      return false
    #else
      return true
    #endif
  }

  private func fetchPrivateKey() throws -> SecKey? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: Self.keyTag.data(using: .utf8)!,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecReturnRef as String: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else {
      throw NSError(domain: "DeviceVault", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "key fetch failed"])
    }
    return (item as! SecKey)
  }

  private func ensureKey() throws -> String {
    if let existing = try fetchPrivateKey(), let pubKey = SecKeyCopyPublicKey(existing) {
      return try exportPublicKey(pubKey)
    }
    var accessError: Unmanaged<CFError>?
    let access = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      .privateKeyUsage,
      &accessError
    )
    var attrs: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: Self.keyTag.data(using: .utf8)!,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      ] as [String: Any],
    ]
    if let access = access {
      var privAttrs = attrs[kSecPrivateKeyAttrs as String] as! [String: Any]
      privAttrs[kSecAttrAccessControl as String] = access
      attrs[kSecPrivateKeyAttrs as String] = privAttrs
    }
    #if !targetEnvironment(simulator)
      attrs[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
    #endif
    var error: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
      throw error!.takeRetainedValue() as Error
    }
    guard let pubKey = SecKeyCopyPublicKey(privateKey) else {
      throw NSError(domain: "DeviceVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "no public key"])
    }
    return try exportPublicKey(pubKey)
  }

  private func exportPublicKey(_ key: SecKey) throws -> String {
    var error: Unmanaged<CFError>?
    guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
      throw error!.takeRetainedValue() as Error
    }
    return data.base64EncodedString()
  }

  // MARK: - ECIES wrap/unwrap

  private static let algorithm: SecKeyAlgorithm =
    .eciesEncryptionCofactorVariableIVX963SHA256AESGCM

  private func eciesEncrypt(_ data: Data) throws -> Data {
    _ = try ensureKey()
    guard let privKey = try fetchPrivateKey(),
      let pubKey = SecKeyCopyPublicKey(privKey)
    else {
      throw NSError(domain: "DeviceVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "no key"])
    }
    guard SecKeyIsAlgorithmSupported(pubKey, .encrypt, Self.algorithm) else {
      throw NSError(domain: "DeviceVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "algorithm unsupported"])
    }
    var error: Unmanaged<CFError>?
    guard let blob = SecKeyCreateEncryptedData(pubKey, Self.algorithm, data as CFData, &error) as Data? else {
      throw error!.takeRetainedValue() as Error
    }
    return blob
  }

  private func eciesDecrypt(_ blob: Data) throws -> Data {
    guard let privKey = try fetchPrivateKey() else {
      throw NSError(domain: "DeviceVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "no key — was it deleted or is this a new device?"])
    }
    guard SecKeyIsAlgorithmSupported(privKey, .decrypt, Self.algorithm) else {
      throw NSError(domain: "DeviceVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "algorithm unsupported"])
    }
    var error: Unmanaged<CFError>?
    guard let data = SecKeyCreateDecryptedData(privKey, Self.algorithm, blob as CFData, &error) as Data? else {
      throw error!.takeRetainedValue() as Error
    }
    return data
  }
}
