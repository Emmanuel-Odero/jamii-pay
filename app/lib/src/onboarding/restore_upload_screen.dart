import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/qr_image_decoder.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_screen.dart';
import '../widgets/info_banner.dart';
import '../widgets/screen_nav.dart';

/// "Restore from wallet key", step 1 of 3 — pick the QR image the person
/// downloaded from `WalletKeyBackupScreen` and decode it. Reads a still
/// image, not the live camera: this is a file someone saved (Photos, a
/// USB drive mounted to the Files app, an email attachment), not
/// something to scan off another screen.
///
/// Styled to match the premium backup certificate (navy + gold) so the
/// person recognises the file they are looking for.
class RestoreUploadScreen extends StatefulWidget {
  const RestoreUploadScreen(
      {super.key,
      required this.onBack,
      required this.onDecoded,
      this.errorText});

  final VoidCallback onBack;
  final ValueChanged<String> onDecoded;
  final String? errorText;

  @override
  State<RestoreUploadScreen> createState() => _RestoreUploadScreenState();
}

class _RestoreUploadScreenState extends State<RestoreUploadScreen> {
  bool _busy = false;
  String? _error;

  static const _gold = Color(0xFFC8A96A);
  static const _qrPaper = Color(0xFFFFFDF4);

  @override
  void initState() {
    super.initState();
    _error = widget.errorText;
  }

  Future<void> _pickAndDecode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) {
        setState(() => _busy = false);
        return;
      }
      final bytes = await File(picked.path).readAsBytes();
      // Runs on a background isolate — zxing's decode over a ~1200px
      // image is real CPU work, not something to do on the UI thread.
      final raw = await compute(decodeQrFromImageBytes, bytes);
      if (raw == null) {
        setState(() {
          _busy = false;
          _error =
              "Couldn't find a QR code in that image. Try the navy + gold Wallet Key certificate — not a fresh photo of a screen.";
        });
        return;
      }
      widget.onDecoded(raw);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not read that image: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      footer: AppButton(
        label: _busy ? 'Reading…' : 'Choose Wallet Key image',
        variant: AppButtonVariant.green,
        onPressed: _busy ? null : _pickAndDecode,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Restore from wallet key', onBack: widget.onBack),
          Text('WALLET KEY • STEP 1 OF 3',
              style: AppText.mono(
                  size: 11,
                  weight: FontWeight.w700,
                  color: _gold,
                  letterSpacing: 1.8)),
          const SizedBox(height: 8),
          Text('Upload your Wallet Key',
              style: AppText.screenTitle(size: 22)),
          const SizedBox(height: 8),
          Text(
              'Find the navy + gold QR certificate you saved or printed when you set this wallet up.',
              style: AppText.screenSub()),
          const SizedBox(height: 12),
          const _StepsRow(gold: _gold),
          const SizedBox(height: 12),
          if (_error != null) ...[
            InfoBanner(
                icon: Icons.error_outline,
                tone: BannerTone.danger,
                text: _error!),
            const SizedBox(height: 12),
          ],
          // Miniature of the backup certificate — the visual target the
          // person is hunting for in Photos / Files.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.navy800, AppColors.navy900],
              ),
              border: Border.all(color: _gold.withValues(alpha: 0.55)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _qrPaper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _gold.withValues(alpha: 0.35)),
                  ),
                  child: const Icon(Icons.qr_code_2,
                      size: 40, color: Color(0xFF101B33)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('JAMIIPAY • WALLET KEY',
                          style: AppText.mono(
                              size: 10,
                              weight: FontWeight.w700,
                              color: _gold,
                              letterSpacing: 1.4)),
                      const SizedBox(height: 4),
                      Text('jamiipay_wallet_key.png',
                          style: AppText.mono(
                              size: 12,
                              weight: FontWeight.w700,
                              color: AppColors.ink)),
                      const SizedBox(height: 4),
                      Text(
                        "It's the certificate you saved to Photos or shared to yourself — not a fresh photo of a screen.",
                        style:
                            AppText.ui(size: 11.5, color: AppColors.ink2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 1 Upload → 2 Key PIN → 3 Wallet PIN, matching `restore_from_key_flow`.
class _StepsRow extends StatelessWidget {
  const _StepsRow({required this.gold});

  final Color gold;

  @override
  Widget build(BuildContext context) {
    Widget step(String n, String label, bool active) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? gold : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                  color: active ? gold : AppColors.line2, width: 1.5),
            ),
            child: Text(n,
                style: AppText.mono(
                    size: 11,
                    weight: FontWeight.w700,
                    color: active ? AppColors.navy900 : AppColors.ink3)),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: AppText.ui(
                  size: 11.5,
                  weight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? AppColors.ink : AppColors.ink3)),
        ],
      );
    }

    Widget connector() => Expanded(
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: AppColors.line2,
          ),
        );

    return Row(
      children: [
        step('1', 'Upload', true),
        connector(),
        step('2', 'Key PIN', false),
        connector(),
        step('3', 'Wallet PIN', false),
      ],
    );
  }
}
