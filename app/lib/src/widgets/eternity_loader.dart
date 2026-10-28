import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'motion.dart';

/// Copper eternity-loop loader — the app's signature wait indicator.
///
/// An infinity loop drawn in the brand's own copper gradient (the same
/// coral `#FF5E3A` → orange `#FF8A3D` → amber `#FFC53D` that flows through
/// the logo's swoosh), with a single head of light travelling the loop
/// and a fading comet trail behind it. One continuous motion, no start
/// or end — the wait feels like drift, not a countdown.
///
/// The loop is a Bernoulli lemniscate, so the head naturally hurries
/// through the crossing and lingers around the bends — that ease is what
/// makes it read as a wave rather than a spinner. A faint full-loop
/// track underneath keeps the shape legible at a glance.
///
/// Under reduced motion ([reduceMotion]) it renders one static loop in
/// the same gradient — no animation, same meaning.
class EternityLoader extends StatefulWidget {
  const EternityLoader({super.key, this.width = 72, this.strokeWidth = 5});

  /// Full width of the loop. Height is ~55% of this.
  final double width;
  final double strokeWidth;

  @override
  State<EternityLoader> createState() => _EternityLoaderState();
}

class _EternityLoaderState extends State<EternityLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.width, widget.width * 0.55);
    if (reduceMotion(context)) {
      return CustomPaint(
        size: size,
        painter: _LoopPainter(
          progress: 0.35,
          staticFrame: true,
          strokeWidth: widget.strokeWidth,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        size: size,
        painter: _LoopPainter(
          progress: _c.value,
          staticFrame: false,
          strokeWidth: widget.strokeWidth,
        ),
      ),
    );
  }
}

/// Bernoulli lemniscate samples, t in [0, 2π). Index i of [samples]
/// maps to t = i/samples * 2π.
List<Offset> _lemniscate(double halfWidth, double halfHeight, int samples) {
  final pts = <Offset>[];
  for (var i = 0; i < samples; i++) {
    final t = i / samples * 2 * math.pi;
    final s = math.sin(t);
    final c = math.cos(t);
    final d = 1 + s * s;
    pts.add(Offset(halfWidth * c / d, halfHeight * s * c / d));
  }
  return pts;
}

class _LoopPainter extends CustomPainter {
  _LoopPainter({
    required this.progress,
    required this.staticFrame,
    required this.strokeWidth,
  });

  final double progress;
  final bool staticFrame;
  final double strokeWidth;

  static const _samples = 220;
  static const _trail = 90;

  /// Brand copper gradient: coral → orange → amber (logo swoosh).
  static const _copper = [
    Color(0xFFFF5E3A),
    Color(0xFFFF8A3D),
    Color(0xFFFFC53D),
  ];

  Color _copperAt(double t) {
    // t in [0,1]: coral (tail) → amber (head).
    if (t <= 0.5) {
      return Color.lerp(_copper[0], _copper[1], t * 2)!;
    }
    return Color.lerp(_copper[1], _copper[2], (t - 0.5) * 2)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final pts = _lemniscate(size.width / 2 - strokeWidth, size.height / 2 - strokeWidth, _samples)
        .map((p) => Offset(p.dx + cx, p.dy + cy))
        .toList();

    Path pathFrom(int from, int count) {
      final path = Path();
      path.moveTo(pts[from % _samples].dx, pts[from % _samples].dy);
      for (var k = 1; k <= count; k++) {
        final p = pts[(from + k) % _samples];
        path.lineTo(p.dx, p.dy);
      }
      return path;
    }

    // Faint full-loop track.
    canvas.drawPath(
      pathFrom(0, _samples),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = AppColors.line2,
    );

    if (staticFrame) {
      // One calm gradient pass, no comet.
      for (var s = 0; s < 24; s++) {
        final from = (s * _samples / 24).floor();
        canvas.drawPath(
          pathFrom(from, (_samples / 24).ceil() + 1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeCap = StrokeCap.round
            ..color = _copperAt(s / 23).withValues(alpha: 0.85),
        );
      }
      return;
    }

    // Comet trail: 90 samples behind the head, alpha + copper ramp.
    const segments = 18;
    final head = (progress * _samples).floor();
    for (var s = 0; s < segments; s++) {
      final t = s / (segments - 1); // 0 tail → 1 head
      final from = head - _trail + (t * _trail).floor();
      canvas.drawPath(
        pathFrom(from, (_trail / segments).ceil() + 1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * (0.55 + 0.45 * t)
          ..strokeCap = StrokeCap.round
          ..color = _copperAt(t).withValues(alpha: 0.08 + 0.92 * t * t),
      );
    }

    // Head of light + soft glow.
    final hp = pts[head % _samples];
    canvas.drawCircle(
      hp,
      strokeWidth * 1.9,
      Paint()..color = _copper[2].withValues(alpha: 0.22),
    );
    canvas.drawCircle(hp, strokeWidth * 0.95, Paint()..color = _copper[2]);
    canvas.drawCircle(
      hp,
      strokeWidth * 0.42,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(_LoopPainter old) =>
      old.progress != progress || old.staticFrame != staticFrame;
}
