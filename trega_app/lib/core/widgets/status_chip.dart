import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';

/// Generic status pill for bids, orders and listings.
class StatusChip extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const StatusChip({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  /// Convenience constructor mapping an order status to chip colours.
  factory StatusChip.order(String label, {required bool isTerminal}) {
    return StatusChip(
      label: label,
      background:
          isTerminal ? const Color(0xFFE8F5E9) : AppColors.accentSoft,
      foreground:
          isTerminal ? AppColors.success : AppColors.textPrimary,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        // NOTE: not const — background is a runtime color.
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            background,
            background.withValues(alpha: 0.82),
          ],
        ),
        boxShadow: AppShadows.soft,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}
