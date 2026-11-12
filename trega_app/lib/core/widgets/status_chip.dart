import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Generic status pill for bids, orders and listings.
///
/// A small flat pill. The semantic [background] is blended at low
/// opacity over white to form a pale tint fill, so saturated
/// [foreground] labels stay readable; the pill itself is solid, with
/// no blur or frosted rendering.
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
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: Color.alphaBlend(
          background.withValues(alpha: 0.22),
          Colors.white,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}
