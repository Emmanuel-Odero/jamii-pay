import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/info_banner.dart';
import '../widgets/screen_nav.dart';

/// Recovery R1 — "Start on a borrowed phone". Reachable before login, from
/// a device that has never held the account — a recovery flow behind a
/// sign-in wall is not a recovery flow. That means the payment name has to
/// be typed here, not read from a session this device doesn't have — this
/// used to show a hardcoded handle no matter who opened it.
class RecoveryStartScreen extends StatefulWidget {
  const RecoveryStartScreen({
    super.key,
    this.initialHandle,
    required this.onBack,
    required this.onContinue,
    required this.onReportStolen,
  });

  /// Pre-fills the field when reached from an active session (Settings'
  /// "Lost your phone?" demo entry point) — still editable, since the
  /// real-world flow never has this.
  final String? initialHandle;
  final VoidCallback onBack;
  final ValueChanged<String> onContinue;
  final ValueChanged<String> onReportStolen;

  @override
  State<RecoveryStartScreen> createState() => _RecoveryStartScreenState();
}

class _RecoveryStartScreenState extends State<RecoveryStartScreen> {
  late final _controller =
      TextEditingController(text: widget.initialHandle ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canContinue => _controller.text.trim().length >= 4;

  @override
  Widget build(BuildContext context) {
    final handle = _controller.text.trim().toLowerCase();

    return AppScreen(
      footer: Column(
        children: [
          AppButton(
              label: 'Continue',
              onPressed: _canContinue ? () => widget.onContinue(handle) : null),
          const SizedBox(height: 9),
          AppButton(
              label: 'My phone was stolen',
              variant: AppButtonVariant.dangerOutline,
              onPressed:
                  _canContinue ? () => widget.onReportStolen(handle) : null),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Get my wallet back', onBack: widget.onBack),
          Text("What's your payment name?",
              style: AppText.screenTitle(size: 22)),
          const SizedBox(height: 8),
          Text(
            "We'll show you which recovery methods you set up. You'll need any two of them.",
            style: AppText.screenSub(),
          ),
          AppCard(
            variant: AppCardVariant.selected,
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 6),
            child: TextField(
              controller: _controller,
              onChanged: (_) => setState(() {}),
              textAlign: TextAlign.center,
              autofocus: widget.initialHandle == null,
              style: AppText.mono(size: 20, letterSpacing: 1),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'yourname0',
                hintStyle: AppText.mono(
                    size: 20, letterSpacing: 1, color: AppColors.ink3),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const InfoBanner(
            icon: Icons.warning_amber_rounded,
            tone: BannerTone.danger,
            text:
                "If your phone was stolen rather than lost, tell us now — we'll alert every device on "
                'your account.',
          ),
        ],
      ),
    );
  }
}
