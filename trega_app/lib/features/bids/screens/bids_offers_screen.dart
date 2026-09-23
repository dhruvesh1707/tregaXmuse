import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/bid.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/status_chip.dart';
import '../../listing_detail/screens/listing_detail_screen.dart';

/// Bids the user placed + offers received on the user's listings.
///
/// Backed by Firestore streams (`bids` where `buyerId`/`sellerId` == uid).
/// Accept/reject runs server-side via the `acceptBid` callable (accepting one
/// bid rejects the others and moves the listing to `sold`).
///
/// Negotiation is structured (accept / reject / counter) — there is
/// intentionally no buyer↔seller chat in Trega.
class BidsOffersScreen extends ConsumerWidget {
  static const String routeName = '/bids';

  const BidsOffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    final service = ref.watch(firestoreServiceProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bids & Offers'),
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(text: 'My Bids'),
              Tab(text: 'Offers Received'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _BidListAsync(
              stream: uid == null ? null : service.watchMyBids(uid),
              emptyTitle: 'No bids yet',
              emptySubtitle: 'Place a bid on a listing and track it here.',
            ),
            _BidListAsync(
              stream: uid == null ? null : service.watchOffersReceived(uid),
              emptyTitle: 'No offers yet',
              emptySubtitle: 'Offers on your listings will appear here.',
              showActions: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// Subscribes to a bid stream. Signed-out users get a sign-in prompt;
/// stream errors surface an inline error state — no demo data is shown.
class _BidListAsync extends ConsumerWidget {
  final Stream<List<Bid>>? stream;
  final String emptyTitle;
  final String emptySubtitle;
  final bool showActions;

  const _BidListAsync({
    required this.stream,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.showActions = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (stream == null) {
      return const EmptyState(
        icon: Icons.login_outlined,
        title: 'Sign in required',
        subtitle: 'Sign in to see your bids and offers.',
      );
    }
    return StreamBuilder<List<Bid>>(
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
          return const EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Couldn\'t load bids',
            subtitle: 'Check your connection and try again.',
          );
        }
        return _BidList(
          bids: snap.data ?? const [],
          emptyTitle: emptyTitle,
          emptySubtitle: emptySubtitle,
          showActions: showActions,
        );
      },
    );
  }
}

class _BidList extends ConsumerWidget {
  final List<Bid> bids;
  final String emptyTitle;
  final String emptySubtitle;
  final bool showActions;

  const _BidList({
    required this.bids,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.showActions = false,
  });

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

  Future<void> _respond(
      BuildContext context, WidgetRef ref, Bid bid, String action,) async {
    if (action != 'accept') {
      // v1: only accept is wired; reject/counter follow the same callable.
      return;
    }
    try {
      await ref
          .read(functionsServiceProvider)
          .acceptBid(bidId: bid.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offer accepted.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not accept the offer.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bids.isEmpty) {
      return EmptyState(
        icon: Icons.gavel_outlined,
        title: emptyTitle,
        subtitle: emptySubtitle,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: bids.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final bid = bids[i];
        return FadeSlideIn(
          delay: Duration(milliseconds: (i % 6) * 50),
          duration: const Duration(milliseconds: 400),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => Navigator.of(context).pushNamed(
                            ListingDetailScreen.routeName,
                            arguments: ListingDetailArgs(
                              listingId: bid.listingId,
                            ),
                          ),
                          child: Text(
                            bid.listingTitle ?? 'Listing ${bid.listingId}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ),
                      StatusChip(
                        label: bid.status.label,
                        background: _statusColor(bid.status).withValues(alpha: 0.12),
                        foreground: _statusColor(bid.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${bid.buyerName ?? 'Buyer'} · ${timeAgo(bid.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (bid.counterAmount != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Counter: ${formatINR(bid.counterAmount!)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    formatINR(bid.amount),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: AppColors.primary),
                  ),
                  if (showActions && bid.status == BidStatus.open) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: PressScale(
                            child: OutlinedButton(
                              onPressed: () {
                                // TODO: reject/counter via callables (same
                                // pattern as accept below).
                              },
                              child: const Text('Reject'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PressScale(
                            child: ElevatedButton(
                              onPressed: () =>
                                  _respond(context, ref, bid, 'accept'),
                              child: const Text('Accept'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
