import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api_client.dart';
import '../models/alert_preference.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_card.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/info_banner.dart';
import '../widgets/screen_nav.dart';

/// Settings → "Alerts". The prototype's `SCR.alerts` is read-only —
/// static rows showing what channels each event uses. This is a real,
/// editable version: per-event SMS/Push/Email switches, saved
/// immediately on toggle (same optimistic-update pattern as Settings'
/// biometric switch). `recovery_started` renders locked with the
/// prototype's own override-copy banner, matching its "ignores your
/// preferences and quiet hours" rule exactly — that's server-enforced
/// too (see `routes/alerts.rs`), not just a disabled switch.
class AlertSettingsScreen extends StatefulWidget {
  const AlertSettingsScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<AlertSettingsScreen> createState() => _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends State<AlertSettingsScreen> {
  List<AlertPreference>? _preferences;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await context.read<WalletStore>().getAlertPreferences();
      if (!mounted) return;
      setState(() => _preferences = prefs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _toggle(AlertPreference pref,
      {bool? sms, bool? push, bool? email}) async {
    final updated = pref.copyWith(sms: sms, push: push, email: email);
    setState(() {
      _preferences = [
        for (final p in _preferences!)
          if (p.eventKey == pref.eventKey) updated else p
      ];
    });
    try {
      await context.read<WalletStore>().updateAlertPreferences([updated]);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppSnackBar.show(context, message: e.message, tone: SnackTone.danger);
      _load(); // revert to server truth
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy900,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScreenNav(title: 'Alerts', onBack: widget.onBack),
                if (_preferences == null && _error == null)
                  const AppLoading(label: 'Loading alert settings…'),
                if (_error != null)
                  InfoBanner(
                      icon: Icons.error_outline,
                      tone: BannerTone.danger,
                      text: _error!),
                if (_preferences != null) ...[
                  for (final pref in _preferences!) ...[
                    _EventCard(
                      pref: pref,
                      onToggle: ({sms, push, email}) =>
                          _toggle(pref, sms: sms, push: push, email: email),
                    ),
                    const SizedBox(height: 9),
                  ],
                  const SizedBox(height: 9),
                  const InfoBanner(
                    icon: Icons.warning_amber_rounded,
                    tone: BannerTone.warning,
                    text:
                        'Recovery alerts ignore your preferences and quiet hours. That is deliberate — it is the '
                        'one message you cannot afford to miss.',
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.pref, required this.onToggle});

  final AlertPreference pref;
  final void Function({bool? sms, bool? push, bool? email}) onToggle;

  @override
  Widget build(BuildContext context) {
    if (pref.locked) {
      return AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pref.label,
                      style: AppText.ui(size: 13, weight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('SMS, push, and email · always on',
                      style: AppText.ui(size: 11, color: AppColors.ink3)),
                ],
              ),
            ),
            Icon(Icons.lock_outline, size: 16, color: AppColors.ink3),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pref.label,
              style: AppText.ui(size: 13, weight: FontWeight.w700)),
          const SizedBox(height: 9),
          _ChannelRow(
              label: 'SMS',
              value: pref.sms,
              onChanged: (v) => onToggle(sms: v)),
          _ChannelRow(
              label: 'Push',
              value: pref.push,
              onChanged: (v) => onToggle(push: v)),
          _ChannelRow(
              label: 'Email',
              value: pref.email,
              onChanged: (v) => onToggle(email: v)),
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow(
      {required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppText.ui(size: 12, color: AppColors.ink2)),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
