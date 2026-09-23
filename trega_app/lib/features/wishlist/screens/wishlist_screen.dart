import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/sample_data.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/listing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/product_card.dart';
import '../../listing_detail/screens/listing_detail_screen.dart';

/// Saved listings: Firestore `listings` where `likedBy` contains the uid.
///
/// Falls back to [SampleData] when Firestore is unreachable.
class WishlistScreen extends ConsumerWidget {
  static const String routeName = '/wishlist';

  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    final stream =
        uid == null ? null : ref.watch(firestoreServiceProvider).watchWishlist(uid);

    if (stream == null) {
      return _WishlistGrid(listings: SampleData.listings, demo: true);
    }
    return StreamBuilder<List<Listing>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Wishlist')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return _WishlistGrid(
            listings:
                SampleData.listings.where((l) => l.isLiked).toList(),
            demo: true,
          );
        }
        return _WishlistGrid(listings: snap.data ?? const []);
      },
    );
  }
}

class _WishlistGrid extends StatelessWidget {
  final List<Listing> listings;
  final bool demo;

  const _WishlistGrid({required this.listings, this.demo = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      body: listings.isEmpty
          ? const EmptyState(
              icon: Icons.favorite_outline,
              title: 'Nothing saved yet',
              subtitle:
                  'Tap the heart on any listing to save it here.',
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.68,
              ),
              itemCount: listings.length,
              itemBuilder: (context, i) {
                final listing = listings[i];
                return ProductCard(
                  listing: listing,
                  onTap: () => Navigator.of(context).pushNamed(
                    ListingDetailScreen.routeName,
                    arguments: listing.id,
                  ),
                );
              },
            ),
    );
  }
}
