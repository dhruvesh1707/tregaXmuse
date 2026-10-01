import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Frosted app bar for the minimal Trega glass theme.
///
/// Builds a REAL [AppBar] inside — so the automatic back button, title,
/// actions and [bottom] keep working exactly as callers expect — wrapped
/// in [ClipRect] + [BackdropFilter] (blur 18) with a translucent white
/// fill and a hairline [AppColors.divider] bottom edge.
///
/// Drop-in replacement for [AppBar] on screens that want the frosted
/// look. Do NOT use it in [showFullScreenPhoto]-style black viewers —
/// those keep their own transparent-black app bar.
class TregaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;

  const TregaAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.centerTitle = true,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AppBar(
          title: titleWidget ?? title,
          leading: leading,
          actions: actions,
          centerTitle: centerTitle,
          bottom: bottom,
          backgroundColor: Colors.white.withValues(alpha: 0.7),
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppColors.textPrimary,
          shape: const Border(
            bottom: BorderSide(color: AppColors.divider, width: 1),
          ),
        ),
      ),
    );
  }
}
