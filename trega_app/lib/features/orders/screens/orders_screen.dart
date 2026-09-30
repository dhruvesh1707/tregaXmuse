import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/trega_scaffold.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/order.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/no_internet_state.dart';
import '../../../core/widgets/status_chip.dart';
import '../../home/providers/listing_providers.dart';
import 'order_tracking_screen.dart';

/// Buyer's order history, streamed from Firestore (`orders` where
/// `buyerId` == uid). Orders are created server-side by the
/// `createCashfreeOrder` callable — the app never writes order docs.
class OrdersScreen extends ConsumerStatefulWidget {
  static const String routeName = '/orders';

  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  /// Bumped on retry so the [StreamBuilder] below gets a new key and
  /// resubscribes to a fresh order stream.
  int _nonce = 0;

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final service = ref.watch(firestoreServiceProvider);
    final ordersAsync = uid == null ? null : service.watchMyOrders(uid);

    if (ordersAsync == null) {
      return const TregaScaffold(
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
      key: ValueKey(_nonce),
      stream: ordersAsync,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return TregaScaffold(
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
          return TregaScaffold(
            appBar: AppBar(title: const Text('My Orders')),
            body: errorStateFor(
              snap.error!,
              title: 'Couldn\'t load orders',
              onRetry: () => setState(() => _nonce++),
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
    return TregaScaffold(
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
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      onTap: () => Navigator.of(context).pushNamed(
        OrderTrackingScreen.routeName,
        arguments: order.id,
      ),
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
    );
  }
}
