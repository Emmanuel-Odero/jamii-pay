import 'package:flutter/material.dart';

import '../data/session_storage.dart';
import '../security/pin_hash.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_screen.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/info_banner.dart';
import '../widgets/option_card.dart';
import '../widgets/pill.dart';
import '../widgets/screen_nav.dart';

/// "Choose how to reveal it" — the coercion-protection setup screen from
/// `designs/jammii-pay-prototype.html`'s `hideSetup`. Purely client-side:
/// nothing here needs the server, since hiding a balance from a glance is
/// a property of this device's UI, not of the account.
class HideSavingsSetupScreen extends StatefulWidget {
  const HideSavingsSetupScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<HideSavingsSetupScreen> createState() => _HideSavingsSetupScreenState();
}

enum _RevealAction { tap, hold, search }

class _HideSavingsSetupScreenState extends State<HideSavingsSetupScreen> {
  _RevealAction _action = _RevealAction.tap;
  int _count = 3;
  int _seconds = 20;
  final _phraseController = TextEditingController();
  bool _saving = false;
  bool _wasAlreadyHidden = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    const storage = SessionStorage();
    final enabled = await storage.readHideSavingsEnabled();
    final action = await storage.readHideSavingsAction();
    final count = await storage.readHideSavingsCount();
    final seconds = await storage.readHideSavingsRevealSeconds();
    if (!mounted) return;
    setState(() {
      _wasAlreadyHidden = enabled;
      _action = _RevealAction.values
          .firstWhere((a) => a.name == action, orElse: () => _RevealAction.tap);
      _count = count;
      _seconds = seconds;
    });
  }

  @override
  void dispose() {
    _phraseController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_action == _RevealAction.search &&
        _phraseController.text.trim().isEmpty) {
      AppSnackBar.show(context,
          message: 'Pick a phrase', tone: SnackTone.warning);
      return;
    }
    setState(() => _saving = true);
    final phrase = _phraseController.text.trim();
    await const SessionStorage().saveHideSavingsSettings(
      enabled: true,
      action: _action.name,
      count: _count,
      revealSeconds: _seconds,
      phraseHash: _action == _RevealAction.search
          ? hashPin(phrase.toLowerCase())
          : null,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    final howTo = switch (_action) {
      _RevealAction.tap => 'tap the balance $_count×',
      _RevealAction.hold => 'long-press the balance $_count×',
      _RevealAction.search => 'search "$phrase" in Activity',
    };
    // Pop *with* the confirmation message rather than showing the snackbar
    // here — `context` belongs to this screen, which is being removed by
    // this same `pop()`; using it afterward throws ("Looking up a
    // deactivated widget's ancestor is unsafe"), which is exactly what
    // produced the blank screen this replaced. The caller (still-mounted,
    // still on screen) shows it instead — see `wallet_flow.dart`'s
    // `_pushHideSavingsSetup`.
    Navigator.of(context).pop('Savings hidden — To reveal: $howTo.');
  }

  Future<void> _stopHiding() async {
    await const SessionStorage().saveHideSavingsSettings(
        enabled: false, action: 'tap', count: 3, revealSeconds: 20);
    if (!mounted) return;
    Navigator.of(context)
        .pop('Visible again — Savings shows on your home screen.');
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      footer: Column(
        children: [
          AppButton(
            label: _saving
                ? 'Saving…'
                : (_wasAlreadyHidden ? 'Update' : 'Hide savings'),
            onPressed: _saving ? null : _save,
          ),
          if (_wasAlreadyHidden) ...[
            const SizedBox(height: 9),
            AppButton(
                label: 'Stop hiding',
                variant: AppButtonVariant.outline,
                onPressed: _stopHiding),
          ],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Choose how to reveal it', onBack: widget.onBack),
          Text(
            'Savings disappears from your home screen. Only this action brings it back.',
            style: AppText.screenSub(),
          ),
          const SizedBox(height: 18),
          OptionCard(
            icon: Icons.touch_app_outlined,
            iconBackground: AppColors.blue.withValues(alpha: 0.2),
            iconColor: AppColors.blue,
            title: 'Tap the balance',
            description: 'Tap your everyday balance a set number of times',
            selected: _action == _RevealAction.tap,
            onTap: () => setState(() => _action = _RevealAction.tap),
          ),
          const SizedBox(height: 9),
          OptionCard(
            icon: Icons.back_hand_outlined,
            iconBackground: AppColors.green.withValues(alpha: 0.18),
            iconColor: AppColors.green,
            title: 'Long-press the balance',
            description: 'Press and hold, repeated a set number of times',
            selected: _action == _RevealAction.hold,
            onTap: () => setState(() => _action = _RevealAction.hold),
          ),
          const SizedBox(height: 9),
          OptionCard(
            icon: Icons.search,
            iconBackground: AppColors.navy600,
            iconColor: AppColors.ink2,
            title: 'Search a secret phrase',
            description: 'Type a phrase you choose into Activity search',
            selected: _action == _RevealAction.search,
            onTap: () => setState(() => _action = _RevealAction.search),
          ),
          const SizedBox(height: 18),
          if (_action == _RevealAction.search) ...[
            Text('Your secret phrase',
                style: AppText.ui(size: 12, color: AppColors.ink3)),
            const SizedBox(height: 8),
            TextField(
              controller: _phraseController,
              style: AppText.ui(size: 14),
              decoration: InputDecoration(
                hintText: 'e.g. blue kettle',
                hintStyle: AppText.ui(size: 14, color: AppColors.ink3),
                filled: true,
                fillColor: AppColors.navy800,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11),
                    borderSide: BorderSide(color: AppColors.line2)),
              ),
            ),
          ] else ...[
            Text('How many times',
                style: AppText.ui(size: 12, color: AppColors.ink3)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              children: [
                for (final n in [2, 3, 4, 5, 6])
                  AppPill(
                      label: '$n×',
                      selected: _count == n,
                      onTap: () => setState(() => _count = n)),
              ],
            ),
            const SizedBox(height: 16),
            Text('Stay visible for',
                style: AppText.ui(size: 12, color: AppColors.ink3)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              children: [
                for (final s in [10, 20, 30, 60])
                  AppPill(
                      label: '${s}s',
                      selected: _seconds == s,
                      onTap: () => setState(() => _seconds = s)),
              ],
            ),
          ],
          const SizedBox(height: 18),
          const InfoBanner(
            icon: Icons.info_outline,
            text:
                'We build the actions; you pick the numbers. If you forget your own setting, savings is still '
                'reachable from Settings — this hides it from a casual glance, not from you.',
          ),
        ],
      ),
    );
  }
}
