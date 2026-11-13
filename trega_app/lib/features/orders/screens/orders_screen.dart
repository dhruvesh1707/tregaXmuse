import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/trega_scaffold.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/order.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/no_internet_state.dart';
import '../../../core/widgets/order_thumbnail.dart';
import '../../../core/widgets/status_chip.dart';
import '../../home/providers/listing_providers.dart';
import 'order_tracking_screen.dart';

/// Espresso header zone: the solid espresso gradient behind a plain
/// [AppBar], so the automatic back button and title keep working
/// exactly as before. Rounded bottom corners let the cream body show
/// through at the edges.
class _EspressoHeader extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;

  const _EspressoHeader({required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Colors.white,
          ),
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.headerEspresso,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(24),
          ),
        ),
      ),
    );
  }
}

/// Buyer's order history, streamed from Firestore (`orders` where
/// `buyerId` == uid). Orders are created server-side by the
/// `createCashfreeOrder` callable, the app never writes order docs.
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
            appBar: const _EspressoHeader(title: Text('My Orders')),
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
            appBar: const _EspressoHeader(title: Text('My Orders')),
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
      appBar: const _EspressoHeader(title: Text('My Orders')),
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

/// Order card: the listing's first photo as a small thumbnail plus its
/// name. Title/photo resolve from the live listing when it still exists,
/// fall back to the purchase-time snapshot on the order doc when the
/// listing was deleted, and show "Listing unavailable" when neither
/// exists, never a bare listing id.
class _OrderCard extends ConsumerWidget {
  final Order order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingId = order.listing.id;
    final listingAsync = ref.watch(listingDetailProvider(listingId));
    final live = listingAsync.valueOrNull;
    final livePhoto = live != null && live.product.imageUrls.isNotEmpty
        ? live.product.imageUrls.first
        : null;
    final title = live?.product.title ??
        order.listingTitle ??
        (listingAsync.isLoading ? null : 'Listing unavailable');
    final photoUrl = livePhoto ?? order.listingPhotoUrl;
    return Pressable(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.divider),
          boxShadow: AppShadows.card,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => Navigator.of(context).pushNamed(
              OrderTrackingScreen.routeName,
              arguments: order.id,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OrderThumbnail(photoUrl: photoUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: title == null
                                  ? const ShimmerBox(
                                      width: 140,
                                      height: 14,
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(7),
                                      ),
                                    )
                                  : Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
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
                      SizedBox(width: 4),
                      Icon(PhosphorIconsRegular.caretRight,
                          size: 18, color: AppColors.primary),
                    ],
                  ),
                ],
              ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
