import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'motion.dart';

/// The payment-handle chip: base name + amber check-digit, e.g.
/// `amina7k3n` + `z`. This is the product's "signature" component — see
/// `.handle` in the mockup. The check digit exists so a mistyped or
/// deliberately-similar handle is caught before money moves.
enum HandleChipSize { small, regular, large }

class HandleChip extends StatelessWidget {
  const HandleChip({
    super.key,
    required this.base,
    required this.checkDigit,
    this.size = HandleChipSize.regular,
    this.onTap,
    this.copyable = false,
  });

  final String base;
  final String checkDigit;
  final HandleChipSize size;

  /// When set, the chip becomes a 48px-min pressable with haptic.
  final VoidCallback? onTap;

  /// When true, tap copies `base+checkDigit` and shows a check morph.
  /// Used on Receive/Home so the name feels owned, not decorative.
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final (double fontSize, EdgeInsets padding, EdgeInsets cdPadding) =
        switch (size) {
      HandleChipSize.small => (
          12,
          const EdgeInsets.fromLTRB(8, 3, 3, 3),
          const EdgeInsets.symmetric(horizontal: 5)
        ),
      HandleChipSize.regular => (
          15,
          const EdgeInsets.fromLTRB(10, 5, 4, 5),
          const EdgeInsets.symmetric(horizontal: 6, vertical: 1)
        ),
      HandleChipSize.large => (
          22,
          const EdgeInsets.fromLTRB(15, 9, 7, 9),
          const EdgeInsets.symmetric(horizontal: 9, vertical: 3)
        ),
    };

    final chip = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.129),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(base,
              style: AppText.mono(size: fontSize, weight: FontWeight.w500)),
          Padding(
            padding:
                EdgeInsets.only(left: size == HandleChipSize.small ? 5 : 7),
            child: Container(
              padding: cdPadding,
              decoration: BoxDecoration(
                color: AppColors.amber,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                checkDigit,
                style: AppText.mono(
                  size: size == HandleChipSize.small ? 11 : fontSize,
                  weight: FontWeight.w700,
                  color: AppColors.navy900,
                ),
              ),
            ),
          ),
          if (copyable) ...[
            const SizedBox(width: 6),
            Icon(Icons.copy_rounded, size: 14, color: AppColors.ink3),
          ],
        ],
      ),
    );

    if (onTap == null && !copyable) return chip;
    return Semantics(
      button: true,
      label: 'Payment name $base$checkDigit. Tap to copy.',
      child: Pressable(
        onTap: () {
          final full = '$base$checkDigit';
          if (copyable) {
            Clipboard.setData(ClipboardData(text: full));
          }
          onTap?.call();
        },
        borderRadius: BorderRadius.circular(10),
        child: chip,
      ),
    );
  }
}

/// "Say it over the phone" helper — e.g. `amina7k3n` → "amina seven kay
/// three en". Shown under the chip on Receive so names survive voice.
String phoneticHandle(String fullHandle) {
  const words = {
    '0': 'zero',
    '1': 'one',
    '2': 'two',
    '3': 'three',
    '4': 'four',
    '5': 'five',
    '6': 'six',
    '7': 'seven',
    '8': 'eight',
    '9': 'nine',
  };
  return fullHandle.split('').map((c) {
    if (words.containsKey(c)) return words[c]!;
    return c;
  }).join(' ');
}
