import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../data/wallet_key_backup_codec.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_screen.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/info_banner.dart';
import '../widgets/jamii_logo.dart';
import '../widgets/screen_nav.dart';

/// Premium wallet-key backup certificate (v2 split backup).
///
/// Design (#1 @ 9.5/10 + Emergency-Kit borrowings):
/// - QR itself stays dark-on-light for 100% scannability: navy ink
///   on a cream island, generous quiet-zone padding, Level H.
/// - Rounded dot modules + circular eyes for a soft, classy feel.
/// - Center mark as a medallion (white halo + ring) instead of a raw
///   square pasted over modules — scans better, looks finished.
/// - Banknote framing: deep-navy certificate, thin gold hairline,
///   eyebrow + handle + created date + "needs image + PIN + approval"
///   line, so the exported PNG reads as something to protect and is
///   identifiable without scanning.
///
/// Security: the QR holds only the PIN-wrapped random share `S1` of a
/// 2-of-2 split — brute-forcing its PIN yields nothing usable without the
/// server-held `S2`. Restores complete only via the app + release oracle
/// together. The temp export file is wiped after sharing, the filename
/// carries no handle, and "I've saved it" stays locked until the
/// save-checklist is complete.
class WalletKeyBackupScreen extends StatefulWidget {
  const WalletKeyBackupScreen(
      {super.key,
      required this.qrPayload,
      required this.addressHex,
      required this.onDone});

  /// v2 envelope JSON — embedded in the QR verbatim.
  final String qrPayload;
  final String addressHex;
  final VoidCallback onDone;

  @override
  State<WalletKeyBackupScreen> createState() => _WalletKeyBackupScreenState();
}

class _WalletKeyBackupScreenState extends State<WalletKeyBackupScreen> {
  final _cardKey = GlobalKey();
  bool _sharing = false;
  bool _savedOffline = false;
  bool _pinKept = false;
  bool _understood = false;

  bool get _checklistDone => _savedOffline && _pinKept && _understood;

  /// Navy ink — softer than pure black, still ~15:1 on cream.
  static const _qrInk = Color(0xFF101B33);
  static const _qrPaper = Color(0xFFFFFDF4);
  static const _gold = Color(0xFFC8A96A);

  String _createdLabel(DateTime now) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.qrPayload;
    final addr = widget.addressHex;
    final shortAddr = addr.length > 10
        ? '${addr.substring(0, 6)}…${addr.substring(addr.length - 4)}'
        : addr;
    final handle = context.watch<WalletStore>().wallet?.fullHandle ?? '';
    final created = _createdLabel(DateTime.now());
    // The card identifies itself: version + short backup id, so support
    // (and the owner, months later) can tell prints apart without scanning.
    String versionLine = 'v2 split backup';
    try {
      final info = WalletKeyBackupCodec.inspect(payload);
      final shortId = info.backupId != null && info.backupId!.length > 8
          ? '${info.backupId!.substring(0, 8)}…'
          : info.backupId;
      versionLine = shortId != null
          ? '${info.label} • ID $shortId'
          : info.label;
    } catch (_) {
      // Payload was just minted by the bridge — inspect cannot fail;
      // keep the static fallback rather than crashing the screen.
    }

    return AppScreen(
      footer: Column(
        children: [
          AppButton(
            label: _sharing ? 'Preparing…' : 'Save / print this backup',
            variant: AppButtonVariant.green,
            onPressed: _sharing ? null : () => _confirmAndShare(payload),
          ),
          const SizedBox(height: 9),
          _CheckRow(
            checked: _savedOffline,
            label: 'Printed it or saved it offline (not in chat or cloud Photos)',
            onTap: () => setState(() => _savedOffline = !_savedOffline),
          ),
          _CheckRow(
            checked: _pinKept,
            label: 'Key PIN memorized or written down separately',
            onTap: () => setState(() => _pinKept = !_pinKept),
          ),
          _CheckRow(
            checked: _understood,
            label: 'I know restoring needs this file + key PIN + approval in the app',
            onTap: () => setState(() => _understood = !_understood),
          ),
          const SizedBox(height: 9),
          AppButton(
              label: "I've saved it",
              variant: AppButtonVariant.outline,
              onPressed: _checklistDone ? widget.onDone : null),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenNav(title: 'Your wallet key'),
          Text('Store this somewhere only you can reach. Print it if you can.',
              style: AppText.screenSub()),
          const SizedBox(height: 12),
          RepaintBoundary(
            key: _cardKey,
            child: Container(
              // Opaque capture background — this is exactly what lands in
              // the shared PNG, not just what is visible on screen.
              color: AppColors.navy900,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.navy800, AppColors.navy900],
                  ),
                  border: Border.all(color: _gold.withValues(alpha: 0.55)),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const JamiiLogo(size: 30),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('JAMIIPAY • WALLET KEY',
                                style: AppText.mono(
                                    size: 11,
                                    weight: FontWeight.w700,
                                    color: _gold,
                                    letterSpacing: 1.8)),
                            const SizedBox(height: 2),
                            Text('Keep private — needs key PIN + approval',
                                style: AppText.ui(
                                    size: 12, color: AppColors.ink2)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Cream island: the scannable unit. Padding doubles as
                    // the quiet zone; never let text/frames intrude.
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _qrPaper,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: _gold.withValues(alpha: 0.35)),
                      ),
                      child: SizedBox(
                        width: 200,
                        height: 200,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            QrImageView(
                              data: payload,
                              version: QrVersions.auto,
                              // H — survives the ~20% center medallion.
                              errorCorrectionLevel: QrErrorCorrectLevel.H,
                              backgroundColor: _qrPaper,
                              eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.circle,
                                  color: _qrInk),
                              dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape:
                                      QrDataModuleShape.circle,
                                  color: _qrInk),
                              // No embeddedImage: the medallion below is
                              // the halo + mark with a controlled ring.
                              gapless: false,
                            ),
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: _qrInk, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.18),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(5),
                              child: const JamiiLogo(size: 28),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (handle.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: Text(handle,
                            style: AppText.mono(
                                size: 13,
                                weight: FontWeight.w700,
                                color: AppColors.ink)),
                      ),
                    if (handle.isNotEmpty) const SizedBox(height: 8),
                    Text(
                      'Created $created  •  $shortAddr',
                      textAlign: TextAlign.center,
                      style: AppText.mono(size: 11, color: AppColors.ink3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      versionLine,
                      textAlign: TextAlign.center,
                      style: AppText.mono(
                          size: 10,
                          weight: FontWeight.w700,
                          color: _gold,
                          letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 12),
                    Container(height: 1, color: _gold.withValues(alpha: 0.3)),
                    const SizedBox(height: 10),
                    Text(
                      'Needs: this image + key PIN + approval  •  Restore: app → Restore from key',
                      textAlign: TextAlign.center,
                      style: AppText.ui(size: 11.5, color: AppColors.ink2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          const InfoBanner(
            icon: Icons.warning_amber_rounded,
            tone: BannerTone.warning,
            text:
                'This file alone cannot move your money — restoring also needs your key PIN plus approval in the app. '
                'Still, print it or save it offline (never chat, email, or cloud Photos): '
                "it's your only way back in if you lose this phone without recovery guardians.",
          ),
        ],
      ),
    );
  }

  /// Pre-share guardrail: the system sheet offers chat apps, email, and
  /// cloud drives first — exactly where a backup must never go. One
  /// explicit confirmation keeps honest users honest.
  Future<void> _confirmAndShare(String payload) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep it offline'),
        content: const Text(
            'Never send this to chat, email, or cloud Photos — anyone who collects it can keep trying your PIN forever.\n\nPrint it, or save it to Files on this device only.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Print / save offline')),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    await _shareCard(payload);
  }

  Future<void> _shareCard(String payload) async {
    setState(() => _sharing = true);
    // Generic filename: no handle, no address — a leaked filename alone
    // should not advertise whose money it unlocks.
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    File? file;
    try {
      final boundary =
          _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // 4x — this PNG is meant to survive printing on paper and a later
      // photo-scan, not just on-screen sharing.
      final image = await boundary.toImage(pixelRatio: 4.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);

      final dir = await getTemporaryDirectory();
      file = await File('${dir.path}/backup_$stamp.png').writeAsBytes(bytes);

      if (!mounted) return;
      // iOS requires an anchor rect for the share sheet's popover (and, as
      // of a recent share_plus version, enforces this on iPhone too, not
      // just iPad) — reuse the card's own on-screen bounds as the anchor.
      final box = _cardKey.currentContext!.findRenderObject() as RenderBox;
      final origin = box.localToGlobal(Offset.zero) & box.size;
      final result = await Share.shareXFiles(
        [XFile(file.path)],
        text:
            'My JamiiPay wallet key backup. Keep this offline and private — it needs my key PIN plus approval in the app to restore.',
        sharePositionOrigin: origin,
      );
      if (!mounted) return;
      // The system share sheet gives no other feedback of its own — without
      // this, a successful save/share looks identical to nothing happening.
      if (result.status == ShareResultStatus.success) {
        AppSnackBar.show(context,
            message: 'Saved. Print it or keep it offline, somewhere only you can reach.',
            tone: SnackTone.success);
      }
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(context,
          message: 'Could not prepare the backup image: $e',
          tone: SnackTone.danger);
    } finally {
      // Wipe the temp export — the user's real copy is wherever they
      // saved/printed via the sheet; nothing usable should linger in tmp.
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
      if (mounted) setState(() => _sharing = false);
    }
  }
}

/// One row of the save checklist gating "I've saved it".
class _CheckRow extends StatelessWidget {
  const _CheckRow(
      {required this.checked, required this.label, required this.onTap});

  final bool checked;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: checked ? AppColors.green : Colors.transparent,
                border: Border.all(
                    color: checked ? AppColors.green : AppColors.line2,
                    width: 1.5),
                borderRadius: BorderRadius.circular(7),
              ),
              child: checked
                  ? Icon(Icons.check, size: 14, color: AppColors.onGreen)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: AppText.ui(
                      size: 12.5,
                      color: checked ? AppColors.ink : AppColors.ink2)),
            ),
          ],
        ),
      ),
    );
  }
}
