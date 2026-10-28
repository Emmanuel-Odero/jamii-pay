import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// The mockup's "Hold to confirm →" gesture on Send — a deliberate friction
/// control (the design's own rationale: sends can't be reversed, so a tap
/// shouldn't be enough) that was previously just a plain tap `AppButton`.
/// Holding for [holdDuration] fills the button and fires [onConfirmed];
/// releasing early cancels and resets.
class HoldToConfirmButton extends StatefulWidget {
  const HoldToConfirmButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.holdDuration = const Duration(milliseconds: 900),
  });

  final String label;
  final VoidCallback? onConfirmed;
  final Duration holdDuration;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(vsync: this, duration: widget.holdDuration);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    if (widget.onConfirmed == null) return;
    HapticFeedback.selectionClick();
    _controller.forward(from: _controller.value).then((_) {
      // then (not whenCompleteOrCancel): a cancelled hold must NEVER fire.
      // The old whenCompleteOrCancel could confirm after slide-off.
      if (_controller.isCompleted && mounted) {
        HapticFeedback.mediumImpact();
        widget.onConfirmed!();
        _controller.reset();
      }
    });
  }

  void _cancel() {
    if (!_controller.isCompleted) _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onConfirmed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      hint: 'Press and hold to confirm. Double-tap and hold with a screen reader.',
      child: GestureDetector(
      onTapDown: enabled ? (_) => _start() : null,
      onTapUp: enabled ? (_) => _cancel() : null,
      onTapCancel: enabled ? _cancel : null,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: double.infinity,
            height: 52,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: enabled
                  ? AppColors.blue.withValues(alpha: 0.35)
                  : AppColors.navy600.withValues(alpha: 0.5),
              border: Border.all(
                  color: enabled ? Colors.transparent : AppColors.line),
              borderRadius: BorderRadius.circular(kBtnRadius),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _controller.value,
                  child: Container(color: AppColors.blue),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _controller.value > 0.05 && _controller.value < 1
                          ? 'Holding… ${(_controller.value * 100).round()}%'
                          : widget.label,
                      style: AppText.ui(
                          size: 13.5,
                          weight: FontWeight.w700,
                          color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward,
                        size: 16, color: Colors.white),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      ),
    );
  }
}
