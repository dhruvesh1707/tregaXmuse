import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/sample_data.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/product_card.dart';
import '../../home/providers/listing_providers.dart';
import '../../listing_detail/screens/listing_detail_screen.dart';

/// Route arguments for [CategoryScreen].
class CategoryArgs {
  final String categoryId;
  final String categoryName;

  const CategoryArgs({required this.categoryId, required this.categoryName});
}

/// Listings within a single category, streamed from Firestore
/// (`listings` where `categoryId` == id and `status` == live).
class CategoryScreen extends ConsumerWidget {
  static const String routeName = '/category';

  final CategoryArgs? args;

  const CategoryScreen({super.key, this.args});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = args?.categoryName ?? 'Category';
    final categoryId = args?.categoryId ?? '';

    final listingsAsync = categoryId.isEmpty
        ? null
        : ref.watch(categoryListingsProvider(categoryId));

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: listingsAsync == null
          ? const Center(child: Text('Pick a category to browse.'))
          : listingsAsync.when(
              data: (listings) => listings.isEmpty
                  ? const EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No listings yet',
                      subtitle:
                          'Be the first to list gear in this category.',
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
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, __) {
                final listings = SampleData.listings
                    .where((l) => l.product.categoryId == categoryId)
                    .toList();
                return listings.isEmpty
                    ? const EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'No listings yet',
                        subtitle:
                            'Be the first to list gear in this category.',
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
                      );
              },
            ),
    );
  }
}
