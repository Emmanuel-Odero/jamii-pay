import 'package:local_auth/local_auth.dart';

/// Thin wrapper over `local_auth` so screens don't import the plugin
/// directly. Every call here is a real platform biometric prompt (Face
/// ID/Touch ID) — nothing here is simulated.
class LocalAuthService {
  LocalAuthService([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<bool> get isSupported async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Returns true only on a genuine successful biometric match. Returns
  /// false (never throws) on cancellation, lockout, or an unsupported
  /// device — callers fall back to the PIN either way.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options:
            const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}
