import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/category.dart';
import '../../../core/models/listing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_tour.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/no_internet_state.dart';
import '../../../core/widgets/floating_tab_bar.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/trega_scaffold.dart';
import '../../bids/screens/bids_offers_screen.dart';
import '../../listing_detail/screens/listing_detail_screen.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../search/screens/category_screen.dart';
import '../../search/screens/search_screen.dart';
import '../../sell/screens/sell_flow_screen.dart';
import '../providers/listing_providers.dart';
import '../widgets/promo_banner_carousel.dart';

/// The home header's single gradient: solid espresso at the top edge,
/// seamless with the toolbar, flowing to espressoLight at the bottom
/// of the categories block. The toolbar, the refresh reveal area, and
/// the categories block all share it, so the header reads as one
/// surface with one light, never two stacked gradients.
const _homeHeaderGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [AppColors.espresso, AppColors.espressoLight],
);

/// Main marketplace feed: search entry, "Explore by Passion" categories,
/// and the live listing feed.
///
/// Two-tone page: a deep espresso header zone holds the wordmark, the
/// search and notifications actions, and the category photo tiles, and
/// the warm cream body below holds the promo carousel and the listing
/// feed. Surfaces are flat and solid, no frosted glass.
///
/// Data comes from Firestore (`listings` where `status == live`,
/// `categories` where `active == true`). Errors surface an inline error
/// state, no demo data is ever shown.
class HomeScreen extends ConsumerWidget {
  static const String routeName = '/home';

  const HomeScreen({super.key});

  /// The first-run tour gate runs at most once per app session; the
  /// account-level decision lives in Firestore (see shouldShowTour).
  static bool _tourGateChecked = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(liveListingsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final unread = ref.watch(unreadNotificationsProvider).valueOrNull ?? 0;

    // First-run spotlight tour: brand-new accounts only, shown once.
    final uid = ref.watch(currentUidProvider);
    if (uid != null && !_tourGateChecked) {
      _tourGateChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final service = ref.read(firestoreServiceProvider);
        var show = false;
        try {
          show = await service.shouldShowTour(uid);
        } catch (_) {
          show = false; // Offline or read failed: no tour, no crash.
        }
        if (!show) return;
        // Give the feed a moment to land so the tour can point at a
        // real listing and open it for the offer-button step.
        var listings = const <Listing>[];
        for (var i = 0; i < 10; i++) {
          listings = ref.read(liveListingsProvider).valueOrNull ?? const [];
          if (listings.isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        if (!context.mounted) return;
        final first = listings.isEmpty ? null : listings.first;
        AppTour.start(
          context: context,
          hasListings: first != null,
          openFirstListing: () {
            if (first == null) return;
            Navigator.of(context).pushNamed(
              ListingDetailScreen.routeName,
              arguments: ListingDetailArgs(
                listingId: first.id,
                initial: first,
              ),
            );
          },
          onDone: () => service.markTourSeen(uid),
        );
      });
    }

    return TregaScaffold(
      body: Stack(
        children: [
          EasyRefresh.builder(
            // Seamless refresh: the reveal area paints the same
            // espresso gradient as the header zone, so pulling down
            // stretches the main block instead of tearing it open
            // with a white gap. Text and icon stay cream on espresso.
            // Builder form on purpose: the refresh physics is scoped
            // to the feed's CustomScrollView only. The plain
            // EasyRefresh form applies its physics to every
            // descendant scroll view, so swiping the horizontal
            // category rail or promo carousel drove the header
            // sideways onto the left edge. With the builder, nested
            // scroll views keep platform physics and refresh only
            // ever comes from the top.
            header: const ClassicHeader(
              boxDecoration: BoxDecoration(
                gradient: _homeHeaderGradient,
              ),
              textStyle: TextStyle(color: Colors.white, fontSize: 12),
              messageStyle: TextStyle(
                  color: AppColors.onEspressoSecondary, fontSize: 12),
              iconTheme: IconThemeData(color: AppColors.accent),
              processedText: 'All caught up',
            ),
            onRefresh: () async {
              // The feed notifier serves its disk cache first, so this
              // completes fast and the stream refills in the background.
              await Future.wait([
                ref.refresh(liveListingsProvider.future),
                ref.refresh(categoriesProvider.future),
              ]);
            },
            childBuilder: (context, physics) => CustomScrollView(
              physics: physics,
              slivers: [
                SliverAppBar(
                  // Pinned: the espresso header (logo, search,
                  // notifications) stays visible while the feed scrolls
                  // underneath it. The toolbar is solid espresso and the
                  // categories block below continues the same gradient
                  // from espresso, so the whole header is one surface.
                  pinned: true,
                  floating: true,
                  backgroundColor: AppColors.espresso,
                  foregroundColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  iconTheme: const IconThemeData(color: Colors.white),
                  title: Image.asset('assets/logo/trega_logo_light.png', height: 28),
                  actions: [
                    IconButton(
                      key: TourKeys.search,
                      icon: const Icon(PhosphorIconsRegular.magnifyingGlass),
                      onPressed: () => Navigator.of(context)
                          .pushNamed(SearchScreen.routeName),
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
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: _homeHeaderGradient,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(24),
                      ),
                    ),
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: _HeaderGlow(
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(24),
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 4, 20, 12),
                              child: Text(
                                'Explore by Passion',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(color: Colors.white),
                              ),
                            ),
                            KeyedSubtree(
                              key: TourKeys.categories,
                              child: _CategoryRail(
                                  categoriesAsync: categoriesAsync),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 16, bottom: 4),
                    child: PromoBannerCarousel(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'Fresh listings',
                    actionLabel: 'See all',
                    onAction: () => Navigator.of(context)
                        .pushNamed(SearchScreen.routeName),
                  ),
                ),
                listingsAsync.when(
                  data: (listings) => listings.isEmpty
                      ? const SliverToBoxAdapter(
                          child: EmptyState(
                            icon: PhosphorIconsRegular.package,
                            title: 'No listings yet',
                            subtitle:
                                'Be the first to list your gear on Trega.',
                          ),
                        )
                      : _ListingGrid(
                          listings: listings,
                          firstCardKey: TourKeys.firstCard,
                        ),
                  loading: () => SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                  error: (e, __) => SliverToBoxAdapter(
                    child: errorStateFor(
                      e,
                      title: 'Couldn\'t load listings',
                      onRetry: () => ref.invalidate(liveListingsProvider),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
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
                  itemKeys: [
                    null,
                    null,
                    TourKeys.tabSell,
                    TourKeys.tabBids,
                    TourKeys.tabProfile,
                  ],
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

/// Soft warm glow over an espresso header surface, matching the
/// reference frames' ambient light. The light pools low around the
/// category tiles and fades to transparent at the top edge, so the
/// categories block meets the solid toolbar with no tone step and the
/// header reads as one surface. Pure decoration, no interaction.
class _HeaderGlow extends StatelessWidget {
  const _HeaderGlow({this.borderRadius});

  final BorderRadiusGeometry? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: RadialGradient(
          center: const Alignment(0.0, 0.75),
          radius: 1.15,
          colors: [
            AppColors.primaryLight.withValues(alpha: 0.28),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

/// Maps a category to its photo tile asset, matching in order the
/// category id, then slug, then lowercased name, against the known
/// category photo keys. Returns null for unknown or admin-added
/// categories, which fall back to the Phosphor icon tile.
String? _categoryPhotoAsset(Category category) {
  for (final raw in <String>[category.id, category.slug, category.name]) {
    final key = _categoryPhotoKey(raw);
    if (key != null) return 'assets/categories/$key.jpg';
  }
  return null;
}

/// Normalizes one raw category key (id, slug, or name) to a photo key,
/// or null when it matches nothing known. Separators are ignored, so
/// 'home appliances', 'home_appliances' and 'home-appliances' all map
/// to the appliances photo. Plurals and common aliases map to their
/// photo key, and an unmatched key ending in 's' is retried singular,
/// so a plural id like 'laptops' still finds the laptop photo.
String? _categoryPhotoKey(String raw) {
  final normalized = raw
      .trim()
      .toLowerCase()
      .replaceAll(' ', '')
      .replaceAll('_', '')
      .replaceAll('-', '');
  const known = <String>{
    'gaming',
    'mobile',
    'laptop',
    'camera',
    'music',
    'fashion',
    'furniture',
    'appliances',
    'cycles',
    'books',
    'watch',
    'collectible',
    'others',
  };
  const aliases = <String, String>{
    'mobiles': 'mobile',
    'laptops': 'laptop',
    'cameras': 'camera',
    'phones': 'mobile',
    'cellphones': 'mobile',
    'homeappliances': 'appliances',
    'watches': 'watch',
    'collectibles': 'collectible',
    'bicycles': 'cycles',
  };
  final alias = aliases[normalized];
  if (alias != null) return alias;
  if (known.contains(normalized)) return normalized;
  if (normalized.endsWith('s') && normalized.length > 2) {
    final singular = normalized.substring(0, normalized.length - 1);
    if (known.contains(singular)) return singular;
  }
  return null;
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.categoriesAsync});

  final AsyncValue<List<Category>> categoriesAsync;

  @override
  Widget build(BuildContext context) {
    final categories = categoriesAsync.valueOrNull ?? const <Category>[];
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final category = categories[i];
          return Entrance(
            index: i,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => Navigator.of(context).pushNamed(
                CategoryScreen.routeName,
                arguments: CategoryArgs(
                  categoryId: category.id,
                  categoryName: category.name,
                ),
              ),
              child: SizedBox(
                width: 76,
                child: Column(
                  children: [
                    _CategoryTile(category: category),
                    const SizedBox(height: 8),
                    Text(
                      category.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: AppColors.onEspressoSecondary,
                            fontWeight: FontWeight.w600,
                          ),
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

/// Category photo tile: a cream squircle holding the category photo,
/// clipped cover. Unknown or admin-added categories, and any photo
/// asset that fails to load, fall back to the Phosphor icon tile, so
/// the rail never shows a blank tile.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    final asset = _categoryPhotoAsset(category);
    if (asset == null) return _CategoryIconTile(category: category);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 72,
        height: 72,
        color: AppColors.tileBackground,
        child: Image.asset(
          asset,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _CategoryIconTile(category: category),
        ),
      ),
    );
  }
}

/// Fallback tile for categories with no photo: the category icon on a
/// cream squircle.
class _CategoryIconTile extends StatelessWidget {
  const _CategoryIconTile({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.tileBackground,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(category.icon, size: 28, color: AppColors.primary),
        ],
      ),
    );
  }
}

class _ListingGrid extends StatelessWidget {
  const _ListingGrid({required this.listings, this.firstCardKey});

  final List<Listing> listings;

  /// Anchor for the first card, used by the first-run tour.
  final Key? firstCardKey;

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
            final card = Entrance(
              // Staggered entrance: the cascade restarts every 8 items
              // so long scrolls keep feeling alive.
              index: i % 8,
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
            // The tour points at the first real card in the feed.
            if (i == 0 && firstCardKey != null) {
              return KeyedSubtree(key: firstCardKey, child: card);
            }
            return card;
          },
          childCount: listings.length,
        ),
      ),
    );
  }
}
