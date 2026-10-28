import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/session_storage.dart';
import '../models/guardian_labels.dart';
import '../notifications/local_notifications.dart';
import '../security/local_auth_service.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/theme_store.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/handle_chip.dart';
import '../widgets/motion.dart';
import '../widgets/row_line.dart';
import 'wallet_key_backup_flow.dart';
import 'wallet_key_rotate_flow.dart';

/// Wallet → "Settings". Real account/security state, not the "not designed
/// yet" placeholder it used to be — the handle, address, and guardians here
/// come straight from `WalletStore`, and the biometric switch drives a real
/// `local_auth` prompt the same way onboarding's biometric screen does.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onAppearance,
    required this.onAlerts,
    required this.onSavings,
    required this.onRecovery,
    required this.onRecoveryAlertDemo,
    required this.onLanguage,
    required this.onSignedOut,
  });

  final VoidCallback onAppearance;
  final VoidCallback onAlerts;

  /// The one guaranteed way back to Savings (and its "stop hiding"
  /// button) when the home-screen card is hidden — see
  /// `HideSavingsSetupScreen`'s own promise: "savings is still reachable
  /// from Settings — this hides it from a casual glance, not from you."
  /// Before this, that promise was only true in the copy, not in the
  /// navigation: there was no route to Savings other than the (now
  /// hidden) home card.
  final VoidCallback onSavings;
  final VoidCallback onRecovery;

  /// R4 — "someone is trying to recover your wallet" — is real screen the
  /// actual owner's *other* device would show, but no push infrastructure
  /// exists to route it there for real. Reachable from the quiet demo
  /// link at the bottom rather than as a full-width button.
  final VoidCallback onRecoveryAlertDemo;

  /// Onboarding's language step promises "you can change this any time
  /// from Settings" — this is that promise kept.
  final VoidCallback onLanguage;
  final VoidCallback onSignedOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _storage = SessionStorage();
  final _auth = LocalAuthService();

  bool _biometricEnabled = false;
  bool _biometricBusy = false;
  String? _languageCode;
  String _notifStatus = 'Checking…';
  bool _notifTesting = false;

  @override
  void initState() {
    super.initState();
    _storage.readBiometricEnabled().then((v) {
      if (mounted) setState(() => _biometricEnabled = v);
    });
    _storage.readLanguage().then((v) {
      if (mounted) setState(() => _languageCode = v ?? 'EN');
    });
    _refreshNotifStatus();
  }

  /// Reads the OS-level notification permission for the diagnostics row.
  /// This is ground truth for "why don't I get banners": if the OS says
  /// denied, no trigger in the app can ever produce one.
  Future<void> _refreshNotifStatus() async {
    try {
      final p = await LocalNotifications.checkPermissions();
      if (!mounted) return;
      setState(() {
        _notifStatus = p == null
            ? 'Unknown on this device'
            : (p.isEnabled
                ? 'Allowed (banner, sound, badge)'
                : 'Denied — enable in iPhone Settings → JamiiPay → Notifications');
      });
    } catch (_) {
      if (mounted) setState(() => _notifStatus = 'Unknown on this device');
    }
  }

  /// Fires a real banner through the same path money/message alerts use,
  /// so a missing banner here means an OS-level problem (permission,
  /// Focus, silent switch) rather than an app-trigger problem.
  Future<void> _sendTestNotification() async {
    setState(() => _notifTesting = true);
    await LocalNotifications.show(
      title: 'Test notification',
      body:
          'If you see this banner and hear a sound, JamiiPay alerts work — real ones fire while the app is open or recently used.',
      badgeCount: 1,
    );
    await _refreshNotifStatus();
    if (mounted) setState(() => _notifTesting = false);
  }

  Future<void> _toggleBiometric(bool wantsEnabled) async {
    if (!wantsEnabled) {
      await _storage.saveBiometricEnabled(false);
      if (mounted) setState(() => _biometricEnabled = false);
      return;
    }

    setState(() => _biometricBusy = true);
    final supported = await _auth.isSupported;
    if (!supported) {
      setState(() => _biometricBusy = false);
      if (!mounted) return;
      AppSnackBar.show(context,
          message: 'No biometric sensor is enrolled on this device.',
          tone: SnackTone.danger);
      return;
    }
    final matched = await _auth
        .authenticate('Confirm to enable biometric unlock for JamiiPay');
    setState(() => _biometricBusy = false);
    if (!mounted) return;
    if (matched) {
      await _storage.saveBiometricEnabled(true);
      if (mounted) setState(() => _biometricEnabled = true);
      Haptics.confirm();
    } else {
      AppSnackBar.show(context,
          message: "Couldn't confirm your biometrics.",
          tone: SnackTone.danger);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Sign out?',
      message:
          "You'll need your recovery methods to get back into this wallet — signing out doesn't delete "
          'it, but this device forgets it.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await context.read<WalletStore>().signOut();
    widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletStore>().wallet;
    final themePreset = context.watch<ThemeStore>().preset;

    return AppScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings',
              style: AppText.ui(size: 16, weight: FontWeight.w700)),
          const SizedBox(height: 16),
          if (wallet != null) ...[
            _AccountCard(
              handleBase: wallet.handleBase,
              handleCheckDigit: wallet.handleCheckDigit,
              evmAddress: wallet.evmAddress,
            ),
            const SizedBox(height: 20),
          ],
          _SectionHeader('Preferences'),
          const SizedBox(height: 8),
          _SettingsRow(
            icon: Icons.palette_outlined,
            tint: AppColors.blue,
            title: 'Appearance',
            subtitle: themePreset.label,
            onTap: widget.onAppearance,
          ),
          const SizedBox(height: 8),
          _SettingsRow(
            icon: Icons.notifications_none,
            tint: AppColors.amber,
            title: 'Alerts',
            subtitle: 'Per-event SMS, push, and email',
            onTap: widget.onAlerts,
          ),
          const SizedBox(height: 8),
          _SettingsRow(
            icon: Icons.language_outlined,
            tint: AppColors.blue,
            title: 'Language',
            subtitle: _languageName(_languageCode),
            onTap: () {
              widget.onLanguage();
              // Refresh the shown selection when returning.
              Future.delayed(const Duration(milliseconds: 300), () async {
                if (!mounted) return;
                final v = await _storage.readLanguage();
                if (mounted) setState(() => _languageCode = v ?? 'EN');
              });
            },
          ),
          const SizedBox(height: 8),
          _SettingsRow(
            icon: Icons.savings_outlined,
            tint: AppColors.green,
            title: 'Savings',
            subtitle: 'Always reachable, even if hidden from Home',
            onTap: widget.onSavings,
          ),
          const SizedBox(height: 20),
          _SectionHeader('Security'),
          const SizedBox(height: 8),
          AppCard(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.fingerprint,
                      size: 20, color: AppColors.green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Biometric unlock',
                          style: AppText.ui(
                              size: 14, weight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('Face ID / fingerprint instead of PIN',
                          style: AppText.ui(
                              size: 12.5, color: AppColors.ink3)),
                    ],
                  ),
                ),
                if (_biometricBusy)
                  Opacity(
                      opacity: 0.5,
                      child: Switch(
                          value: _biometricEnabled, onChanged: null))
                else
                  Switch(
                      value: _biometricEnabled,
                      onChanged: _toggleBiometric),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _SettingsRow(
            icon: Icons.key_outlined,
            tint: AppColors.amber,
            title: 'Back up wallet key',
            subtitle: 'Encrypted file + PIN, kept by you',
            enabled: wallet != null,
            onTap: () => pushWalletKeyBackupFlow(context),
          ),
          const SizedBox(height: 8),
          _SettingsRow(
            icon: Icons.refresh_rounded,
            tint: AppColors.blue,
            title: 'Rotate wallet key',
            subtitle: 'Fresh key, revokes all old backups',
            enabled: wallet != null,
            onTap: () => pushWalletKeyRotateFlow(context),
          ),
          const SizedBox(height: 8),
          _SettingsRow(
            icon: Icons.phonelink_erase_outlined,
            tint: AppColors.coral,
            title: 'Recover a lost phone',
            subtitle: 'Guardian approval + safety wait',
            onTap: widget.onRecovery,
          ),
          const SizedBox(height: 20),
          _SectionHeader('Notifications'),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RowLine(
                    label: 'Phone alerts', value: _notifStatus),
                const SizedBox(height: 10),
                Text(
                  'Money and message alerts fire while the app is open or recently used. '
                  'Closed-app and lock-screen alerts arrive by remote push once it is provisioned on the server.',
                  style: AppText.ui(size: 12, color: AppColors.ink3)),
                const SizedBox(height: 10),
                AppButton(
                  label: _notifTesting
                      ? 'Sending…'
                      : 'Send test notification',
                  variant: AppButtonVariant.outline,
                  onPressed: _notifTesting ? null : _sendTestNotification,
                ),
              ],
            ),
          ),
          if (wallet != null && wallet.guardians.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionHeader('Recovery methods'),
            const SizedBox(height: 8),
            AppCard(
              child: Column(
                children: [
                  for (final g in wallet.guardians)
                    RowLine(
                        label: guardianLabels[g] ?? g,
                        value: 'Set up',
                        valueColor: AppColors.green,
                        showBorder: g != wallet.guardians.last),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: _confirmSignOut,
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: AppColors.coral.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Sign out',
                  style: AppText.ui(
                      size: 14,
                      weight: FontWeight.w700,
                      color: AppColors.coral)),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: widget.onRecoveryAlertDemo,
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 48)),
              child: Text('Preview a recovery alert (demo)',
                  style: AppText.ui(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: AppColors.ink3)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  static String _languageName(String? code) => switch (code) {
        'SW' => 'Kiswahili',
        'SO' => 'Soomaali',
        'AR' => 'Arabic',
        'FR' => 'French',
        _ => 'English',
      };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: AppText.ui(
            size: 13, weight: FontWeight.w700, color: AppColors.ink3));
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: AppCard(
        onTap: enabled ? onTap : null,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppText.ui(
                          size: 14, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.ui(
                          size: 12.5, color: AppColors.ink3)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.handleBase,
    required this.handleCheckDigit,
    required this.evmAddress,
  });

  final String handleBase;
  final String handleCheckDigit;
  final String evmAddress;

  @override
  Widget build(BuildContext context) {
    final short =
        '${evmAddress.substring(0, 6)}…${evmAddress.substring(evmAddress.length - 4)}';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR PAYMENT NAME',
              style: AppText.balanceLabel()),
          const SizedBox(height: 8),
          HandleChip(
              base: handleBase,
              checkDigit: handleCheckDigit,
              size: HandleChipSize.regular,
              copyable: true),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WALLET ADDRESS',
                        style: AppText.balanceLabel()),
                    const SizedBox(height: 4),
                    Text(short,
                        style: AppText.mono(
                            size: 13, color: AppColors.ink2)),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: 'Copy full wallet address',
                child: Pressable(
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: evmAddress));
                    AppSnackBar.show(context,
                        message: 'Address copied.');
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.line2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded,
                            size: 15, color: AppColors.ink2),
                        const SizedBox(width: 6),
                        Text('Copy',
                            style: AppText.ui(
                                size: 13,
                                weight: FontWeight.w700,
                                color: AppColors.ink2)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
