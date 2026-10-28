import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'eternity_loader.dart';
import 'motion.dart';

/// Pull-to-refresh headed by the copper eternity loop — a drop-in
/// replacement for Material's [RefreshIndicator], whose circular spinner
/// is exactly the cliché this app retired.
///
/// Dragging down past the top edge stretches a header (max 90px) where
/// the loop fades in with the pull; past the 70px trigger, releasing
/// fires [onRefresh] and the header parks at 76px with the loop running
/// until the future completes. Same contract as [RefreshIndicator]:
/// [child] must be a scrollable, [onRefresh] does the reload.
///
/// Bounce physics required for the overscroll to exist — every call site
/// already uses [AlwaysScrollableScrollPhysics]/iOS bounce.
class EternityRefresh extends StatefulWidget {
  const EternityRefresh(
      {super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<EternityRefresh> createState() => _EternityRefreshState();
}

class _EternityRefreshState extends State<EternityRefresh> {
  static const _trigger = 70.0;
  static const _maxDrag = 110.0;
  static const _parkedHeight = 76.0;

  double _dragExtent = 0;
  double _gestureMax = 0;
  bool _refreshing = false;

  bool _handle(ScrollNotification n) {
    if (n.depth != 0 || _refreshing) return false;
    if (n is ScrollStartNotification) {
      // New gesture: forget the previous pull. No setState — nothing
      // visible changes on press alone.
      _gestureMax = 0;
    } else if (n is OverscrollNotification && n.overscroll < 0) {
      setState(() {
        _dragExtent = (_dragExtent - n.overscroll).clamp(0, _maxDrag);
        _gestureMax = math.max(_gestureMax, _dragExtent);
      });
    } else if (n is ScrollUpdateNotification && n.metrics.pixels < 0) {
      setState(() {
        _dragExtent = (-n.metrics.pixels).clamp(0, _maxDrag);
        _gestureMax = math.max(_gestureMax, _dragExtent);
      });
    } else if (n is ScrollEndNotification) {
      // Judge by the gesture's deepest pull: the spring-back runs
      // ballistic updates that shrink the live extent before/around the
      // drag-end notification, so the live value alone would miss
      // legitimate pulls.
      if (_gestureMax >= _trigger) {
        _startRefresh();
      } else if (_dragExtent > 0) {
        setState(() => _dragExtent = 0);
      }
      _gestureMax = 0;
    }
    return false;
  }

  Future<void> _startRefresh() async {
    setState(() {
      _refreshing = true;
      _dragExtent = 0;
    });
    Haptics.select();
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Collapsed and idle: render nothing — this also keeps the looping
    // painter (and its perpetual frames) out of the tree when there's no
    // pull in progress.
    if (!_refreshing && _dragExtent <= 0) {
      return NotificationListener<ScrollNotification>(
        onNotification: _handle,
        child: Column(
          children: [
            const SizedBox.shrink(),
            Expanded(child: widget.child),
          ],
        ),
      );
    }
    final double height =
        _refreshing ? _parkedHeight : _dragExtent.clamp(0.0, 90.0);
    final progress = (_dragExtent / _trigger).clamp(0.0, 1.0);
    return NotificationListener<ScrollNotification>(
      onNotification: _handle,
      child: Column(
        children: [
          SizedBox(
            height: height,
            child: _refreshing
                ? const Center(child: EternityLoader(width: 44))
                : Opacity(
                    opacity: progress,
                    child: Center(
                      child: EternityLoader(
                        width: 30 + 14 * progress,
                        strokeWidth: 4,
                      ),
                    ),
                  ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}
