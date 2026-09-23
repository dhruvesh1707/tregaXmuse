import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';

/// Small pill showing the condition grade of a listing.
class ConditionBadge extends StatelessWidget {
  final Condition condition;

  const ConditionBadge({super.key, required this.condition});

  (Color, Color) get _colors {
    switch (condition) {
      case Condition.brandNew:
        return (AppColors.success, Colors.white);
      case Condition.likeNew:
        return (AppColors.accent, AppColors.textPrimary);
      case Condition.good:
        return (AppColors.primarySoft, AppColors.primaryDark);
      case Condition.fair:
        return (const Color(0xFFEEEEEE), AppColors.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        condition.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
