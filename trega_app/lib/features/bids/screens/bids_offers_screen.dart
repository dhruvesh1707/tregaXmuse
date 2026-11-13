import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/trega_scaffold.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/firebase/functions_service.dart';
import '../../../core/models/bid.dart';
import '../../../core/models/listing.dart';
import '../../../core/models/order.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/widgets/glass_dialog.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/no_internet_state.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/trega_button.dart';
import '../../../core/widgets/trega_toast.dart';
import '../../checkout/screens/checkout_screen.dart';
import '../../listing_detail/screens/listing_detail_screen.dart';
import '../../orders/screens/order_tracking_screen.dart';

/// Arguments for [BidsOffersScreen].
class BidsOffersArgs {
  /// 0 = My Offers, 1 = Offers Received.
  final int initialTab;

  const BidsOffersArgs({this.initialTab = 0});
}

/// The offer ecosystem, in two tabs:
///
/// - **My Offers** (buyer): every offer the user sent, with the next action
///   per state, waiting (open), offer again (rejected), pay now (accepted).
/// - **Offers Received** (seller): offers grouped by listing, so a seller
///   with many listings sees one section per listing with its open offers
///   sorted newest-first and Accept / Reject on each.
///
/// Accepting is exclusive, once one offer is accepted the listing is
/// reserved for that buyer until they pay. The seller can cancel the
/// acceptance if the buyer never pays, reopening the listing for offers.
/// Once the buyer pays, the offer shows payment completed with the
/// order's fulfillment state and a Track order button instead, on both
/// tabs, and Cancel acceptance disappears (the server refuses it too,
/// since the listing is sold by then).
///
/// Negotiation is structured (accept / reject), there is intentionally no
/// buyer↔seller chat in Trega.
class BidsOffersScreen extends ConsumerStatefulWidget {
  static const String routeName = '/bids';

  final int initialTab;

  const BidsOffersScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<BidsOffersScreen> createState() => _BidsOffersScreenState();
}

class _BidsOffersScreenState extends ConsumerState<BidsOffersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  /// Bumped on retry so each tab's StreamBuilder resubscribes with a fresh
  /// stream (passed down as a nonce that keys the StreamBuilders).
  int _nonce = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final service = ref.watch(firestoreServiceProvider);

    return TregaScaffold(
      appBar: AppBar(
        title: const Text('Bids & Offers'),
        centerTitle: true,
        foregroundColor: Colors.white,
        backgroundColor: AppColors.espresso,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle:
            Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: AppGradients.headerEspresso,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.onEspressoSecondary,
          indicatorColor: AppColors.accent,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'My Offers'),
            Tab(text: 'Offers Received'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _MyOffersTab(
            stream: uid == null ? null : service.watchMyBids(uid),
            ordersStream: uid == null ? null : service.watchMyOrders(uid),
            nonce: _nonce,
            onRetry: () => setState(() => _nonce++),
          ),
          _OffersReceivedTab(
            stream: uid == null ? null : service.watchOffersReceived(uid),
            ordersStream:
                uid == null ? null : service.watchSellerOrders(uid),
            nonce: _nonce,
            onRetry: () => setState(() => _nonce++),
          ),
        ],
      ),
    );
  }
}

Color _statusColor(BidStatus status) {
  switch (status) {
    case BidStatus.accepted:
      return AppColors.success;
    case BidStatus.rejected:
      return AppColors.error;
    case BidStatus.open:
      return AppColors.warning;
    case BidStatus.countered:
      return AppColors.primary;
    case BidStatus.expired:
      return AppColors.textSecondary;
  }
}

Widget _statusChip(BidStatus status) {
  final color = _statusColor(status);
  return StatusChip(
    label: status.label,
    background: color.withValues(alpha: 0.12),
    foreground: color,
  );
}

void _openListing(BuildContext context, String listingId) {
  Navigator.of(context).pushNamed(
    ListingDetailScreen.routeName,
    arguments: ListingDetailArgs(listingId: listingId),
  );
}

void _openTracking(BuildContext context, String orderId) {
  Navigator.of(context).pushNamed(
    OrderTrackingScreen.routeName,
    arguments: orderId,
  );
}

/// True only when the buyer actually paid. An order doc existing is not
/// enough: one is created before payment, and abandoned checkouts leave
/// PENDING / FAILED / USER_DROPPED docs behind.
bool _isPaid(Order? order) => order?.paymentStatus == 'SUCCESS';

Widget _paidChip() {
  return StatusChip(
    label: 'Paid',
    background: AppColors.success.withValues(alpha: 0.12),
    foreground: AppColors.success,
  );
}

/// Maps each bid id to its order, preferring a paid (SUCCESS) order when
/// a bid has several attempts, since payment retries create new docs.
Map<String, Order> _ordersByBid(List<Order> orders) {
  final map = <String, Order>{};
  for (final order in orders) {
    final bidId = order.bidId;
    if (bidId == null || bidId.isEmpty) continue;
    final existing = map[bidId];
    if (existing == null || order.paymentStatus == 'SUCCESS') {
      map[bidId] = order;
    }
  }
  return map;
}

/// The other party's display name on an offer card.
///
/// Bid docs carry only ids, names are joined client-side from the public
/// profile. While loading (or if the profile has no name) the fallback
/// shows, so a card never renders a blank name.
class _CounterpartyName extends ConsumerWidget {
  final String uid;
  final String fallback;
  final String prefix;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const _CounterpartyName({
    required this.uid,
    this.fallback = 'Buyer',
    this.prefix = '',
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<AppUser?>(
      stream: ref.watch(firestoreServiceProvider).watchUser(uid),
      builder: (context, snap) {
        final name = snap.data?.name;
        return Text(
          '$prefix${(name?.isNotEmpty ?? false) ? name! : fallback}',
          style: style,
          maxLines: maxLines,
          overflow: overflow,
        );
      },
    );
  }
}

/// The listing's real title on an offer card.
///
/// Bid docs carry only the listing id, the title is joined client-side
/// from the listing doc, exactly like the counterparty name above.
/// Falls back to 'Listing' while loading or if the listing is gone, so
/// a card never renders blank. (Bid.listingTitle was never populated by
/// any code path, which is why every card used to say just 'Listing'
/// and two different offers could look like the same one flipped.)
class _ListingTitle extends ConsumerWidget {
  final String listingId;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const _ListingTitle({
    required this.listingId,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<Listing?>(
      stream: ref.watch(firestoreServiceProvider).watchListing(listingId),
      builder: (context, snap) {
        final title = snap.data?.product.title;
        return Text(
          (title?.isNotEmpty ?? false) ? title! : 'Listing',
          style: style,
          maxLines: maxLines,
          overflow: overflow,
        );
      },
    );
  }
}

// ── Buyer tab ─────────────────────────────────────────────────────────────

/// Every offer the buyer sent, with the next action per state.
class _MyOffersTab extends ConsumerWidget {
  final Stream<List<Bid>>? stream;

  /// The buyer's orders, joined to offers by bid id so a paid offer
  /// shows payment completed with tracking instead of the Pay button.
  final Stream<List<Order>>? ordersStream;

  /// Bumped by the parent on retry; keys the StreamBuilder so it
  /// resubscribes with a fresh stream.
  final int nonce;
  final VoidCallback onRetry;

  const _MyOffersTab({
    required this.stream,
    required this.ordersStream,
    required this.nonce,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (stream == null) {
      return const EmptyState(
        icon: PhosphorIconsRegular.signIn,
        title: 'Sign in required',
        subtitle: 'Sign in to see your offers.',
      );
    }
    return StreamBuilder<List<Bid>>(
      key: ValueKey(nonce),
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => const RowSkeleton(),
          );
        }
        if (snap.hasError) {
          return errorStateFor(
            snap.error!,
            title: "Couldn't load offers",
            onRetry: onRetry,
          );
        }
        final bids = snap.data ?? const <Bid>[];
        if (bids.isEmpty) {
          return const EmptyState(
            icon: PhosphorIconsRegular.gavel,
            title: 'No offers yet',
            subtitle: 'Make an offer on a listing and track it here.',
          );
        }
        // Orders load independently: the offers list never waits on them,
        // and a failed orders stream just means paid states stay hidden
        // until the next load instead of breaking the tab.
        return StreamBuilder<List<Order>>(
          key: ValueKey(nonce),
          stream: ordersStream,
          builder: (context, orderSnap) {
            final ordersByBid = _ordersByBid(orderSnap.data ?? const <Order>[]);
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: bids.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final bid = bids[i];
                return Entrance(
                  index: i % 6,
                  child: _MyOfferCard(
                    bid: bid,
                    order: ordersByBid[bid.id],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MyOfferCard extends StatelessWidget {
  final Bid bid;

  /// The order placed from this bid, when one exists.
  final Order? order;

  const _MyOfferCard({required this.bid, this.order});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final paidOrder = _isPaid(order) ? order : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Pressable(
                    child: InkWell(
                    onTap: () => _openListing(context, bid.listingId),
                    child: _ListingTitle(
                      listingId: bid.listingId,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall,
                    ),
                    ),
                  ),
                ),
                if (paidOrder != null) _paidChip() else _statusChip(bid.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              timeAgo(bid.createdAt),
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            _CounterpartyName(
              uid: bid.sellerId,
              fallback: 'Seller',
              prefix: 'Seller · ',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              formatINR(bid.amount),
              style: textTheme.titleLarge?.copyWith(
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            switch (bid.status) {
              // Awaiting the seller's decision.
              BidStatus.open => Text(
                  'Waiting for the seller to accept or reject.',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              // Rejected, the buyer may offer again on the listing.
              BidStatus.rejected => TregaButton(
                  label: 'Offer again',
                  secondary: true,
                  onPressed: () => _openListing(context, bid.listingId),
                ),
              // Expired unpaid after 24 hours, the buyer may offer again.
              BidStatus.expired => TregaButton(
                  label: 'Offer again',
                  secondary: true,
                  onPressed: () => _openListing(context, bid.listingId),
                ),
              // Accepted, only this buyer gets to buy, at this price.
              // Once paid, the card shows the fulfillment state and a
              // Track order button instead of the Pay button.
              BidStatus.accepted => paidOrder != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payment completed · ${paidOrder.status.label}',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (paidOrder.trackingId != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            paidOrder.trackingId!,
                            style: textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 12),
                        TregaButton(
                          label: 'Track order',
                          secondary: true,
                          onPressed: () =>
                              _openTracking(context, paidOrder.id),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pay within 24 hours of acceptance, or the '
                          'offer expires.',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TregaButton(
                          label: 'Pay ${formatINR(bid.amount)} now',
                          onPressed: () => Navigator.of(context).pushNamed(
                            CheckoutScreen.routeName,
                            arguments: CheckoutArgs(bidId: bid.id),
                          ),
                        ),
                      ],
                    ),
              _ => Text(
                  'This offer is closed.',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            },
          ],
        ),
    );
  }
}

// ── Seller tab ────────────────────────────────────────────────────────────

/// Offers received, grouped by listing, one section per listing with its
/// offers sorted newest-first, so multiple listings stay easy to manage.
class _OffersReceivedTab extends ConsumerWidget {
  final Stream<List<Bid>>? stream;

  /// The seller's orders, joined to offers by bid id so a paid offer
  /// shows payment completed with tracking instead of Cancel acceptance.
  final Stream<List<Order>>? ordersStream;

  /// Bumped by the parent on retry; keys the StreamBuilder so it
  /// resubscribes with a fresh stream.
  final int nonce;
  final VoidCallback onRetry;

  const _OffersReceivedTab({
    required this.stream,
    required this.ordersStream,
    required this.nonce,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (stream == null) {
      return const EmptyState(
        icon: PhosphorIconsRegular.signIn,
        title: 'Sign in required',
        subtitle: 'Sign in to see offers on your listings.',
      );
    }
    return StreamBuilder<List<Bid>>(
      key: ValueKey(nonce),
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => const RowSkeleton(),
          );
        }
        if (snap.hasError) {
          return errorStateFor(
            snap.error!,
            title: "Couldn't load offers",
            onRetry: onRetry,
          );
        }
        final bids = snap.data ?? const <Bid>[];
        if (bids.isEmpty) {
          return const EmptyState(
            icon: PhosphorIconsRegular.tray,
            title: 'No offers yet',
            subtitle: 'Offers on your listings will appear here.',
          );
        }

        // Group by listing, preserving stream order (newest activity first).
        final groups = <String, List<Bid>>{};
        for (final bid in bids) {
          groups.putIfAbsent(bid.listingId, () => []).add(bid);
        }

        // Orders load independently: the offers list never waits on them.
        return StreamBuilder<List<Order>>(
          key: ValueKey(nonce),
          stream: ordersStream,
          builder: (context, orderSnap) {
            final ordersByBid =
                _ordersByBid(orderSnap.data ?? const <Order>[]);
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, i) {
                final entry = groups.entries.elementAt(i);
                return Entrance(
                  index: i % 6,
                  child: _ListingOffersGroup(
                    listingId: entry.key,
                    bids: entry.value,
                    ordersByBid: ordersByBid,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ListingOffersGroup extends ConsumerStatefulWidget {
  final String listingId;
  final List<Bid> bids;

  /// Orders keyed by bid id, for the paid state of accepted offers.
  final Map<String, Order> ordersByBid;

  const _ListingOffersGroup({
    required this.listingId,
    required this.bids,
    this.ordersByBid = const {},
  });

  @override
  ConsumerState<_ListingOffersGroup> createState() =>
      _ListingOffersGroupState();
}

class _ListingOffersGroupState extends ConsumerState<_ListingOffersGroup> {
  /// Bid ids with a server call in flight. Their buttons flip to a spinner
  /// and swallow taps, the tap visibly registers the instant it lands,
  /// even when the function cold-starts and takes seconds.
  final Set<String> _busyIds = {};

  /// Bids the seller just accepted on this device. The bids stream takes a
  /// few seconds to reflect the new status; this set bridges the gap so the
  /// offer jumps to "Accepted" immediately instead of looking stuck.
  /// Rolled back if the call fails.
  final Set<String> _acceptedOptimistic = {};

  String get listingId => widget.listingId;

  Future<void> _accept(
      BuildContext context, WidgetRef ref, Bid bid,) async {
    final buyer = await ref.read(firestoreServiceProvider).getUser(bid.buyerId);
    final buyerLabel =
        (buyer?.name.isNotEmpty ?? false) ? buyer!.name : 'the buyer';
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('Accept this offer?'),
        content: Text(
          "Accept $buyerLabel's offer of ${formatINR(bid.amount)}? "
          'Other open offers on this listing will be rejected automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_busyIds.contains(bid.id)) return;
    // Instant feedback + optimistic accept: the buttons flip to a spinner
    // and the offer moves to "Accepted" NOW; the stream converges in a few
    // seconds. Both are rolled back below if the call fails.
    setState(() {
      _busyIds.add(bid.id);
      _acceptedOptimistic.add(bid.id);
    });
    try {
      await ref.read(functionsServiceProvider).acceptBid(bidId: bid.id);
      if (!mounted) return;
      setState(() => _busyIds.remove(bid.id));
      // Keep _acceptedOptimistic until the stream reports status=accepted.
      if (context.mounted) {
        await showTregaToast(
          context,
          'The buyer has been notified and can now pay.',
          title: 'Offer accepted',
          kind: TregaToastKind.success,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyIds.remove(bid.id);
        _acceptedOptimistic.remove(bid.id);
      });
      if (context.mounted) {
        await showTregaToast(
          context,
          functionsErrorMessage(e,
              fallback: 'Could not accept the offer.',),
          title: 'Something went wrong',
          kind: TregaToastKind.error,
        );
      }
    }
  }

  Future<void> _reject(
      BuildContext context, WidgetRef ref, Bid bid,) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('Reject this offer?'),
        content: const Text(
          'The buyer will be notified and can send a new offer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_busyIds.contains(bid.id)) return;
    setState(() => _busyIds.add(bid.id));
    try {
      await ref.read(functionsServiceProvider).rejectBid(bidId: bid.id);
      if (!mounted) return;
      setState(() => _busyIds.remove(bid.id));
      if (context.mounted) {
        await showTregaToast(
          context,
          'The buyer was notified and can send a new offer.',
          title: 'Offer rejected',
          kind: TregaToastKind.info,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(bid.id));
      if (context.mounted) {
        await showTregaToast(
          context,
          functionsErrorMessage(e,
              fallback: 'Could not reject the offer.',),
          title: 'Something went wrong',
          kind: TregaToastKind.error,
        );
      }
    }
  }

  Future<void> _cancelAcceptance(
      BuildContext context, WidgetRef ref, Bid bid,) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('Cancel the accepted offer?'),
        content: const Text(
          'The listing opens up for offers again and the buyer is notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel offer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_busyIds.contains(bid.id)) return;
    setState(() {
      _busyIds.add(bid.id);
      // The optimistic "Accepted" banner drops back to an open offer.
      _acceptedOptimistic.remove(bid.id);
    });
    try {
      await ref
          .read(functionsServiceProvider)
          .cancelAcceptance(bidId: bid.id);
      if (!mounted) return;
      setState(() => _busyIds.remove(bid.id));
      if (context.mounted) {
        await showTregaToast(
          context,
          'The listing is open for offers again.',
          title: 'Acceptance cancelled',
          kind: TregaToastKind.info,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(bid.id));
      if (context.mounted) {
        await showTregaToast(
          context,
          functionsErrorMessage(e,
              fallback: 'Could not cancel the acceptance.',),
          title: 'Something went wrong',
          kind: TregaToastKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Optimistic accept: a bid the seller just accepted renders as
    // accepted immediately; the stream converges a few seconds later.
    final open = widget.bids
        .where((b) =>
            b.status == BidStatus.open && !_acceptedOptimistic.contains(b.id))
        .toList();
    final accepted = widget.bids
        .where((b) =>
            b.status == BidStatus.accepted ||
            _acceptedOptimistic.contains(b.id))
        .toList();
    final past = widget.bids
        .where((b) =>
            b.status == BidStatus.rejected || b.status == BidStatus.expired)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Listing header.
            Pressable(
              child: InkWell(
              onTap: () => _openListing(context, listingId),
              child: Row(
                children: [
                  Expanded(
                    child: _ListingTitle(
                      listingId: listingId,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium,
                    ),
                  ),
                  if (open.isNotEmpty)
                    StatusChip(
                      label: '${open.length} open',
                      background:
                          AppColors.warning.withValues(alpha: 0.12),
                      foreground: AppColors.warning,
                    ),
                ],
              ),
              ),
            ),
            const SizedBox(height: 12),

            // Accepted offer banner (exclusive reservation, or the paid
            // state with fulfillment tracking once the buyer paid).
            for (final bid in accepted) ...[
              _AcceptedOfferBanner(
                bid: bid,
                order: widget.ordersByBid[bid.id],
                busy: _busyIds.contains(bid.id),
                optimistic: _acceptedOptimistic.contains(bid.id),
                onCancelAcceptance: () =>
                    _cancelAcceptance(context, ref, bid),
              ),
              const SizedBox(height: 12),
            ],

            // Open offers, newest first.
            for (var i = 0; i < open.length; i++) ...[
              _OfferRow(
                bid: open[i],
                busy: _busyIds.contains(open[i].id),
                onAccept: () => _accept(context, ref, open[i]),
                onReject: () => _reject(context, ref, open[i]),
              ),
              if (i < open.length - 1) const SizedBox(height: 8),
            ],
            if (open.isEmpty && accepted.isEmpty)
              Text(
                'No open offers on this listing.',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),

            // Past (rejected) offers, collapsed.
            if (past.isNotEmpty) ...[
              const SizedBox(height: 12),
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Past offers (${past.length})',
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  children: [
                    for (final bid in past)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Row(
                          children: [
                            Flexible(
                              child: _CounterpartyName(
                                uid: bid.buyerId,
                                fallback: 'Buyer',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(' · ${formatINR(bid.amount)}'),
                          ],
                        ),
                        subtitle: Text(timeAgo(bid.createdAt)),
                        trailing: _statusChip(bid.status),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
    );
  }
}

/// The accepted-offer banner on a listing group.
///
/// Unpaid: the reservation state, "Reserved for this buyer until they
/// pay", with Cancel acceptance. Paid: "Paid", the order's fulfillment
/// state with its latest tracking note, and a Track order button.
/// Cancel acceptance never renders once paid: the listing is sold and
/// the server refuses the cancel anyway.
class _AcceptedOfferBanner extends StatelessWidget {
  final Bid bid;
  final Order? order;
  final bool busy;
  final bool optimistic;
  final VoidCallback onCancelAcceptance;

  const _AcceptedOfferBanner({
    required this.bid,
    required this.order,
    required this.busy,
    required this.optimistic,
    required this.onCancelAcceptance,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final paidOrder = _isPaid(order) ? order : null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tileBackground,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  children: [
                    Text(
                      '${paidOrder != null ? 'Paid' : 'Accepted'}: '
                      '${formatINR(bid.amount)} from ',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _CounterpartyName(
                      uid: bid.buyerId,
                      fallback: 'buyer',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (paidOrder != null)
                _paidChip()
              else
                _statusChip(
                    optimistic ? BidStatus.accepted : bid.status),
            ],
          ),
          const SizedBox(height: 4),
          if (paidOrder != null) ...[
            Text(
              'Payment completed · ${paidOrder.status.label}',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (paidOrder.trackingId != null) ...[
              const SizedBox(height: 2),
              Text(
                paidOrder.trackingId!,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _openTracking(context, paidOrder.id),
              child: const Text('Track order'),
            ),
          ] else ...[
            Text(
              'Reserved for this buyer. If they do not pay within 24 '
              'hours of acceptance, the offer expires automatically.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            if (busy)
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Confirming…'),
                ],
              )
            else
              TextButton(
                onPressed: onCancelAcceptance,
                child: const Text('Cancel acceptance'),
              ),
          ],
        ],
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  final Bid bid;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _OfferRow({
    required this.bid,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Swipe right to accept, left to reject, the buttons stay for
    // explicit taps; both paths show the same confirm dialog.
    return Slidable(
      key: ValueKey(bid.id),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (_) => onAccept(),
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            icon: PhosphorIconsRegular.check,
            label: 'Accept',
            borderRadius: BorderRadius.circular(16),
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (_) => onReject(),
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            icon: PhosphorIconsRegular.x,
            label: 'Reject',
            borderRadius: BorderRadius.circular(16),
          ),
        ],
      ),
      child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // NOTE: not const, Border.all has no const constructor.
        color: AppColors.tileBackground,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: _CounterpartyName(
                        uid: bid.buyerId,
                        fallback: 'Buyer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      ' · ${timeAgo(bid.createdAt)}',
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Text(
                formatINR(bid.amount),
                style: textTheme.titleSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: PressScale(
                  child: OutlinedButton(
                    onPressed: busy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PressScale(
                  child: ElevatedButton(
                    onPressed: busy ? null : onAccept,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accept'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}
