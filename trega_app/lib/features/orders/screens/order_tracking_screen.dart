import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timelines_plus/timelines_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/order.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/widgets/trega_button.dart';
import '../../../core/widgets/trega_scaffold.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/no_internet_state.dart';
import '../../../core/widgets/order_thumbnail.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/trega_toast.dart';
import '../../home/providers/listing_providers.dart';
import 'dispute_screen.dart';

/// Espresso header zone: the solid espresso gradient behind a plain
/// [AppBar], so the automatic back button, title and actions keep
/// working exactly as before. Rounded bottom corners let the cream
/// body show through at the edges.
class _EspressoHeader extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;

  const _EspressoHeader({required this.title, this.actions});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      actions: actions,
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
        appBar: const _EspressoHeader(title: Text('Track order')),
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
            appBar: const _EspressoHeader(title: Text('Track order')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final order = snap.data;
        if (snap.hasError) {
          return TregaScaffold(
            appBar: const _EspressoHeader(title: Text('Track order')),
            body: errorStateFor(
              snap.error!,
              title: 'Couldn\'t load this order',
              onRetry: () => setState(() => _nonce++),
            ),
          );
        }
        if (order == null) {
          return TregaScaffold(
            appBar: const _EspressoHeader(title: Text('Track order')),
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
    // Same title/photo resolution as the order list card: live listing
    // first, purchase-time snapshot when the listing is gone, and
    // "Listing unavailable" when neither exists, never a bare id.
    final listingAsync = ref.watch(listingDetailProvider(order.listing.id));
    final live = listingAsync.valueOrNull;
    final livePhoto = live != null && live.product.imageUrls.isNotEmpty
        ? live.product.imageUrls.first
        : null;
    final title = live?.product.title ??
        order.listingTitle ??
        (listingAsync.isLoading ? null : 'Listing unavailable');
    final photoUrl = livePhoto ?? order.listingPhotoUrl;
    final uid = ref.watch(currentUidProvider);
    final isBuyer = uid != null && uid == order.buyer.id;
    final isSeller = uid != null && uid == order.listing.seller.id;
    final deliveredAt = order.deliveredAt;
    final disputeDeadline = deliveredAt?.add(const Duration(hours: 72));
    // The 72-hour support window: buyer only, delivered only, inside
    // the window, and no report filed yet. The server enforces the
    // same rule; this only decides whether the button shows.
    final windowOpen = isBuyer &&
        order.status == OrderStatus.delivered &&
        deliveredAt != null &&
        DateTime.now().difference(deliveredAt) <
            const Duration(hours: 72) &&
        order.disputeStatus != 'open' &&
        order.disputeStatus != 'resolved';

    return TregaScaffold(
      appBar: _EspressoHeader(
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
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.divider),
              boxShadow: AppShadows.card,
            ),
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
                            title == null
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
                                        .titleMedium,
                                  ),
                            const SizedBox(height: 4),
                            Text(
                              'Order ${order.id.toUpperCase()}${order.trackingId != null ? ' · ${order.trackingId}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  Theme.of(context).textTheme.bodySmall,
                            ),
                            if (order.courierName != null ||
                                order.awbCode != null)
                              Text(
                                [
                                  order.courierName,
                                  order.awbCode != null
                                      ? 'AWB ${order.awbCode}'
                                      : null,
                                ].whereType<String>().join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    Theme.of(context).textTheme.bodySmall,
                              ),
                            if (order.etd != null && order.etd!.isNotEmpty)
                              Text(
                                'Arriving by ${order.etd}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    Theme.of(context).textTheme.bodySmall,
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
          // Terminal orders (cancelled, returned, payment pending) have
          // no timeline position. They used to render the full timeline
          // as completed, which read as a delivered order; they now get
          // an explicit status card instead of the timeline.
          if (currentIndex == -1)
            _TerminalStatusCard(order: order)
          else ...[
            Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _TimelineView(
              currentIndex: currentIndex,
              isSeller: isSeller,
              deliveredAt: deliveredAt,
            ),
          ],
          const SizedBox(height: 24),
          if (order.disputeStatus == 'open') ...[
            const _InfoBanner(
              text: 'A report for this order is under review. '
                  'We will update you here.',
            ),
            const SizedBox(height: 16),
          ],
          if (order.disputeStatus == 'resolved') ...[
            _InfoBanner(
              text: order.refundStatus == 'refunded'
                  ? 'This order was refunded after review.'
                  : 'The report for this order was resolved.',
            ),
            const SizedBox(height: 16),
          ],
          if (windowOpen) ...[
            TregaButton(
              label: 'Report a problem',
              secondary: true,
              expanded: false,
              onPressed: () => Navigator.of(context).pushNamed(
                DisputeScreen.routeName,
                arguments: order.id,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You can report a problem until '
              '${formatDayTime(disputeDeadline!)}.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
          ],
          if (isSeller &&
              order.sellerPayout != null &&
              (order.status == OrderStatus.delivered ||
                  order.settlementStatus != null)) ...[
            _SettlementCard(order: order),
            const SizedBox(height: 16),
          ],
          TregaButton(
            label: 'Need help with this order?',
            secondary: true,
            expanded: false,
            onPressed: () => _emailOrderSupport(context, ref, order),
          ),
        ],
      ),
    );
  }

  /// Emails support about this specific order, with the order details
  /// prefilled so the buyer does not have to type them. Same mailto +
  /// fallback pattern as the Help screen.
  Future<void> _emailOrderSupport(
      BuildContext context, WidgetRef ref, Order order) async {
    final title = ref
            .read(listingDetailProvider(order.listing.id))
            .valueOrNull
            ?.product
            .title ??
        order.listingTitle ??
        'Listing unavailable';
    final shortId = order.id.length > 6
        ? order.id.substring(0, 6).toUpperCase()
        : order.id;
    final uri = Uri(
      scheme: 'mailto',
      path: 'contact@trega.in',
      queryParameters: {
        'subject': 'Help with order #$shortId',
        'body': 'Hi Trega team,\n\nI need help with my order.\n\n'
            'Order ID: ${order.id}\n'
            'Item: $title\n'
            'Amount: ${formatINR(order.amount)}\n'
            'Status: ${order.status.label}\n\n'
            'What happened:\n',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      await showTregaToast(
        context,
        'Write to contact@trega.in with order #$shortId, we reply within a day.',
        title: 'Contact support',
        kind: TregaToastKind.info,
      );
    }
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
    final text = '$title, ${formatINR(order.amount)} on Trega '
        '(order #$shortId, ${order.status.label}). '
        'Track it: https://trega.in/orders/${order.id}';
    try {
      // share_plus 10.x on iOS throws PlatformException
      // ("sharePositionOrigin: argument must be set") unless the sheet is
      // anchored to a non-zero rect inside the source view, anchor it to
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

/// Timeline wording from the viewer's side: the seller reads "to the
/// buyer", the buyer reads "to your city".
String _timelineLabel(OrderStatus step, String label, bool isSeller) {
  if (!isSeller) return label;
  switch (step) {
    case OrderStatus.pickupScheduled:
      return 'Pickup scheduled';
    case OrderStatus.inTransit:
      return 'In transit to the buyer';
    case OrderStatus.outForDelivery:
      return 'Out for delivery to the buyer';
    default:
      return label;
  }
}

/// Shipment tracker: filled brand dots for completed steps, hollow dots
/// ahead, solid connectors behind and dashed ahead. Only rendered when
/// the order's status has a timeline position; terminal orders get
/// [_TerminalStatusCard] instead.
class _TimelineView extends StatelessWidget {
  final int currentIndex;
  final bool isSeller;
  final DateTime? deliveredAt;

  const _TimelineView({
    required this.currentIndex,
    required this.isSeller,
    required this.deliveredAt,
  });

  @override
  Widget build(BuildContext context) {
    final currentIndex = this.currentIndex;
    return Entrance(
      child: TimelineTheme(
        data: TimelineThemeData(
          color: AppColors.primary,
          indicatorTheme: const IndicatorThemeData(size: 26),
        ),
        child: Timeline.tileBuilder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          builder: TimelineTileBuilder.connectedFromStyle(
            connectionDirection: ConnectionDirection.before,
            contentsAlign: ContentsAlign.basic,
            contentsBuilder: (context, index) {
              final (step, label) = OrderTrackingScreen._timeline[index];
              final done = index <= currentIndex;
              final isCurrent = index == currentIndex;
              return Padding(
                padding: const EdgeInsets.only(
                  left: 12,
                  top: 2,
                  bottom: 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _timelineLabel(step, label, isSeller),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: done
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: AppColors.tileBackground,
                          border: Border.all(color: AppColors.divider),
                          boxShadow: AppShadows.soft,
                        ),
                        child: Text(
                          'Current status',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                    ],
                    if (step == OrderStatus.delivered &&
                        done &&
                        deliveredAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Delivered on ${formatDayTime(deliveredAt!)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
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
              final prevDone = index == 0 || index - 1 <= currentIndex;
              return prevDone
                  ? ConnectorStyle.solidLine
                  : ConnectorStyle.dashedLine;
            },
            indicatorStyleBuilder: (context, index) {
              final done = index <= currentIndex;
              return done ? IndicatorStyle.dot : IndicatorStyle.outlined;
            },
            itemCount: OrderTrackingScreen._timeline.length,
          ),
        ),
      ),
    );
  }
}

/// Explicit status card for orders with no timeline position
/// (cancelled, returned, payment pending).
class _TerminalStatusCard extends StatelessWidget {
  final Order order;

  const _TerminalStatusCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final message = switch (order.status) {
      OrderStatus.cancelled => 'This order was cancelled.',
      OrderStatus.refunded =>
        'This order was returned. A refund was issued to the original '
            'payment method.',
      _ => 'This order is no longer in transit.',
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(order.status.label, style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            message,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain notice banner, used for the delivery-report states.
class _InfoBanner extends StatelessWidget {
  final String text;

  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tileBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

/// Seller-only payout summary: the amount the seller receives for this
/// order and where it stands in the settlement workflow.
class _SettlementCard extends StatelessWidget {
  final Order order;

  const _SettlementCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final label = switch (order.settlementStatus) {
      'eligible' => 'Ready, your payout is on its way.',
      'held' => 'On hold while a report is under review.',
      'paid' => order.settlementReference != null
          ? 'Paid · Ref ${order.settlementReference}.'
          : 'Paid.',
      'cancelled' => 'Cancelled, the order was refunded.',
      null => 'The Trega team will confirm this payout.',
      _ => 'On hold until the 72 hour support window ends.',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your payout', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${formatINR(order.sellerPayout!)} · $label',
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
