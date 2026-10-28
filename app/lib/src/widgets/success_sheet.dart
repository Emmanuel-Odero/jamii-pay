import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/handle_chip.dart';
import '../widgets/motion.dart';

/// Money-moment celebration (Rec #1): the emotional payoff for an
/// irreversible send. Check draws itself, amount counts up, haptic fires,
/// then `[Share receipt] [Done]`.
///
/// Why a sheet, not a snackbar: a snackbar says "done (maybe?)". A 300ms
/// ceremony says "done — feel good". Respects reduced-motion (fade only)
/// and never traps the user (swipe/tap-out dismisses to Home state).
class SuccessSheet extends StatefulWidget {
  const SuccessSheet({
    super.key,
    required this.amountUsd,
    required this.recipientLabel,
    this.base,
    this.checkDigit,
    this.onShare,
    required this.onDone,
  });

  final double amountUsd;
  final String recipientLabel;
  final String? base;
  final String? checkDigit;
  final VoidCallback? onShare;
  final VoidCallback onDone;

  static Future<void> show(
    BuildContext context, {
    required double amountUsd,
    required String recipientLabel,
    String? base,
    String? checkDigit,
    VoidCallback? onShare,
    required VoidCallback onDone,
  }) {
    Haptics.confirm();
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: AppColors.navy800,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SuccessSheet(
          amountUsd: amountUsd,
          recipientLabel: recipientLabel,
          base: base,
          checkDigit: checkDigit,
          onShare: onShare,
          onDone: onDone,
        ),
      ),
    );
  }

  @override
  State<SuccessSheet> createState() => _SuccessSheetState();
}

class _SuccessSheetState extends State<SuccessSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320))
    ..forward();
  late final Animation<double> _check =
      CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
  late final Animation<double> _rise =
      CurvedAnimation(parent: _c, curve: const Interval(0.25, 1));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.line2,
                  borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 20),
          ScaleTransition(
            scale: reduce ? const AlwaysStoppedAnimation(1) : _check,
            child: Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.14),
                border: Border.all(
                    color: AppColors.green.withValues(alpha: 0.5), width: 1.5),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.green.withValues(alpha: 0.25),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Semantics(
                label: 'Payment sent successfully',
                child: Icon(Icons.check_rounded,
                    size: 42, color: AppColors.green),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FadeTransition(
            opacity: reduce ? const AlwaysStoppedAnimation(1) : _rise,
            child: Column(
              children: [
                _CountUpAmount(target: widget.amountUsd, reduce: reduce),
                const SizedBox(height: 6),
                if (widget.base != null && widget.checkDigit != null)
                  HandleChip(
                      base: widget.base!,
                      checkDigit: widget.checkDigit!,
                      size: HandleChipSize.regular)
                else
                  Text(widget.recipientLabel,
                      style: AppText.ui(
                          size: 14,
                          weight: FontWeight.w600,
                          color: AppColors.ink2)),
                const SizedBox(height: 4),
                Text('Arrives in ~15 seconds · receipt saved to Activity',
                    style:
                        AppText.ui(size: 12.5, color: AppColors.ink3)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onDone();
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    side: BorderSide(color: AppColors.line2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Done',
                      style: AppText.ui(
                          size: 14,
                          weight: FontWeight.w700,
                          color: AppColors.ink)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: widget.onShare == null
                      ? null
                      : () {
                          Haptics.select();
                          Navigator.of(context).pop();
                          widget.onShare!();
                        },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    backgroundColor: AppColors.green,
                    disabledBackgroundColor:
                        AppColors.navy600.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Share receipt',
                      style: AppText.ui(
                          size: 14,
                          weight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Amount counts 0 → target in ~400ms with tabular figures (no jitter).
class _CountUpAmount extends StatefulWidget {
  const _CountUpAmount({required this.target, required this.reduce});
  final double target;
  final bool reduce;

  @override
  State<_CountUpAmount> createState() => _CountUpAmountState();
}

class _CountUpAmountState extends State<_CountUpAmount>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420))
    ..forward();

  @override
  void initState() {
    super.initState();
    if (widget.reduce) _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Text(
        '\$${(widget.target * _c.value).toStringAsFixed(2)} sent',
        style: AppText.balance(size: 34).copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
