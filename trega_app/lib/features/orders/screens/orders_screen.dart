import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/order.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/status_chip.dart';
import '../../home/providers/listing_providers.dart';
import 'order_tracking_screen.dart';

/// Buyer's order history, streamed from Firestore (`orders` where
/// `buyerId` == uid). Orders are created server-side by the
/// `createCashfreeOrder` callable — the app never writes order docs.
class OrdersScreen extends ConsumerWidget {
  static const String routeName = '/orders';

  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    final service = ref.watch(firestoreServiceProvider);
    final ordersAsync = uid == null ? null : service.watchMyOrders(uid);

    if (ordersAsync == null) {
      return const Scaffold(
        body: SafeArea(
          child: EmptyState(
            icon: PhosphorIconsRegular.signIn,
            title: 'Sign in required',
            subtitle: 'Sign in to see your orders.',
          ),
        ),
      );
    }
    return StreamBuilder<List<Order>>(
      stream: ordersAsync,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('My Orders')),
            body: ListView.separated(
              padding: const EdgeInsets.all(16),
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => const RowSkeleton(),
            ),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('My Orders')),
            body: const EmptyState(
              icon: PhosphorIconsRegular.cloudSlash,
              title: 'Couldn\'t load orders',
              subtitle: 'Check your connection and try again.',
            ),
          );
        }
        return _OrdersList(orders: snap.data ?? const []);
      },
    );
  }
}

class _OrdersList extends StatelessWidget {
  final List<Order> orders;

  const _OrdersList({required this.orders});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: orders.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsRegular.package,
              title: 'No orders yet',
              subtitle:
                  'When you buy something, tracking will show up here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final order = orders[i];
                return Entrance(
                  index: i % 6,
                  child: _OrderCard(order: order),
                );
              },
            ),
    );
  }
}

/// Order card; resolves the listing title/photo via the listing stream
/// (canonical order docs carry no listing snapshot).
class _OrderCard extends ConsumerWidget {
  final Order order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingId = order.listing.id;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).pushNamed(
          OrderTrackingScreen.routeName,
          arguments: order.id,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ref
                        .watch(listingDetailProvider(listingId))
                        .when(
                          data: (listing) => Text(
                            listing?.product.title ?? 'Listing $listingId',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          loading: () => Text(
                            'Listing $listingId',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          error: (_, __) => Text(
                            'Listing $listingId',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                  ),
                  StatusChip.order(
                    order.status.label,
                    isTerminal: order.status.isTerminal,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Order ${order.id.toUpperCase()} · ${timeAgo(order.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatINR(order.amount),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const Row(
                    children: [
                      Text(
                        'Track',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(PhosphorIconsRegular.caretRight, color: AppColors.primary),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
