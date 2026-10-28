import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Horizontal gutter used by every screen built on [AppScreen]. Screens
/// that still hand-roll their own `Scaffold`/`SafeArea`/`Padding` shell
/// instead of reusing this widget should match this value so the app's
/// left/right rhythm stays consistent even where the shell itself isn't
/// shared yet.
const double kScreenGutter = 18.0;

/// Shared page shell: navy background, [kScreenGutter] horizontal gutters,
/// scrollable content area, and an optional pinned footer for the
/// full-width action button(s) (`.foot`) that close out almost every
/// screen in the design.
class AppScreen extends StatelessWidget {
  const AppScreen(
      {super.key, required this.child, this.footer, this.scrollable = true});

  final Widget child;
  final Widget? footer;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy900,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kScreenGutter),
          child: Column(
            children: [
              Expanded(
                child: scrollable ? SingleChildScrollView(child: child) : child,
              ),
              if (footer != null)
                Padding(
                    padding: const EdgeInsets.only(
                        bottom: AppSpacing.xl, top: AppSpacing.sm),
                    child: footer),
            ],
          ),
        ),
      ),
    );
  }
}
