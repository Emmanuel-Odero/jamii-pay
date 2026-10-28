import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'avatar_circle.dart';

/// `.mem` — a group member row: avatar, name (+"(you)" suffix), a
/// sub-stat line, and a right-aligned stat (vote-share %, vote status,
/// etc.), coloured to match that member's `SegmentedBar` segment.
class GroupMemberRow extends StatelessWidget {
  const GroupMemberRow({
    super.key,
    required this.name,
    required this.isYou,
    required this.subStat,
    required this.trailingText,
    required this.trailingColor,
    required this.avatarColor,
    this.showBorder = true,
  });

  final String name;
  final bool isYou;
  final String subStat;
  final String trailingText;
  final Color trailingColor;
  final Color avatarColor;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: showBorder
            ? Border(bottom: BorderSide(color: AppColors.line))
            : null,
      ),
      child: Row(
        children: [
          AvatarCircle(name: name, color: avatarColor, size: 36),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isYou ? '$name (you)' : name,
                  style: AppText.ui(size: 13, weight: FontWeight.w600),
                ),
                const SizedBox(height: 1),
                Text(subStat,
                    style: AppText.ui(size: 10.5, color: AppColors.ink3)),
              ],
            ),
          ),
          Text(trailingText,
              style: AppText.mono(
                  size: 11.5, weight: FontWeight.w700, color: trailingColor)),
        ],
      ),
    );
  }
}
