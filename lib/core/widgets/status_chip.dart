import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';

/// Generic status pill for bids, orders and listings.
///
/// A small light-glass pill (white 0.70 + blur 14 + hairline border +
/// the one shadow). The semantic [background] survives as a faint tint
/// in the frosted fill; [foreground] colors the label.
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
    const radius = BorderRadius.all(Radius.circular(999));
    // The shadow lives on the outer wrapper so the inner ClipRRect never
    // clips it.
    return Container(
      decoration: const BoxDecoration(
        borderRadius: radius,
        boxShadow: AppShadows.glass,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: Color.alphaBlend(
                background.withValues(alpha: 0.22),
                Colors.white.withValues(alpha: 0.7),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
