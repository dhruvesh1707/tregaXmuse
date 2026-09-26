import 'dart:async';

import 'package:flutter/material.dart';

import '../delivery/express_delivery.dart';
import '../icons/phosphor_icons.dart';

/// Small "Express" pill overlaid on listing photos in the feed cards.
class ExpressBadge extends StatelessWidget {
  const ExpressBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIconsRegular.lightning,
            size: 12,
            color: Color(0xFFFFC53D),
          ),
          SizedBox(width: 4),
          Text(
            'Express',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.1,
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB7791F), Color(0xFF7A3A12)],
        ),
        borderRadius: BorderRadius.circular(16),
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
