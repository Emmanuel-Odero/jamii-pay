import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The real brand mark, extracted verbatim from the `<symbol id="jamii-logo">`
/// in `designs/jammii-pay-mockup.html` into `assets/branding/jamii_logo.svg`
/// — a navy rounded-square background with the illustrated wordmark on top,
/// not a placeholder.
class JamiiLogo extends StatelessWidget {
  const JamiiLogo({super.key, this.size = 76});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.23),
      child: SvgPicture.asset(
        'assets/branding/jamii_logo.svg',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
