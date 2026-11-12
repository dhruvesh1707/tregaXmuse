import 'package:flutter/material.dart';

import '../theme/app_shadows.dart';
import '../theme/app_theme.dart';

/// Shows a floating flat bottom panel.
///
/// Modern replacement for plain `showModalBottomSheet` call sites: the
/// panel floats with a margin, 28dp radius and a drag pill.
///
/// The [builder] returns the sheet's content, laid out in a min-height
/// column below the pill, return a Column with mainAxisSize.min (or a
/// scrollable with a bounded height) from the builder. If the sheet holds
/// text fields, wrap the content in a SingleChildScrollView at the call
/// site so the keyboard never covers it. Never return a vertical
/// Expanded/Flexible from the builder, the sheet hands its content
/// unbounded height.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: AppColors.espresso.withValues(alpha: 0.35),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + MediaQuery.of(ctx).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.divider, width: 1),
          boxShadow: AppShadows.glass,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            builder(ctx),
          ],
        ),
      ),
    ),
  );
}
