import 'dart:async';

import 'package:flutter/material.dart';

import '../delivery/express_delivery.dart';
import '../icons/phosphor_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';

/// Small "Express" pill overlaid on listing photos in the feed cards.
///
/// Solid [AppColors.accent] with [AppColors.primaryDark] text/icon — the
/// contrast pair is deliberate, do not re-theme it to glass.
class ExpressBadge extends StatelessWidget {
  const ExpressBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppShadows.glass,
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIconsRegular.lightning,
            size: 13,
            color: AppColors.primaryDark,
          ),
          SizedBox(width: 4),
          Text(
            'Express',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Countdown banner for the listing detail page.
///
/// "Order in the next 2h 14m — arrives tomorrow in Mumbai." Ticks every 30
/// seconds so the countdown stays live. Rendered only when the listing's
/// city is express-eligible (the caller checks that).
class ExpressBanner extends StatefulWidget {
  final String city;
  final ExpressDeliveryConfig config;

  const ExpressBanner({
    super.key,
    required this.city,
    required this.config,
  });

  @override
  State<ExpressBanner> createState() => _ExpressBannerState();
}

class _ExpressBannerState extends State<ExpressBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final config = widget.config;
    final headline = config.daysUntilDelivery(now) == 1
        ? 'Order in the next ${config.cutoffCountdownLabel(now)}'
        : 'Order now';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryDeep,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.glass,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              PhosphorIconsRegular.truck,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Trega Express',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$headline — arrives ${config.deliveryDayLabel(now)} in ${widget.city}.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
