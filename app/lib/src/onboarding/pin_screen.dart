import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../widgets/app_screen.dart';
import '../widgets/info_banner.dart';
import '../widgets/numeric_keypad.dart';
import '../widgets/pin_dots.dart';
import '../widgets/screen_nav.dart';

/// Onboarding 3/7 — "Set your PIN". The explanation of why six characters
/// is safe sits on the screen where the doubt occurs: the PIN unlocks a
/// key in the phone's secure enclave, which is the actual control —
/// hardware-backed rate limiting, not the PIN's own entropy.
class PinScreen extends StatefulWidget {
  const PinScreen({super.key, required this.onBack, required this.onComplete});

  final VoidCallback onBack;
  final ValueChanged<String> onComplete;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _pin = '';

  void _onDigit(String digit) {
    if (_pin.length >= 6) return;
    setState(() => _pin += digit);
    if (_pin.length == 6) {
      widget.onComplete(_pin);
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(onBack: widget.onBack, step: 2, totalSteps: 5),
          Text('Create a PIN', style: AppText.screenTitle()),
          const SizedBox(height: 8),
          Text("Six characters. You'll use this to approve payments.",
              style: AppText.screenSub()),
          const SizedBox(height: 8),
          PinDots(filled: _pin.length),
          const SizedBox(height: 16),
          const InfoBanner(
            icon: Icons.lock_outline,
            text:
                "Your PIN never leaves this phone. It unlocks a key stored in your phone's secure "
                'chip — which is what makes six characters enough.',
          ),
          const Spacer(),
          NumericKeypad(onDigit: _onDigit, onBackspace: _onBackspace),
        ],
      ),
    );
  }
}
