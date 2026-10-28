import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'eternity_loader.dart';
import 'motion.dart';

/// No-spinner loading kit — the single replacement for every
/// `CircularProgressIndicator` in the app.
///
/// The signature wait indicator is the copper [EternityLoader]: an
/// infinity loop in the brand's copper gradient with a head of light
/// travelling it. The other widgets say *what's coming* or *what's
/// happening* around it:
/// - [AppLoading] — full-screen/region wait: copper loop + label.
/// - [LoadingVeil] — modal busy veil with a plain-language label for
///   money actions (send, cash-out, escrow…).
/// - [Delayed] — only shows its child after [delay]; kills the
///   flash-of-loader on fast responses (show nothing under ~300ms).
/// - [BusyLabel] — pulsing text for disabled busy buttons.
///
/// All animation collapses to static output under reduced motion (see
/// [reduceMotion]), and every widget carries a semantic label so screen
/// readers announce the wait instead of silence.
class Delayed extends StatefulWidget {
  const Delayed(
      {super.key, required this.child, this.delay = const Duration(milliseconds: 300)});

  final Widget child;
  final Duration delay;

  @override
  State<Delayed> createState() => _DelayedState();
}

class _DelayedState extends State<Delayed> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) => _show ? widget.child : const SizedBox.shrink();
}

/// Copper loop + label. [size] is the loop width and matches the
/// surrounding context (72 for full screens, ~48 for inline regions).
/// Pass [label] for waits likely to exceed ~1s — the words matter more
/// than the animation.
class LoopWithLabel extends StatelessWidget {
  const LoopWithLabel({super.key, this.size = 72, this.label});

  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    return Semantics(
      label: label ?? 'Loading',
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EternityLoader(width: size),
          if (label != null) ...[
            const SizedBox(height: 16),
            Text(label,
                textAlign: TextAlign.center,
                style: AppText.ui(
                    size: 14, weight: FontWeight.w600, color: AppColors.ink2)),
          ],
        ],
      ),
    );
  }
}

/// Full-screen/region wait: copper loop, shown only if the wait
/// outlasts [delay]. Drop-in replacement for
/// `Center(child: CircularProgressIndicator())`.
class AppLoading extends StatelessWidget {
  const AppLoading(
      {super.key, this.size = 72, this.label, this.delay = const Duration(milliseconds: 300)});

  final double size;
  final String? label;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Delayed(
        delay: delay,
        child: LoopWithLabel(size: size, label: label),
      ),
    );
  }
}

/// Modal busy veil for money actions. Use as a `showDialog` builder —
/// existing `Navigator.of(context).pop()` dismiss calls keep working:
///
/// ```dart
/// showDialog<void>(
///   context: context,
///   barrierDismissible: false,
///   builder: (_) => const LoadingVeil(message: 'Sending…'),
/// );
/// ```
class LoadingVeil extends StatelessWidget {
  const LoadingVeil({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: AppColors.navy800,
          border: Border.all(color: AppColors.line2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: LoopWithLabel(size: 56, label: message),
      ),
    );
  }
}

/// Pulsing text for a busy (disabled) button — pair with
/// `AppButton(isLoading: true)`.
class BusyLabel extends StatefulWidget {
  const BusyLabel({super.key, required this.text, this.color});

  final String text;
  final Color? color;

  @override
  State<BusyLabel> createState() => _BusyLabelState();
}

class _BusyLabelState extends State<BusyLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = AppText.ui(
        size: 14.5, weight: FontWeight.w700, color: widget.color ?? Colors.white);
    if (reduceMotion(context)) return Text(widget.text, style: style);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) =>
          Opacity(opacity: 0.55 + 0.45 * _c.value, child: Text(widget.text, style: style)),
    );
  }
}
