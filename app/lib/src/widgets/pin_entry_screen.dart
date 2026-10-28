import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import 'app_screen.dart';
import 'info_banner.dart';
import 'numeric_keypad.dart';
import 'pin_dots.dart';
import 'screen_nav.dart';

/// A general-purpose six-digit PIN pad screen — the same keypad/dots
/// pattern as onboarding's `PinScreen`, but parameterized so it can be
/// reused anywhere else a PIN needs entering: setting/confirming the
/// wallet-key encryption PIN on the backup screen, and entering both PINs
/// on the restore-from-key screen.
///
/// [onComplete] returns the error message to show on failure (`null` on
/// success). On failure the screen clears itself and shakes in place
/// rather than the caller popping this screen and pushing a fresh one —
/// that used to cause a visible screen-replace flash for something as
/// routine as a mistyped PIN, the single most common failure this screen
/// sees.
class PinEntryScreen extends StatefulWidget {
  const PinEntryScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.bannerText,
    this.bannerIcon = Icons.lock_outline,
    this.errorText,
    required this.onBack,
    required this.onComplete,
  });

  final String title;
  final String subtitle;
  final String? bannerText;
  final IconData bannerIcon;

  /// Seeds the error banner shown on first build — for a caller that
  /// already knows the previous attempt failed before this widget existed.
  /// Every failure from here on is handled internally; see [onComplete].
  final String? errorText;
  final VoidCallback onBack;

  /// Return an error message to keep the user on this screen (cleared and
  /// shaken); return `null` on success, after which the caller navigates
  /// away as usual.
  final Future<String?> Function(String pin) onComplete;

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  String? _error;
  bool _busy = false;
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _error = widget.errorText;
    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _onDigit(String digit) async {
    if (_pin.length >= 6 || _busy) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length < 6) return;

    final pin = _pin;
    setState(() => _busy = true);
    final error = await widget.onComplete(pin);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _pin = '';
        _error = error;
        _busy = false;
      });
      _shakeController.forward(from: 0);
    }
    // On success the caller navigates away; nothing left to reset here.
  }

  void _onBackspace() {
    if (_pin.isEmpty || _busy) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(onBack: widget.onBack),
          Text(widget.title, style: AppText.screenTitle()),
          const SizedBox(height: 8),
          Text(widget.subtitle, style: AppText.screenSub()),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) {
              final t = _shakeController.value;
              // Decaying sine wave: a few quick side-to-side wobbles that
              // settle back to centre, not a single hard jolt.
              final offset = (1 - t) * 8 * math.sin(t * 4 * math.pi);
              return Transform.translate(
                  offset: Offset(offset, 0), child: child);
            },
            child: PinDots(filled: _pin.length),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            InfoBanner(
                icon: Icons.error_outline,
                tone: BannerTone.danger,
                text: _error!)
          else if (widget.bannerText != null)
            InfoBanner(icon: widget.bannerIcon, text: widget.bannerText!),
          const Spacer(),
          NumericKeypad(onDigit: (d) => _onDigit(d), onBackspace: _onBackspace),
        ],
      ),
    );
  }
}
