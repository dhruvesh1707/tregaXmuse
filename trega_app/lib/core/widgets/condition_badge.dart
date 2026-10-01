import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/app_colors.dart';
import 'status_chip.dart';

/// Small pill showing the condition grade of a listing.
///
/// Rendered as a light-glass [StatusChip]: the semantic color survives as
/// the label color plus a faint tint in the frosted fill.
class ConditionBadge extends StatelessWidget {
  final Condition condition;

  const ConditionBadge({super.key, required this.condition});

  (Color, Color) get _colors {
    switch (condition) {
      case Condition.brandNew:
        return (AppColors.success, AppColors.success);
      case Condition.likeNew:
        return (AppColors.accent, AppColors.accentDeep);
      case Condition.good:
        return (AppColors.primarySoft, AppColors.primaryDark);
      case Condition.fair:
        return (const Color(0xFFEEEEEE), AppColors.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (tint, fg) = _colors;
    return StatusChip(
      label: condition.label,
      background: tint,
      foreground: fg,
    );
  }
}
