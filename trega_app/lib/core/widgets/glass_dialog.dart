import 'package:flutter/material.dart';

import 'liquid_glass.dart';

/// A dialog whose surface is liquid glass instead of flat white.
///
/// Keeps [AlertDialog]'s layout contract (title / content / actions) but
/// renders it as a [LiquidGlass] panel, so every confirmation and prompt
/// in the app matches the modern theme.
class GlassDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry padding;

  const GlassDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(22, 22, 22, 16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: LiquidGlass(
        borderRadius: 28,
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              DefaultTextStyle(
                style: theme.textTheme.titleLarge!,
                child: title!,
              ),
              const SizedBox(height: 10),
            ],
            if (content != null)
              DefaultTextStyle(
                style: theme.textTheme.bodyMedium!,
                child: content!,
              ),
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows a [GlassDialog]. Drop-in replacement for `showDialog` + AlertDialog
/// at call sites that want the modern look.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  Widget? title,
  Widget? content,
  List<Widget>? actions,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) => GlassDialog(
      title: title,
      content: content,
      actions: actions,
    ),
  );
}
