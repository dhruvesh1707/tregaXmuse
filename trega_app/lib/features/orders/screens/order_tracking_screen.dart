import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/sample_data.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/order.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/status_chip.dart';
import '../../home/providers/listing_providers.dart';

/// Doorstep pickup + delivery tracking timeline for a single order.
///
/// Streams `orders/{orderId}` from Firestore; falls back to [SampleData]
/// when Firestore is unreachable.
class OrderTrackingScreen extends ConsumerWidget {
  static const String routeName = '/orders/tracking';

  final String? orderId;

  const OrderTrackingScreen({super.key, this.orderId});

  static const List<(OrderStatus, String)> _timeline = [
    (OrderStatus.confirmed, 'Order confirmed'),
    (OrderStatus.pickupScheduled, 'Pickup scheduled with seller'),
    (OrderStatus.pickedUp, 'Picked up from seller'),
    (OrderStatus.inTransit, 'In transit to your city'),
    (OrderStatus.outForDelivery, 'Out for delivery'),
    (OrderStatus.delivered, 'Delivered'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = orderId;
    if (id == null) {
      return _TrackingContent(order: SampleData.orders.first, demo: true);
    }
    final orderAsync = ref.watch(firestoreServiceProvider).watchOrder(id);
    return StreamBuilder<Order?>(
      stream: orderAsync,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Track order')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final order = snap.data;
        if (order == null || snap.hasError) {
          return _TrackingContent(order: SampleData.orders.first, demo: true);
        }
        return _TrackingContent(order: order);
      },
    );
  }
}

class _TrackingContent extends ConsumerWidget {
  final Order order;
  final bool demo;

  const _TrackingContent({required this.order, this.demo = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = OrderTrackingScreen._timeline
        .indexWhere((e) => e.$1 == order.status);

    return Scaffold(
      appBar: AppBar(title: const Text('Track order')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  demo
                      ? Text(order.listing.product.title,
                          style: Theme.of(context).textTheme.titleMedium)
                      : ref
                          .watch(listingDetailProvider(order.listing.id))
                          .when(
                            data: (listing) => Text(
                              listing?.product.title ??
                                  'Listing ${order.listing.id}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            loading: () => Text(
                              'Listing ${order.listing.id}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            error: (_, __) => Text(
                              'Listing ${order.listing.id}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                  const SizedBox(height: 4),
                  Text(
                    'Order ${order.id.toUpperCase()}${order.trackingId != null ? ' · ${order.trackingId}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formatINR(order.amount),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(color: AppColors.primary)),
                      StatusChip.order(
                        order.status.label,
                        isTerminal: order.status.isTerminal,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...OrderTrackingScreen._timeline.asMap().entries.map((entry) {
            final index = entry.key;
            final (status, label) = entry.value;
            final done = currentIndex == -1 || index <= currentIndex;
            final isCurrent = index == currentIndex;
            return _TimelineTile(
              label: label,
              done: done,
              isCurrent: isCurrent,
              isLast: index == OrderTrackingScreen._timeline.length - 1,
            );
          }),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.support_agent_outlined),
            label: const Text('Need help with this order?'),
          ),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final String label;
  final bool done;
  final bool isCurrent;
  final bool isLast;

  const _TimelineTile({
    required this.label,
    required this.done,
    required this.isCurrent,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.primary : AppColors.divider;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.primary : AppColors.surface,
                border: Border.all(color: color, width: 2),
              ),
              child: done
                  ? const Icon(Icons.check,
                      size: 14, color: Colors.white)
                  : null,
            ),
            if (!isLast)
              Container(width: 2, height: 28, color: color),
          ],
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight:
                      isCurrent ? FontWeight.w700 : FontWeight.w400,
                  color: done
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
          ),
        ),
      ],
    );
  }
}
