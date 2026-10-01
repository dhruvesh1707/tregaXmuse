import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timelines_plus/timelines_plus.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/order.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/trega_button.dart';
import '../../../core/widgets/trega_scaffold.dart';
import '../../../core/widgets/trega_app_bar.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/no_internet_state.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/trega_toast.dart';
import '../../home/providers/listing_providers.dart';

/// Doorstep pickup + delivery tracking timeline for a single order.
///
/// Streams `orders/{orderId}` from Firestore.
class OrderTrackingScreen extends ConsumerStatefulWidget {
  static const String routeName = '/orders/tracking';

  static const List<(OrderStatus, String)> _timeline = [
    (OrderStatus.confirmed, 'Order confirmed'),
    (OrderStatus.pickupScheduled, 'Pickup scheduled with seller'),
    (OrderStatus.pickedUp, 'Picked up from seller'),
    (OrderStatus.inTransit, 'In transit to your city'),
    (OrderStatus.outForDelivery, 'Out for delivery'),
    (OrderStatus.delivered, 'Delivered'),
  ];

  final String? orderId;

  const OrderTrackingScreen({super.key, this.orderId});

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {

  /// Bumped on retry so the [StreamBuilder] below gets a new key and
  /// resubscribes to a fresh order stream.
  int _nonce = 0;

  @override
  Widget build(BuildContext context) {
    final id = widget.orderId;
    if (id == null) {
      return TregaScaffold(
        appBar: TregaAppBar(title: const Text('Track order')),
        body: const Center(child: Text('Order not found.')),
      );
    }
    final orderAsync = ref.watch(firestoreServiceProvider).watchOrder(id);
    return StreamBuilder<Order?>(
      key: ValueKey(_nonce),
      stream: orderAsync,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return TregaScaffold(
            appBar: TregaAppBar(title: const Text('Track order')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final order = snap.data;
        if (snap.hasError) {
          return TregaScaffold(
            appBar: TregaAppBar(title: const Text('Track order')),
            body: errorStateFor(
              snap.error!,
              title: 'Couldn\'t load this order',
              onRetry: () => setState(() => _nonce++),
            ),
          );
        }
        if (order == null) {
          return TregaScaffold(
            appBar: TregaAppBar(title: const Text('Track order')),
            body: const Center(
              child:
                  Text('Couldn\'t load this order. Check your connection.'),
            ),
          );
        }
        return _TrackingContent(order: order);
      },
    );
  }
}

class _TrackingContent extends ConsumerWidget {
  final Order order;

  const _TrackingContent({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = OrderTrackingScreen._timeline
        .indexWhere((e) => e.$1 == order.status);

    return TregaScaffold(
      appBar: TregaAppBar(
        title: const Text('Track order'),
        actions: [
          Builder(
            builder: (shareBtnContext) => IconButton(
              icon: const Icon(PhosphorIconsRegular.shareNetwork),
              tooltip: 'Share order',
              onPressed: () => _shareOrder(shareBtnContext, ref, order),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ref
                      .watch(listingDetailProvider(order.listing.id))
                      .when(
                        data: (listing) => Text(
                          listing?.product.title ??
                              'Listing ${order.listing.id}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        loading: () => Text(
                          'Listing ${order.listing.id}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        error: (_, __) => Text(
                          'Listing ${order.listing.id}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                  const SizedBox(height: 4),
                  Text(
                    'Order ${order.id.toUpperCase()}${order.trackingId != null ? ' · ${order.trackingId}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                              ?.copyWith(color: AppColors.primary),),
                      StatusChip.order(
                        order.status.label,
                        isTerminal: order.status.isTerminal,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          // Shipment tracker: filled brand dots for completed steps,
          // hollow dots ahead, solid connectors behind and dashed ahead.
          Entrance(
            child: TimelineTheme(
              data: TimelineThemeData(
                color: AppColors.primary,
                indicatorTheme:
                    const IndicatorThemeData(size: 26),
              ),
              child: Timeline.tileBuilder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                builder: TimelineTileBuilder.connectedFromStyle(
                  connectionDirection: ConnectionDirection.before,
                  contentsAlign: ContentsAlign.basic,
                  contentsBuilder: (context, index) {
                    final (_, label) =
                        OrderTrackingScreen._timeline[index];
                    final done = currentIndex == -1 ||
                        index <= currentIndex;
                    final isCurrent = index == currentIndex;
                    return Padding(
                      padding: const EdgeInsets.only(
                        left: 12,
                        top: 2,
                        bottom: 28,
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: isCurrent
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: done
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                // NOTE: not const — gradient recipe.
                                borderRadius:
                                    BorderRadius.circular(8),
                                color: AppColors.surface,
                                border: Border.all(
                                    color: AppColors.divider),
                                boxShadow: AppShadows.soft,
                              ),
                              child: Text(
                                'Current status',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                  // The connector above step `index` is solid once the
                  // step before it is done, dashed while still ahead.
                  connectorStyleBuilder: (context, index) {
                    final prevDone = index == 0 ||
                        currentIndex == -1 ||
                        index - 1 <= currentIndex;
                    return prevDone
                        ? ConnectorStyle.solidLine
                        : ConnectorStyle.dashedLine;
                  },
                  indicatorStyleBuilder: (context, index) {
                    final done = currentIndex == -1 ||
                        index <= currentIndex;
                    return done
                        ? IndicatorStyle.dot
                        : IndicatorStyle.outlined;
                  },
                  itemCount:
                      OrderTrackingScreen._timeline.length,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          TregaButton(
            label: 'Need help with this order?',
            secondary: true,
            expanded: false,
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  /// Shares this specific order as text with a link to it, so it can be
  /// sent to anyone (WhatsApp, SMS, …). Deep links resolve in-app later;
  /// text share works everywhere today.
  Future<void> _shareOrder(
      BuildContext shareBtnContext, WidgetRef ref, Order order) async {
    final title = ref
            .read(listingDetailProvider(order.listing.id))
            .valueOrNull
            ?.product
            .title ??
        'Trega order';
    final shortId = order.id.length > 6
        ? order.id.substring(0, 6).toUpperCase()
        : order.id;
    final text = '$title — ${formatINR(order.amount)} on Trega '
        '(order #$shortId, ${order.status.label}). '
        'Track it: https://trega.in/orders/${order.id}';
    try {
      // share_plus 10.x on iOS throws PlatformException
      // ("sharePositionOrigin: argument must be set") unless the sheet is
      // anchored to a non-zero rect inside the source view — anchor it to
      // the share button itself. `subject` stays unset for the same reason
      // as the listing share (setValue:forKey:@"subject" throws).
      final box = shareBtnContext.findRenderObject() as RenderBox?;
      await Share.share(
        text,
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      debugPrint('Share order failed: $e');
      if (!shareBtnContext.mounted) return;
      await showTregaToast(
        shareBtnContext,
        'Share failed: $e',
        title: 'Share sheet unavailable',
        kind: TregaToastKind.error,
      );
    }
  }
}
