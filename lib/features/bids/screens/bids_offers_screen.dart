import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/trega_scaffold.dart';
import '../../../core/widgets/trega_app_bar.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/firebase/functions_service.dart';
import '../../../core/models/bid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/widgets/glass_dialog.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/no_internet_state.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/trega_button.dart';
import '../../../core/widgets/trega_toast.dart';
import '../../checkout/screens/checkout_screen.dart';
import '../../listing_detail/screens/listing_detail_screen.dart';

/// Arguments for [BidsOffersScreen].
class BidsOffersArgs {
  /// 0 = My Offers, 1 = Offers Received.
  final int initialTab;

  const BidsOffersArgs({this.initialTab = 0});
}

/// The offer ecosystem, in two tabs:
///
/// - **My Offers** (buyer): every offer the user sent, with the next action
///   per state — waiting (open), offer again (rejected), pay now (accepted).
/// - **Offers Received** (seller): offers grouped by listing, so a seller
///   with many listings sees one section per listing with its open offers
///   sorted newest-first and Accept / Reject on each.
///
/// Accepting is exclusive — once one offer is accepted the listing is
/// reserved for that buyer until they pay. The seller can cancel the
/// acceptance if the buyer never pays, reopening the listing for offers.
///
/// Negotiation is structured (accept / reject) — there is intentionally no
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
      appBar: TregaAppBar(
        title: const Text('Bids & Offers'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
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
            nonce: _nonce,
            onRetry: () => setState(() => _nonce++),
          ),
          _OffersReceivedTab(
            stream: uid == null ? null : service.watchOffersReceived(uid),
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

// ── Buyer tab ─────────────────────────────────────────────────────────────

/// Every offer the buyer sent, with the next action per state.
class _MyOffersTab extends ConsumerWidget {
  final Stream<List<Bid>>? stream;

  /// Bumped by the parent on retry; keys the StreamBuilder so it
  /// resubscribes with a fresh stream.
  final int nonce;
  final VoidCallback onRetry;

  const _MyOffersTab({
    required this.stream,
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
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: bids.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final bid = bids[i];
            return Entrance(
              index: i % 6,
              child: _MyOfferCard(bid: bid),
            );
          },
        );
      },
    );
  }
}

class _MyOfferCard extends StatelessWidget {
  final Bid bid;

  const _MyOfferCard({required this.bid});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _openListing(context, bid.listingId),
                    child: Text(
                      bid.listingTitle ?? 'Listing',
                      style: textTheme.titleSmall,
                    ),
                  ),
                ),
                _statusChip(bid.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              timeAgo(bid.createdAt),
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
              // Rejected — the buyer may offer again on the listing.
              BidStatus.rejected => TregaButton(
                  label: 'Offer again',
                  secondary: true,
                  onPressed: () => _openListing(context, bid.listingId),
                ),
              // Accepted — only this buyer gets to buy, at this price.
              BidStatus.accepted => TregaButton(
                  label: 'Pay ${formatINR(bid.amount)} now',
                  onPressed: () => Navigator.of(context).pushNamed(
                    CheckoutScreen.routeName,
                    arguments: CheckoutArgs(bidId: bid.id),
                  ),
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

/// Offers received, grouped by listing — one section per listing with its
/// offers sorted newest-first, so multiple listings stay easy to manage.
class _OffersReceivedTab extends ConsumerWidget {
  final Stream<List<Bid>>? stream;

  /// Bumped by the parent on retry; keys the StreamBuilder so it
  /// resubscribes with a fresh stream.
  final int nonce;
  final VoidCallback onRetry;

  const _OffersReceivedTab({
    required this.stream,
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
              ),
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

  const _ListingOffersGroup({
    required this.listingId,
    required this.bids,
  });

  @override
  ConsumerState<_ListingOffersGroup> createState() =>
      _ListingOffersGroupState();
}

class _ListingOffersGroupState extends ConsumerState<_ListingOffersGroup> {
  /// Bid ids with a server call in flight. Their buttons flip to a spinner
  /// and swallow taps — the tap visibly registers the instant it lands,
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
    final buyerLabel = bid.buyerName ?? 'the buyer';
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
    final title = widget.bids.first.listingTitle ?? 'Listing';
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
    final past =
        widget.bids.where((b) => b.status == BidStatus.rejected).toList();

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Listing header.
            InkWell(
              onTap: () => _openListing(context, listingId),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: textTheme.titleMedium),
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
            const SizedBox(height: 12),

            // Accepted offer banner (exclusive reservation).
            for (final bid in accepted) ...[
              GlassCard(
                padding: const EdgeInsets.all(12),
                borderRadius: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Accepted: ${formatINR(bid.amount)} from '
                            "${bid.buyerName ?? 'buyer'}",
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _statusChip(_acceptedOptimistic.contains(bid.id)
                            ? BidStatus.accepted
                            : bid.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Reserved for this buyer until they pay.',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_busyIds.contains(bid.id))
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
                        onPressed: () =>
                            _cancelAcceptance(context, ref, bid),
                        child: const Text('Cancel acceptance'),
                      ),
                  ],
                ),
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
                        title: Text(
                          "${bid.buyerName ?? 'Buyer'} · "
                          '${formatINR(bid.amount)}',
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
    // Swipe right to accept, left to reject — the buttons stay for
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
            borderRadius: BorderRadius.circular(12),
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
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
      child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // NOTE: not const — Border.all has no const constructor.
        color: AppColors.surface,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "${bid.buyerName ?? 'Buyer'} · ${timeAgo(bid.createdAt)}",
                  style: textTheme.bodyMedium,
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
                    child: const Text('Reject'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PressScale(
                  child: ElevatedButton(
                    onPressed: busy ? null : onAccept,
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
