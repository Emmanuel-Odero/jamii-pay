import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Premium motion + haptic map (Rec #10).
///
/// One place for "how the app *feels*": every tactile moment goes through
/// here so timing stays consistent (150-300ms, transform/opacity only) and
/// reduced-motion users always get the calm fallback.
///
/// Map:
/// - select (tap chip, filter, option): selectionClick
/// - confirm (money sent, PIN ok, vote cast): mediumImpact
/// - received (money in): heavyImpact (respects silent mode — haptic only)
/// - error (wrong PIN, validation): vibrate (double-tap pattern)
class Haptics {
  const Haptics._();

  static Future<void> select() => HapticFeedback.selectionClick();
  static Future<void> confirm() => HapticFeedback.mediumImpact();
  static Future<void> received() => HapticFeedback.heavyImpact();
  static Future<void> error() => HapticFeedback.vibrate();
}

/// True when the OS asks for reduced motion — all scale/slide/rotation
/// must collapse to opacity-only fades (or instant appearance).
bool reduceMotion(BuildContext context) =>
    MediaQuery.of(context).disableAnimations ||
    MediaQuery.of(context).accessibleNavigation;

/// Premium pressable: 3% scale down + slight dim in 150ms, spring back.
/// Replaces dead `InkWell`-only cells (quick actions, cards) that gave no
/// physical acknowledgement — "did my tap land?" is terrifying with money.
class Pressable extends StatefulWidget {
  const Pressable(
      {super.key, required this.child, this.onTap, this.borderRadius});

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    return GestureDetector(
      onTapDown: (_) {
        if (widget.onTap == null) return;
        setState(() => _down = true);
      },
      onTapUp: (_) {
        if (widget.onTap == null) return;
        setState(() => _down = false);
        Haptics.select();
        widget.onTap!();
      },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: !reduce && _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _down ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: widget.child,
        ),
      ),
    );
  }
}
