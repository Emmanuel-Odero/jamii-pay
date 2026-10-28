import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Cycles a small fixed set of theme colours for avatar backgrounds —
/// mirrors `designs/jammii-pay-prototype.html`'s `pal(i)` helper (`info,
/// good, warn, alert, pri`, cycling every 5). Used anywhere a list of
/// people needs visually distinct avatars without per-person colour data
/// (Contacts rows, Group member rows, Search's "People" card).
Color avatarPaletteColor(int index) {
  final colors = [
    AppColors.blue,
    AppColors.green,
    AppColors.amber,
    AppColors.coral,
    AppColors.blue
  ];
  return colors[index % colors.length];
}
