import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/pay_uri.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/screen_nav.dart';

/// "Scan to pay" — live camera QR scanning, not the still-image decoder
/// `qr_image_decoder.dart` uses for wallet-key restore. That one is a
/// pure-Dart one-shot decode, deliberately avoiding a native camera
/// dependency for a job that never needed live frames; this screen *is*
/// the live-frame job that tradeoff was declining to pay for, so it uses
/// `mobile_scanner` (ML Kit / AVFoundation) instead.
///
/// Only ever hands back a well-formed `jamiipay://pay/...` link (see
/// `parsePayUri`) — anything else scanned (a WiFi QR, a URL, a business
/// card) is silently ignored rather than passed through as garbage.
class ScanPayScreen extends StatefulWidget {
  const ScanPayScreen(
      {super.key,
      required this.onBack,
      required this.onScanned,
      this.onEnterManually});

  final VoidCallback onBack;
  final ValueChanged<ParsedPayUri> onScanned;
  final VoidCallback? onEnterManually;

  @override
  State<ScanPayScreen> createState() => _ScanPayScreenState();
}

class _ScanPayScreenState extends State<ScanPayScreen> {
  final _controller =
      MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);

  // Detection fires repeatedly while a code stays in frame — this stops
  // `onScanned` from being called more than once per successful scan
  // while the caller is still navigating away.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    var sawNonJamii = false;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final parsed = parsePayUri(raw);
      if (parsed == null) {
        sawNonJamii = true;
        continue;
      }
      if (parsed.amountTampered) {
        // Tampered amount: still hand over, caller must show warning.
      }
      _handled = true;
      unawaited(_controller.stop());
      widget.onScanned(parsed);
      return;
    }
    // Non-Jamii QR in frame: tell the user instead of silent ignore
    // (old behavior looked like a broken camera).
    if (sawNonJamii && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
          content: Text('Not a JamiiPay code — point at a JamiiPay QR.'),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: ScreenNav(
                title: 'Scan to pay',
                onBack: widget.onBack,
                trailing: Semantics(
                  button: true,
                  label: 'Toggle flashlight',
                  child: InkWell(
                    onTap: () => _controller.toggleTorch(),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.line2),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: ValueListenableBuilder(
                        valueListenable: _controller,
                        builder: (context, state, child) => Icon(
                          state.torchState == TorchState.on
                              ? Icons.flash_on
                              : Icons.flash_off,
                          color: AppColors.ink2,
                          size: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => _ScanError(error: error),
                  ),
                  // A plain framing square — enough to communicate "point
                  // here", without a full cutout overlay this feature
                  // doesn't need to justify.
                  IgnorePointer(
                    child: Container(
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.8),
                            width: 2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "Point your camera at someone else's JamiiPay QR code",
                            textAlign: TextAlign.center,
                            style:
                                AppText.ui(size: 13, color: Colors.white),
                          ),
                        ),
                        if (widget.onEnterManually != null) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: widget.onEnterManually,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white70),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Enter name manually',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanError extends StatelessWidget {
  const _ScanError({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Camera access is off for JamiiPay. Enable it in Settings to scan a QR code.',
      _ =>
        "Couldn't start the camera: ${error.errorDetails?.message ?? error.errorCode.name}",
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_outlined,
                size: 36, color: AppColors.coral),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: AppText.ui(size: 13, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
