import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';

/// Scaffold with the modern Trega backdrop: a soft warm gradient wash
/// with two barely-there ambient glows (amber top-right, brown
/// bottom-left).
///
/// Drop-in replacement for [Scaffold] on full-screen pages — the
/// constructor mirrors the commonly used [Scaffold] parameters. Pass
/// [backgroundColor] to opt a screen back out to a solid color.
class TregaScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool extendBody;
  final bool extendBodyBehindAppBar;
  final bool? resizeToAvoidBottomInset;
  final Widget? drawer;
  final Widget? endDrawer;
  final Widget? bottomSheet;

  /// Solid override. When null (default) the gradient wash is used.
  final Color? backgroundColor;

  const TregaScaffold({
    super.key,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset,
    this.drawer,
    this.endDrawer,
    this.bottomSheet,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: backgroundColor == null ? AppGradients.page : null,
        color: backgroundColor,
      ),
      child: Stack(
        children: [
          if (backgroundColor == null) ...[
            Positioned(
              top: -90,
              right: -70,
              child: _glow(230, AppColors.accent, 0.13),
            ),
            Positioned(
              bottom: -110,
              left: -80,
              child: _glow(270, AppColors.primary, 0.09),
            ),
          ],
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: appBar,
            body: body,
            bottomNavigationBar: bottomNavigationBar,
            floatingActionButton: floatingActionButton,
            floatingActionButtonLocation:
                floatingActionButtonLocation,
            extendBody: extendBody,
            extendBodyBehindAppBar: extendBodyBehindAppBar,
            resizeToAvoidBottomInset: resizeToAvoidBottomInset,
            drawer: drawer,
            endDrawer: endDrawer,
            bottomSheet: bottomSheet,
          ),
        ],
      ),
    );
  }

  /// Static radial glow — cheap (no blur filter), purely decorative.
  Widget _glow(double size, Color color, double alpha) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
