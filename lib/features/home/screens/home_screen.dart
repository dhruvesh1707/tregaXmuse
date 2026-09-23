import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/category.dart';
import '../../../core/models/listing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../bids/screens/bids_offers_screen.dart';
import '../../listing_detail/screens/listing_detail_screen.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../search/screens/category_screen.dart';
import '../../search/screens/search_screen.dart';
import '../../sell/screens/sell_flow_screen.dart';
import '../providers/listing_providers.dart';

/// Main marketplace feed: search entry, "Explore by Passion" categories,
/// and the live listing feed.
///
/// Data comes from Firestore (`listings` where `status == live`,
/// `categories` where `active == true`). Errors surface an inline error
/// state — no demo data is ever shown.
class HomeScreen extends ConsumerWidget {
  static const String routeName = '/home';

  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(liveListingsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Image.asset('assets/logo/trega_logo.png', height: 28),
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () =>
                    Navigator.of(context).pushNamed(SearchScreen.routeName),
              ),
              IconButton(
                icon: const Badge(
                  label: Text('3'),
                  child: Icon(Icons.notifications_outlined),
                ),
                onPressed: () => Navigator.of(context)
                    .pushNamed(NotificationsScreen.routeName),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Explore by Passion',
              onSeeAll: () {
                // TODO: open full category list (bottom sheet or screen).
              },
            ),
          ),
          SliverToBoxAdapter(
            child: _CategoryRail(categoriesAsync: categoriesAsync),
          ),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Fresh listings',
              onSeeAll: () =>
                  Navigator.of(context).pushNamed(SearchScreen.routeName),
            ),
          ),
          listingsAsync.when(
            data: (listings) => listings.isEmpty
                ? const SliverToBoxAdapter(
                    child: EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No listings yet',
                      subtitle: 'Be the first to list your gear on Trega.',
                    ),
                  )
                : _ListingGrid(listings: listings),
            loading: () => SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.68,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => const ProductCardSkeleton(),
                  childCount: 6,
                ),
              ),
            ),
            error: (_, __) => const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Couldn\'t load listings',
                subtitle: 'Check your connection and try again.',
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (i) {
          TregaHaptics.tap();
          // Bottom-nav destinations: Home / Search / Sell / Bids / Profile.
          switch (i) {
            case 1:
              Navigator.of(context).pushNamed(SearchScreen.routeName);
            case 2:
              Navigator.of(context).pushNamed(SellFlowScreen.routeName);
            case 3:
              Navigator.of(context).pushNamed(BidsOffersScreen.routeName);
            case 4:
              Navigator.of(context).pushNamed(ProfileScreen.routeName);
            case 0:
            default:
              break; // Already on Home.
          }
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.search_outlined),
              activeIcon: Icon(Icons.search),
              label: 'Search'),
          BottomNavigationBarItem(
              icon: Icon(Icons.add_circle_outline),
              activeIcon: Icon(Icons.add_circle),
              label: 'Sell'),
          BottomNavigationBarItem(
              icon: Icon(Icons.gavel_outlined),
              activeIcon: Icon(Icons.gavel),
              label: 'Bids'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.categoriesAsync});

  final AsyncValue<List<Category>> categoriesAsync;

  @override
  Widget build(BuildContext context) {
    final categories = categoriesAsync.valueOrNull ?? const <Category>[];
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final category = categories[i];
          return FadeSlideIn(
            delay: Duration(milliseconds: i * 60),
            duration: const Duration(milliseconds: 400),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context).pushNamed(
                CategoryScreen.routeName,
                arguments: CategoryArgs(
                  categoryId: category.id,
                  categoryName: category.name,
                ),
              ),
              child: Container(
                width: 84,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(category.icon, size: 28, color: AppColors.primary),
                    const SizedBox(height: 6),
                    Text(
                      category.name,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        },
      ),
    );
  }
}

class _ListingGrid extends StatelessWidget {
  const _ListingGrid({required this.listings});

  final List<Listing> listings;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.68,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final listing = listings[i];
            return FadeSlideIn(
              // Staggered entrance: first two rows cascade in.
              delay: Duration(milliseconds: (i % 8) * 45),
              child: ProductCard(
                listing: listing,
                onTap: () => Navigator.of(context).pushNamed(
                  ListingDetailScreen.routeName,
                  arguments: listing.id,
                ),
              ),
            );
          },
          childCount: listings.length,
        ),
      ),
    );
  }
}
