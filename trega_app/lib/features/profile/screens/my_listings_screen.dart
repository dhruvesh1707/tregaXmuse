import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/listing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/status_chip.dart';
import '../../listing_detail/screens/listing_detail_screen.dart';
import '../../sell/screens/sell_flow_screen.dart';

/// "My Listings" — everything the signed-in user is selling, across all
/// statuses (live → sold, plus draft/flagged edge cases).
///
/// Also the only place the seller can see their private pickup address
/// (stored under `listings/{id}/private/details`, never public).
class MyListingsScreen extends ConsumerWidget {
  static const String routeName = '/profile/listings';

  const MyListingsScreen({super.key});

  ({Color bg, Color fg, String label}) _chipFor(ListingStatus status) {
    switch (status) {
      case ListingStatus.draft:
        return (
          bg: const Color(0xFFEEEEEE),
          fg: const Color(0xFF616161),
          label: 'Draft'
        );
      case ListingStatus.pending:
        return (
          bg: AppColors.accentSoft,
          fg: AppColors.textPrimary,
          label: 'In review'
        );
      case ListingStatus.live:
        return (
          bg: const Color(0xFFE8F5E9),
          fg: AppColors.success,
          label: 'Live'
        );
      case ListingStatus.sold:
        return (
          bg: AppColors.primarySoft,
          fg: AppColors.primaryDark,
          label: 'Sold'
        );
      case ListingStatus.rejected:
        return (
          bg: const Color(0xFFFDECEA),
          fg: AppColors.error,
          label: 'Rejected'
        );
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Listing listing,) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete listing?'),
        content: Text(
            '“${listing.product.title}” will be permanently removed. This can’t be undone.',),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.error,),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(firestoreServiceProvider).deleteListing(listing.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing deleted.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete this listing right now.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showPickupAddress(
      BuildContext context, WidgetRef ref, String listingId,) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pickup address'),
        content: StreamBuilder<Map<String, dynamic>?>(
          stream: ref
              .read(firestoreServiceProvider)
              .watchListingPrivateDetails(listingId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 64,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final raw = snap.data?['pickupAddress'];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatPickupAddress(raw),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(PhosphorIconsRegular.lock,
                        size: 14,
                        color: AppColors.textSecondary,),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Only you and the Trega team can see this — buyers never see your address.',
                        style:
                            Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    final service = ref.watch(firestoreServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Listings')),
      body: uid == null
          ? const EmptyState(
              icon: PhosphorIconsRegular.package,
              title: 'Not signed in',
              subtitle: 'Sign in to see the items you’re selling.',
            )
          : StreamBuilder<List<Listing>>(
              stream: service.watchSellerListings(uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(),);
                }
                final listings = snap.data ?? [];
                if (listings.isEmpty) {
                  return EmptyState(
                    icon: PhosphorIconsRegular.package,
                    title: 'No listings yet',
                    subtitle:
                        'Sell your pre-owned gear in 30 seconds — photos, details, price, done.',
                    actionLabel: 'Sell an item',
                    onAction: () => Navigator.of(context)
                        .pushNamed(SellFlowScreen.routeName),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: listings.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final listing = listings[i];
                    final chip = _chipFor(listing.status);
                    final photo =
                        listing.product.imageUrls.isNotEmpty
                            ? listing.product.imageUrls.first
                            : null;
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.of(context).pushNamed(
                          ListingDetailScreen.routeName,
                          arguments: ListingDetailArgs(
                            listingId: listing.id,
                            initial: listing,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(10),
                                child: photo != null
                                    ? CachedNetworkImage(
                                        imageUrl: photo,
                                        width: 72,
                                        height: 72,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            _thumbFallback(),
                                      )
                                    : _thumbFallback(),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      listing.product.title,
                                      maxLines: 2,
                                      overflow:
                                          TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatINR(listing.price),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              color:
                                                  AppColors.primary,),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${listing.viewsCount} views • ${timeAgo(listing.createdAt)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                children: [
                                  StatusChip(
                                    label: chip.label,
                                    background: chip.bg,
                                    foreground: chip.fg,
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons
                                        .more_vert,),
                                    onSelected: (value) {
                                      if (value == 'address') {
                                        _showPickupAddress(
                                            context,
                                            ref,
                                            listing.id,);
                                      } else if (value ==
                                          'delete') {
                                        _confirmDelete(
                                            context,
                                            ref,
                                            listing,);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'address',
                                        child: Text(
                                            'Pickup address',),
                                      ),
                                      if (listing.status !=
                                          ListingStatus.sold)
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete',
                                              style: TextStyle(
                                                  color: AppColors
                                                      .error,),),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _thumbFallback() {
    return Container(
      width: 72,
      height: 72,
      color: AppColors.primarySoft,
      child:
          const Icon(PhosphorIconsRegular.image, color: AppColors.primary),
    );
  }

  /// Formats the stored pickup address. New listings store a structured
  /// map (`line1`, `line2`, `city`, `state`, `pincode`); older ones may
  /// still hold a plain string.
  String _formatPickupAddress(Object? raw) {
    if (raw is Map) {
      final line1 = (raw['line1'] ?? '').toString().trim();
      final line2 = (raw['line2'] ?? '').toString().trim();
      final city = (raw['city'] ?? '').toString().trim();
      final state = (raw['state'] ?? '').toString().trim();
      final pin = (raw['pincode'] ?? '').toString().trim();
      final lines = <String>[
        if (line1.isNotEmpty) line1,
        if (line2.isNotEmpty) line2,
        [
          if (city.isNotEmpty) city,
          if (state.isNotEmpty) state,
        ].join(', ') +
            (pin.isNotEmpty ? ' — $pin' : ''),
      ].where((l) => l.trim().isNotEmpty && l.trim() != '—').toList();
      if (lines.isNotEmpty) return lines.join('\n');
    } else if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return 'No pickup address saved for this listing.';
  }
}
