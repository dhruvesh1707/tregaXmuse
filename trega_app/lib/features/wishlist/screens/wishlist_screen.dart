import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/trega_scaffold.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/listing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/no_internet_state.dart';
import '../../../core/widgets/product_card.dart';
import '../../listing_detail/screens/listing_detail_screen.dart';

/// Saved listings: Firestore `listings` where `likedBy` contains the uid.
class WishlistScreen extends ConsumerStatefulWidget {
  static const String routeName = '/wishlist';

  const WishlistScreen({super.key});

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen> {
  /// Bumped on retry so the StreamBuilder resubscribes with a fresh stream.
  int _streamNonce = 0;

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final stream =
        uid == null ? null : ref.watch(firestoreServiceProvider).watchWishlist(uid);

    if (stream == null) {
      return const TregaScaffold(
        body: SafeArea(
          child: EmptyState(
            icon: PhosphorIconsRegular.signIn,
            title: 'Sign in required',
            subtitle: 'Sign in to see your wishlist.',
          ),
        ),
      );
    }
    return StreamBuilder<List<Listing>>(
      key: ValueKey(_streamNonce),
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return TregaScaffold(
            appBar: AppBar(title: const Text('Wishlist')),
            body: GridView.builder(
              padding: const EdgeInsets.all(16),
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.68,
              ),
              itemCount: 6,
              itemBuilder: (context, i) => const ProductCardSkeleton(),
            ),
          );
        }
        if (snap.hasError) {
          return TregaScaffold(
            appBar: AppBar(title: const Text('Wishlist')),
            body: SafeArea(
              child: errorStateFor(
                snap.error!,
                title: 'Couldn\'t load wishlist',
                onRetry: () => setState(() => _streamNonce++),
              ),
            ),
          );
        }
        return _WishlistGrid(listings: snap.data ?? const []);
      },
    );
  }
}

class _WishlistGrid extends StatelessWidget {
  final List<Listing> listings;

  const _WishlistGrid({required this.listings});

  @override
  Widget build(BuildContext context) {
    return TregaScaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      body: listings.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsRegular.heart,
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
                return FadeSlideIn(
                  delay: Duration(milliseconds: (i % 8) * 45),
                  child: ProductCard(
                    listing: listing,
                    onTap: () => Navigator.of(context).pushNamed(
                      ListingDetailScreen.routeName,
                      arguments: ListingDetailArgs(
                        listingId: listing.id,
                        initial: listing,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
