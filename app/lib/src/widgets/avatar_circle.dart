import 'package:flutter/material.dart';

import '../theme/app_text.dart';

/// `.mem`/contact-list avatar — a rounded-square initials badge. `size`
/// controls the box; `colorIndex` picks the background via
/// `avatarPaletteColor` (pass it directly rather than a `Color` so every
/// call site cycles consistently without each one re-deriving an index).
class AvatarCircle extends StatelessWidget {
  const AvatarCircle(
      {super.key, required this.name, required this.color, this.size = 40});

  final String name;
  final Color color;
  final double size;

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(_initials,
          style: AppText.ui(
              size: size * 0.35, weight: FontWeight.w800, color: Colors.white)),
    );
  }
}
