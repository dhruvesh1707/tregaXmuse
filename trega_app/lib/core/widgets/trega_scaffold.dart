import 'dart:ui';

import 'package:flutter/material.dart';

import '../icons/phosphor_icons.dart';
import '../network/connectivity_service.dart';
import '../theme/app_colors.dart';

/// Scaffold with the minimal Trega backdrop: flat warm paper.
///
/// Drop-in replacement for [Scaffold] on full-screen pages — the
/// constructor mirrors the commonly used [Scaffold] parameters. Pass
/// [backgroundColor] to opt a screen out to a different solid fill.
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

  /// Solid override. When null (default) the flat [AppColors.background]
  /// is used.
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
      color: backgroundColor ?? AppColors.background,
      child: Stack(
        children: [
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
          // Floating offline pill — overlays every screen while the
          // device has no connectivity, vanishes when back online.
          // Pure overlay: it never shifts the screen's layout.
          // NOTE: Row, not Center — Center would expand to the Stack's
          // full height here (finite-loose constraints).
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable:
                  ConnectivityService.instance.isOnline,
              builder: (context, online, _) {
                if (online) return const SizedBox.shrink();
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [_OfflinePill()],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim floating "you're offline" pill, shown over every [TregaScaffold]
/// screen while the device has no connectivity.
///
/// Dark glass: espresso at 0.78 alpha + blur 16 + hairline
/// white-at-0.14 border, no heavy shadow. Driven by
/// [ConnectivityService]; appears and vanishes automatically.
/// [IgnorePointer] so it never swallows taps meant for the screen below.
class _OfflinePill extends StatelessWidget {
  const _OfflinePill();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.espresso.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIconsRegular.cloudSlash,
                  size: 14,
                  color: Colors.white,
                ),
                SizedBox(width: 8),
                Text(
                  "You're offline",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
