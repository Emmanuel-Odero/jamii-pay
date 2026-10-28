import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// A reusable "are you sure?" dialog — same themed `AlertDialog` shell
/// (`navy800` background, `AppText` typography) that used to be hand-rolled
/// per call site (sign-out, and every future destructive/irreversible
/// action: leaving a group, cancelling recovery, removing a guardian).
/// Returns `true` only if the user tapped [confirmLabel]; `false`/`null`
/// (cancel, dismiss, back button) both mean "don't proceed".
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.navy800,
      title: Text(title, style: AppText.ui(size: 15, weight: FontWeight.w700)),
      content:
          Text(message, style: AppText.ui(size: 12.5, color: AppColors.ink2)),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel,
              style: TextStyle(color: destructive ? AppColors.coral : null)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
