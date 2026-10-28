import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../security/device_vault.dart';

/// Everything a device needs to remember between launches so the app can
/// skip onboarding and reload the same wallet: the wallet id (server-side
/// identity), the raw private key (never leaves the Keychain in plaintext
/// once written), and the app-lock state (PIN hash + whether biometric
/// unlock is enabled). Nothing here is synced anywhere — losing the device
/// without a recovery guardian set up loses the wallet, by design.
///
/// Since the DeviceVault upgrade, the private key is ECIES-wrapped by a
/// hardware-bound device key (Secure Enclave / StrongBox) before Keychain
/// storage whenever the vault is available — the Keychain then holds
/// ciphertext, and extraction requires the physical secure element. Keys
/// written before the upgrade stay plaintext-readable (flag absent) and
/// are transparently re-wrapped on the next save.
class SessionStorage {
  const SessionStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _walletIdKey = 'jamiipay.wallet_id';
  static const _privateKeyKey = 'jamiipay.private_key_hex';
  /// '1' when [_privateKeyKey] holds a DeviceVault blob instead of raw hex.
  /// Absent (pre-upgrade keys) means raw hex — still readable, re-wrapped
  /// on the next save.
  static const _privateKeyVaultKey = 'jamiipay.private_key_vaulted';
  static const _pinHashKey = 'jamiipay.pin_hash';
  static const _biometricEnabledKey = 'jamiipay.biometric_enabled';
  static const _hideSavingsEnabledKey = 'jamiipay.hide_savings_enabled';
  static const _hideSavingsActionKey = 'jamiipay.hide_savings_action';
  static const _hideSavingsCountKey = 'jamiipay.hide_savings_count';
  static const _hideSavingsRevealSecsKey = 'jamiipay.hide_savings_reveal_secs';
  static const _hideSavingsPhraseHashKey = 'jamiipay.hide_savings_phrase_hash';
  static const _languageKey = 'jamiipay.language';
  static const _onboardingStepKey = 'jamiipay.onboarding_step';
  static const _fxRateKey = 'jamiipay.fx_rate';
  static const _fxUpdatedAtKey = 'jamiipay.fx_updated_at';

  Future<String?> readWalletId() => _storage.read(key: _walletIdKey);

  /// Reads the session private key, unwrapping through the DeviceVault
  /// when it was stored wrapped. Throws [StateError] when a wrapped key
  /// cannot be unwrapped (device key gone — restore from backup instead
  /// of silently returning nothing).
  ///
  /// Only ever read for two things: signing (once that's wired up) and
  /// the "Download wallet key" export flow — which immediately hands it
  /// to `wallet-core` and never holds it in a Dart variable longer than
  /// that call needs.
  Future<String?> readPrivateKeyHex() async {
    final stored = await _storage.read(key: _privateKeyKey);
    if (stored == null) return null;
    final vaulted = await _storage.read(key: _privateKeyVaultKey);
    if (vaulted != '1') return stored;
    final hex = await DeviceVault.unwrapHex(stored);
    if (hex == null) {
      throw StateError(
          'device vault unavailable — restore this wallet from its backup');
    }
    return hex;
  }

  Future<void> saveSession(
      {required String walletId, required String privateKeyHex}) async {
    await _storage.write(key: _walletIdKey, value: walletId);
    // Wrap before storing whenever the vault answers; otherwise keep the
    // previous plaintext behavior (flag cleared) rather than failing the
    // save — availability first, hardening best-effort.
    final blob = await DeviceVault.wrapHex(privateKeyHex);
    if (blob != null) {
      await _storage.write(key: _privateKeyKey, value: blob);
      await _storage.write(key: _privateKeyVaultKey, value: '1');
    } else {
      await _storage.write(key: _privateKeyKey, value: privateKeyHex);
      await _storage.delete(key: _privateKeyVaultKey);
    }
  }

  /// Whether the live session key is hardware-wrapped. Reported at wallet
  /// creation / rotation so server policy can distinguish vaulted devices.
  Future<bool> readPrivateKeyVaulted() async =>
      (await _storage.read(key: _privateKeyVaultKey)) == '1';

  /// Set once during onboarding's PIN step, independent of wallet creation
  /// — the PIN guards the app lock screen, not any single wallet.
  Future<void> savePinHash(String pinHash) =>
      _storage.write(key: _pinHashKey, value: pinHash);

  Future<String?> readPinHash() => _storage.read(key: _pinHashKey);

  Future<void> saveBiometricEnabled(bool enabled) =>
      _storage.write(key: _biometricEnabledKey, value: enabled.toString());

  Future<bool> readBiometricEnabled() async =>
      (await _storage.read(key: _biometricEnabledKey)) == 'true';

  /// Hide-savings (coercion protection) — see `HideSavingsSetupScreen`.
  /// `hidePhraseHash` is hashed the same way the app PIN is (see
  /// `security/pin_hash.dart`): the prototype this is ported from stored
  /// its own secret phrase in plaintext, which is exactly the kind of
  /// leftover it warns against elsewhere in its own design ("never
  /// published in plaintext").
  Future<void> saveHideSavingsSettings({
    required bool enabled,
    required String action,
    required int count,
    required int revealSeconds,
    String? phraseHash,
  }) async {
    await _storage.write(
        key: _hideSavingsEnabledKey, value: enabled.toString());
    await _storage.write(key: _hideSavingsActionKey, value: action);
    await _storage.write(key: _hideSavingsCountKey, value: count.toString());
    await _storage.write(
        key: _hideSavingsRevealSecsKey, value: revealSeconds.toString());
    if (phraseHash != null)
      await _storage.write(key: _hideSavingsPhraseHashKey, value: phraseHash);
  }

  Future<bool> readHideSavingsEnabled() async =>
      (await _storage.read(key: _hideSavingsEnabledKey)) == 'true';

  Future<String?> readHideSavingsAction() =>
      _storage.read(key: _hideSavingsActionKey);

  Future<int> readHideSavingsCount() async =>
      int.tryParse(await _storage.read(key: _hideSavingsCountKey) ?? '') ?? 3;

  Future<int> readHideSavingsRevealSeconds() async =>
      int.tryParse(await _storage.read(key: _hideSavingsRevealSecsKey) ?? '') ??
      20;

  Future<String?> readHideSavingsPhraseHash() =>
      _storage.read(key: _hideSavingsPhraseHashKey);

  /// Per-conversation read marks backing inbox unread dots — the server
  /// has no "read" concept, so last-read lives on-device. Keyed by
  /// conversation id (a wallet or group UUID, safe to inline after
  /// sanitizing). Unknown ids read back as "never read", which callers
  /// treat as *baseline-on-first-sight* (not unread) so history never
  /// spams dots after a fresh login.
  static String _readMarkKey(String id) =>
      'jamiipay.last_read.${id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  Future<void> saveConversationRead(String id, DateTime at) =>
      _storage.write(key: _readMarkKey(id), value: at.toIso8601String());

  Future<Map<String, DateTime>> readConversationReads() async {
    final all = await _storage.readAll();
    final out = <String, DateTime>{};
    const prefix = 'jamiipay.last_read.';
    all.forEach((key, value) {
      if (!key.startsWith(prefix)) return;
      final at = DateTime.tryParse(value);
      if (at != null) out[key.substring(prefix.length)] = at;
    });
    return out;
  }

  /// Language actually persists now (was discarded by LanguageScreen).
  Future<void> saveLanguage(String code) =>
      _storage.write(key: _languageKey, value: code);
  Future<String?> readLanguage() => _storage.read(key: _languageKey);

  /// Crash-resume: which onboarding step was reached (language/pin/
  /// biometric/handle/guardians/done). Relaunch resumes instead of
  /// restarting at Welcome and orphaning the saved PIN.
  Future<void> saveOnboardingStep(String step) =>
      _storage.write(key: _onboardingStepKey, value: step);
  Future<String?> readOnboardingStep() =>
      _storage.read(key: _onboardingStepKey);

  /// Cached FX quote with timestamp so every screen shows
  /// "updated Xm ago" and freezes the quote at confirm time.
  Future<void> saveFxRate(double rate) async {
    await _storage.write(key: _fxRateKey, value: rate.toString());
    await _storage.write(
        key: _fxUpdatedAtKey, value: DateTime.now().toIso8601String());
  }

  Future<(double, DateTime)?> readFxRate() async {
    final r = await _storage.read(key: _fxRateKey);
    final t = await _storage.read(key: _fxUpdatedAtKey);
    final rate = double.tryParse(r ?? '');
    final at = DateTime.tryParse(t ?? '');
    if (rate == null || at == null) return null;
    return (rate, at);
  }

  Future<void> clear() async {
    await _storage.delete(key: _walletIdKey);
    await _storage.delete(key: _privateKeyKey);
    await _storage.delete(key: _privateKeyVaultKey);
    await _storage.delete(key: _pinHashKey);
    await _storage.delete(key: _biometricEnabledKey);
    await _storage.delete(key: _hideSavingsEnabledKey);
    await _storage.delete(key: _hideSavingsActionKey);
    await _storage.delete(key: _hideSavingsCountKey);
    await _storage.delete(key: _hideSavingsRevealSecsKey);
    await _storage.delete(key: _hideSavingsPhraseHashKey);
    await _storage.delete(key: _languageKey);
    await _storage.delete(key: _onboardingStepKey);
    // Keep cached FX across sign-out: rates are not per-wallet.
  }
}
