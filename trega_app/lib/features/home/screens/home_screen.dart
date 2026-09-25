import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/category.dart';
import '../../../core/models/listing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/floating_tab_bar.dart';
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
import '../widgets/promo_banner_carousel.dart';

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
    final unread = ref.watch(unreadNotificationsProvider).valueOrNull ?? 0;

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Image.asset('assets/logo/trega_logo.png', height: 28),
            actions: [
              IconButton(
                icon: const Icon(PhosphorIconsRegular.magnifyingGlass),
                onPressed: () =>
                    Navigator.of(context).pushNamed(SearchScreen.routeName),
              ),
              IconButton(
                icon: unread > 0
                    ? Badge(
                        label: Text(unread > 99 ? '99+' : '$unread'),
                        child: const Icon(PhosphorIconsRegular.bell),
                      )
                    : const Icon(PhosphorIconsRegular.bell),
                onPressed: () => Navigator.of(context)
                    .pushNamed(NotificationsScreen.routeName),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Explore by Passion',
              onSeeAll: () => _showAllCategories(context),
            ),
          ),
          SliverToBoxAdapter(
            child: _CategoryRail(categoriesAsync: categoriesAsync),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: 4),
              child: PromoBannerCarousel(),
            ),
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
                      icon: PhosphorIconsRegular.package,
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
                icon: PhosphorIconsRegular.cloudSlash,
                title: 'Couldn\'t load listings',
                subtitle: 'Check your connection and try again.',
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: FloatingTabBar(
                  currentIndex: 0,
                  onTap: (i) {
                    // Bottom-nav destinations: Home / Search / Sell / Bids /
                    // Profile. (Haptics live inside FloatingTabBar.)
                    switch (i) {
                      case 1:
                        Navigator.of(context)
                            .pushNamed(SearchScreen.routeName);
                      case 2:
                        Navigator.of(context)
                            .pushNamed(SellFlowScreen.routeName);
                      case 3:
                        Navigator.of(context)
                            .pushNamed(BidsOffersScreen.routeName);
                      case 4:
                        Navigator.of(context)
                            .pushNamed(ProfileScreen.routeName);
                      case 0:
                      default:
                        break; // Already on Home.
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "See all" for Explore by Passion: a bottom sheet with every category.
/// Tapping a category opens its listings on the CategoryScreen.
///
/// The sheet watches [categoriesProvider] itself instead of taking a
/// snapshot of the list at tap time: on a cold start (or slow network)
/// the categories may still be loading when the user taps "See all", and
/// a snapshot would render a permanently empty sheet.
void _showAllCategories(BuildContext context) {
  showCupertinoModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'All categories',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Flexible(
            child: Consumer(
              builder: (context, ref, _) {
                final categoriesAsync = ref.watch(categoriesProvider);
                return categoriesAsync.when(
                  data: (categories) => ListView.builder(
                    shrinkWrap: true,
                    itemCount: categories.length,
                    itemBuilder: (context, i) {
                      final category = categories[i];
                      return ListTile(
                        leading: Icon(
                          category.icon,
                          color: AppColors.primary,
                        ),
                        title: Text(category.name),
                        trailing:
                            const Icon(PhosphorIconsRegular.caretRight),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          Navigator.of(context).pushNamed(
                            CategoryScreen.routeName,
                            arguments: CategoryArgs(
                              categoryId: category.id,
                              categoryName: category.name,
                            ),
                          );
                        },
                      );
                    },
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "Couldn't load categories. Please try again.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
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
          );
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
                  arguments: ListingDetailArgs(
                    listingId: listing.id,
                    initial: listing,
                  ),
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