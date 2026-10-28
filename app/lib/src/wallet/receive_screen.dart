import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../data/pay_uri.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/handle_chip.dart';
import '../widgets/info_banner.dart';
import '../widgets/jamii_logo.dart';
import '../widgets/row_line.dart';
import '../widgets/screen_nav.dart';

/// Wallet → "Receive money". The paybill/account number are equal citizens
/// with the QR code, not a fallback — most senders read them off a
/// WhatsApp message on a feature phone, not scan a code.
///
/// "Share these details" generates an actual image — a branded card with
/// the handle, QR, and paybill/account, matching the mockup's own stated
/// concept ("Generates a shareable card with paybill, account and QR",
/// `designs/jammii-pay-mockup.html:2809`) — not just a text message, which
/// is all it did before.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen(
      {super.key,
      required this.onBack,
      required this.onRequestStkPush,
      required this.onTopUpWithCard});

  final VoidCallback onBack;

  /// "Prompt their phone" — real M-Pesa STK Push, not just displaying
  /// the paybill/account for them to dial manually.
  final VoidCallback onRequestStkPush;

  /// "Top up with card" — Stripe Checkout, for topping up *your own*
  /// wallet directly (unlike the M-Pesa button above, which prompts
  /// someone else's phone).
  final VoidCallback onTopUpWithCard;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _cardKey = GlobalKey();
  final _amountController = TextEditingController();
  bool _sharing = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double? get _requestedAmount {
    final amount = double.tryParse(_amountController.text);
    return amount != null && amount > 0 ? amount : null;
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletStore>().wallet;
    final fullHandle = wallet?.fullHandle ?? '';
    final base = wallet?.handleBase ?? '';
    final checkDigit = wallet?.handleCheckDigit ?? '';
    final requestedAmount = _requestedAmount;
    final payUri = buildPayUri(fullHandle, amountUsd: requestedAmount);

    return AppScreen(
      footer: AppButton(
        label: _sharing ? 'Preparing…' : 'Share these details',
        variant: AppButtonVariant.green,
        onPressed: wallet == null || _sharing
            ? null
            : () => _shareCard(fullHandle, requestedAmount),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Receive money', onBack: widget.onBack),
          // Optional — leaving this blank keeps the QR exactly what it
          // always was (just the handle); filling it in embeds the amount
          // so whoever scans it with JamiiPay's own scanner goes straight
          // to approving with their PIN instead of having to type it in.
          Text('Request a specific amount (optional)',
              style: AppText.ui(size: 12, color: AppColors.ink3)),
          const SizedBox(height: 8),
          AppCard(
            variant: requestedAmount != null
                ? AppCardVariant.selected
                : AppCardVariant.plain,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _amountController,
              onChanged: (_) => setState(() {}),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: AppText.mono(size: 15),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                prefixText: '\$ ',
                prefixStyle: AppText.mono(size: 15),
                hintText: 'Leave blank to let them choose',
                hintStyle: AppText.mono(size: 15, color: AppColors.ink3),
              ),
            ),
          ),
          const SizedBox(height: 9),
          RepaintBoundary(
            key: _cardKey,
            child: Container(
              // A flat opaque background for the capture — RepaintBoundary
              // renders exactly what's here, so this is also what ends up
              // in the shared image, not just what's visible on screen.
              color: AppColors.navy900,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(19),
                    child: Column(
                      children: [
                        const JamiiLogo(size: 40),
                        const SizedBox(height: 12),
                        Container(
                          width: 150,
                          height: 150,
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14)),
                          child: QrImageView(
                            data: payUri,
                            version: QrVersions.auto,
                            backgroundColor: Colors.white,
                            eyeStyle: QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: AppColors.navy900),
                            dataModuleStyle: QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: AppColors.navy900),
                          ),
                        ),
                        const SizedBox(height: 15),
                        HandleChip(
                            base: base,
                            checkDigit: checkDigit,
                            copyable: true),
                        if (fullHandle.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Say it: "${phoneticHandle(fullHandle)}" · tap to copy',
                            textAlign: TextAlign.center,
                            style: AppText.ui(
                                size: 12.5, color: AppColors.ink3),
                          ),
                        ],
                        const SizedBox(height: 9),
                        Text(
                          requestedAmount != null
                              ? 'Scan with JamiiPay to pay \$${requestedAmount.toStringAsFixed(2)} — or pay any amount via M-Pesa below'
                              : 'Scan with JamiiPay to pay any amount — or pay via M-Pesa below',
                          textAlign: TextAlign.center,
                          style: AppText.ui(size: 12, color: AppColors.ink3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 9),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Or pay by M-Pesa number',
                            style: AppText.ui(size: 12, color: AppColors.ink3)),
                        const SizedBox(height: 9),
                        RowLine(
                            label: 'Paybill',
                            value: '4 088 990',
                            valueColor: AppColors.amber),
                        RowLine(
                            label: 'Account',
                            value: fullHandle,
                            valueColor: AppColors.blue,
                            showBorder: false),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          const InfoBanner(
              icon: Icons.check_circle_outline,
              text:
                  "They don't need Jamii Pay. Anyone on M-Pesa can pay this."),
          const SizedBox(height: 9),
          AppButton(
              label: 'Prompt their phone to pay',
              variant: AppButtonVariant.outline,
              onPressed: widget.onRequestStkPush),
          const SizedBox(height: 9),
          AppButton(
              label: 'Top up with card',
              variant: AppButtonVariant.outline,
              onPressed: widget.onTopUpWithCard),
        ],
      ),
    );
  }

  Future<void> _shareCard(String fullHandle, double? requestedAmount) async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // 3x pixel ratio — this is a card meant to be read on someone else's
      // screen (WhatsApp, SMS), not just this device's.
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);

      final dir = await getTemporaryDirectory();
      final file = await File('${dir.path}/jamiipay_$fullHandle.png')
          .writeAsBytes(bytes);

      if (!mounted) return;
      final box = _cardKey.currentContext!.findRenderObject() as RenderBox;
      final origin = box.localToGlobal(Offset.zero) & box.size;
      final amountLine = requestedAmount != null
          ? ' for \$${requestedAmount.toStringAsFixed(2)}'
          : '';
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            'Pay me$amountLine on JamiiPay: $fullHandle\nOr pay by M-Pesa paybill 4 088 990, account $fullHandle.',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(context,
          message: 'Could not prepare the share card: $e',
          tone: SnackTone.danger);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
