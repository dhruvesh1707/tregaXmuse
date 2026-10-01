import 'package:flutter/material.dart';

import '../icons/phosphor_icons.dart';
import '../network/connectivity_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';

/// Scaffold with a flat clean Trega backdrop: solid warm paper
/// ([AppColors.background]).
///
/// Drop-in replacement for [Scaffold] on full-screen pages — the
/// constructor mirrors the commonly used [Scaffold] parameters. Pass
/// [backgroundColor] to opt a screen out to another solid color.
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

  /// Solid override. Defaults to [AppColors.background].
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
/// Driven by [ConnectivityService]; appears and vanishes automatically.
/// [IgnorePointer] so it never swallows taps meant for the screen below.
class _OfflinePill extends StatelessWidget {
  const _OfflinePill();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2A1A12).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
          ),
          boxShadow: AppShadows.button,
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
    );
  }
}
