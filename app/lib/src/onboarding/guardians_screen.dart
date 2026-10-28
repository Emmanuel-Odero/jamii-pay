import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_screen.dart';
import '../widgets/option_card.dart';
import '../widgets/screen_nav.dart';

class _GuardianOption {
  const _GuardianOption(this.id, this.icon, this.iconBg, this.iconColor,
      this.title, this.description);
  final String id;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String description;
}

/// Onboarding 6/7 — "Set up recovery". The hardest screen in the product.
/// A person guardian is offered but never required, because displacement
/// scatters exactly the networks that design normally assumes exist. The
/// default three (device, printed code, Jamii Pay) work for someone who
/// knows nobody nearby.
class GuardiansScreen extends StatefulWidget {
  const GuardiansScreen(
      {super.key, required this.onBack, required this.onConfirm});

  final VoidCallback onBack;
  final ValueChanged<Set<String>> onConfirm;

  @override
  State<GuardiansScreen> createState() => _GuardiansScreenState();
}

class _GuardiansScreenState extends State<GuardiansScreen> {
  // A getter, not a static list — reads AppColors fresh so it stays correct
  // if the theme changes (e.g. mid-onboarding, via the picker in Settings
  // reached through some other route).
  List<_GuardianOption> get _options => [
        _GuardianOption(
            'device',
            Icons.tablet_mac_outlined,
            AppColors.blue.withValues(alpha: 0.2),
            AppColors.blue,
            'Another device',
            'A tablet or second phone you own'),
        _GuardianOption(
            'printed_code',
            Icons.description_outlined,
            AppColors.coral.withValues(alpha: 0.18),
            AppColors.coral,
            'A printed code',
            'Keep it somewhere safe, or with someone you trust'),
        _GuardianOption(
            'institutional',
            Icons.account_balance_outlined,
            AppColors.green.withValues(alpha: 0.18),
            AppColors.green,
            'Jamii Pay',
            'We verify you, then wait 48 hours before helping'),
        _GuardianOption(
            'trusted_person',
            Icons.people_outline,
            AppColors.navy600,
            AppColors.ink2,
            'Someone you trust',
            'A friend or family member using Jamii Pay'),
      ];

  final Set<String> _selected = {'device', 'printed_code', 'institutional'};

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      footer: AppButton(
        label: 'Confirm these three',
        onPressed:
            _selected.length >= 3 ? () => widget.onConfirm(_selected) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(
              title: 'Recovery', onBack: widget.onBack, step: 5, totalSteps: 5),
          Text('If you lose this phone', style: AppText.screenTitle(size: 22)),
          const SizedBox(height: 8),
          Text(
            "Choose three ways to prove it's you. Any two of them can restore your money.",
            style: AppText.screenSub(),
          ),
          for (final option in _options) ...[
            OptionCard(
              icon: option.icon,
              iconBackground: option.iconBg,
              iconColor: option.iconColor,
              title: option.title,
              description: option.description,
              selected: _selected.contains(option.id),
              onTap: () => setState(() {
                if (_selected.contains(option.id)) {
                  _selected.remove(option.id);
                } else {
                  _selected.add(option.id);
                }
              }),
            ),
            const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}
