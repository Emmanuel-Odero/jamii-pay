import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// `.keypad` — the custom on-screen numeric keypad used for PIN entry. A
/// real device keyboard would work too, but the design specifically calls
/// for this large-target custom pad (worn fingerprints / low dexterity are
/// called out elsewhere in the design notes), so it's implemented as-is
/// rather than swapped for `TextField` + system keyboard.
class NumericKeypad extends StatelessWidget {
  const NumericKeypad(
      {super.key, required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  static const _keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '',
    '0',
    '⌫'
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 1.9,
      children: [
        for (final key in _keys)
          if (key.isEmpty)
            const SizedBox.shrink()
          else
            Material(
              color: AppColors.navy800,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: key == '⌫' ? onBackspace : () => onDigit(key),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: key == '⌫'
                      ? Icon(Icons.backspace_outlined,
                          size: 18, color: AppColors.ink)
                      : Text(key,
                          style:
                              AppText.mono(size: 19, weight: FontWeight.w500)),
                ),
              ),
            ),
      ],
    );
  }
}
