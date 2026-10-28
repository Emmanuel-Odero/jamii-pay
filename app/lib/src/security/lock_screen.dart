import 'package:flutter/material.dart';

import '../data/session_storage.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/jamii_logo.dart';
import '../widgets/numeric_keypad.dart';
import '../widgets/pin_dots.dart';
import 'local_auth_service.dart';
import 'pin_hash.dart';

/// Gates `/wallet` on every cold start once a PIN has been set — this is
/// the enforcement half of onboarding's PIN/biometric screens, which
/// previously recorded nothing and never actually locked anything. Shown
/// from `router/app_router.dart`'s `_Bootstrap` after a session is found.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked, this.onForgotPin});

  final VoidCallback onUnlocked;

  /// A locked-out user used to have no in-context way back into their
  /// wallet other than knowing to look for recovery somewhere else
  /// entirely — this is the same guardian-recovery flow reachable from
  /// Settings, surfaced from the one screen where actually needing it is
  /// most likely. Optional so this screen still works before recovery is
  /// wired up anywhere that constructs it.
  final VoidCallback? onForgotPin;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const _storage = SessionStorage();
  final _auth = LocalAuthService();

  String? _pinHash;
  bool _biometricEnabled = false;
  bool _ready = false;
  bool _biometricAttempting = false;
  String _pin = '';
  bool _wrongPin = false;
  int _attempts = 0;
  DateTime? _lockedUntil;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pinHash = await _storage.readPinHash();
    final biometricEnabled = await _storage.readBiometricEnabled();
    if (!mounted) return;

    if (pinHash == null) {
      // No PIN was ever set for this session (e.g. an older test wallet) —
      // don't lock someone out of an app they never set a lock code for.
      widget.onUnlocked();
      return;
    }

    setState(() {
      _pinHash = pinHash;
      _biometricEnabled = biometricEnabled;
      _ready = true;
    });

    if (biometricEnabled) _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    setState(() => _biometricAttempting = true);
    final matched = await _auth.authenticate('Unlock JamiiPay');
    if (!mounted) return;
    setState(() => _biometricAttempting = false);
    if (matched) widget.onUnlocked();
  }

  void _onDigit(String digit) {
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) return;
    if (_pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _wrongPin = false;
    });
    if (_pin.length == 6) _checkPin();
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _checkPin() {
    if (hashPin(_pin) == _pinHash) {
      widget.onUnlocked();
      return;
    }
    _attempts++;
    // Exponential backoff: 5 fails -> 30s, 8 fails -> 2m. Brute-force
    // perception was the old gap (6-digit PIN, no delay, no counter).
    Duration? lockFor;
    if (_attempts >= 8) {
      lockFor = const Duration(minutes: 2);
    } else if (_attempts >= 5) {
      lockFor = const Duration(seconds: 30);
    }
    setState(() {
      _wrongPin = true;
      _pin = '';
      _lockedUntil =
          lockFor == null ? null : DateTime.now().add(lockFor);
    });
    if (lockFor != null) {
      Future.delayed(lockFor, () {
        if (mounted) setState(() => _lockedUntil = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
          backgroundColor: AppColors.navy900,
          body: const Center(child: JamiiLogo(size: 64)));
    }
    return Scaffold(
      backgroundColor: AppColors.navy900,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Center(child: JamiiLogo(size: 56)),
              const SizedBox(height: 20),
              Text('Enter your PIN',
                  style: AppText.screenTitle(), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _lockedUntil != null &&
                          DateTime.now().isBefore(_lockedUntil!)
                      ? 'Too many tries. Wait a moment, then try again.'
                      : _wrongPin
                          ? _attempts >= 3
                              ? "That PIN doesn't match ($_attempts tries). Need help? Use Forgot PIN below."
                              : "That PIN doesn't match."
                          : 'Unlock JamiiPay to continue.',
                  style: AppText.screenSub()
                      .copyWith(color: _wrongPin ? AppColors.coral : null),
                ),
              ),
              const SizedBox(height: 20),
              PinDots(filled: _pin.length),
              const Spacer(),
              if (_biometricEnabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppButton(
                    label: _biometricAttempting
                        ? 'Confirming…'
                        : 'Use Face ID / Touch ID',
                    variant: AppButtonVariant.outline,
                    onPressed: _biometricAttempting ? null : _tryBiometric,
                  ),
                ),
              NumericKeypad(onDigit: _onDigit, onBackspace: _onBackspace),
              if (widget.onForgotPin != null)
                Center(
                  child: TextButton(
                    onPressed: widget.onForgotPin,
                    child: Text('Forgot your PIN?',
                        style: AppText.ui(
                            size: 12.5,
                            weight: FontWeight.w600,
                            color: AppColors.ink2)),
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
