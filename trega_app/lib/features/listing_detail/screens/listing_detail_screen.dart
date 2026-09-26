import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:page_transition/page_transition.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../core/delivery/express_delivery.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/firebase/functions_service.dart';
import '../../../core/models/bid.dart';
import '../../../core/models/listing.dart';
import '../../../core/models/product.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/condition_badge.dart';
import '../../../core/widgets/express_widgets.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/trega_button.dart';
import '../../../core/widgets/trega_toast.dart';
import '../widgets/gallery_viewer.dart';
import '../../bids/screens/bids_offers_screen.dart';
import '../../checkout/screens/checkout_screen.dart';
import '../../home/providers/listing_providers.dart';
import '../../profile/screens/kyc_screen.dart';

/// Full listing page: media gallery (photos + video), condition badge,
/// verified seller card, specs, and the single state-driven offer action.
///
/// The bottom bar shows exactly one action, driven by state:
/// - buyer, no offer yet -> "Make an Offer" (Aadhaar-verified only)
/// - buyer, offer open -> "Offer sent — awaiting the seller" (disabled)
/// - buyer, offer rejected -> "Offer again"
/// - buyer, offer accepted -> "Buy Now at ₹X" -> checkout with address
/// - seller -> "Manage Offers"
///
/// Streams the listing document from Firestore.
///
/// TODO(detail): implement video playback with video_player when
/// product.videoUrl is present.
/// Route arguments for [ListingDetailScreen].
///
/// Screens that already hold the full [Listing] (feed, search, wishlist)
/// pass it as [initial] so the page paints on the first frame with zero
/// loading state; the live stream then refreshes it in the background.
class ListingDetailArgs {
  final String listingId;
  final Listing? initial;

  const ListingDetailArgs({required this.listingId, this.initial});
}

class ListingDetailScreen extends ConsumerStatefulWidget {
  static const String routeName = '/listing';

  final String? listingId;

  /// The listing object the caller already had, if any — used to paint the
  /// first frame instantly while the live document streams in.
  final Listing? initialListing;

  const ListingDetailScreen({super.key, this.listingId, this.initialListing});

  @override
  ConsumerState<ListingDetailScreen> createState() =>
      _ListingDetailScreenState();
}

class _ListingDetailScreenState extends ConsumerState<ListingDetailScreen> {
  int _page = 0;

  @override
  void initState() {
    super.initState();
    // Count a view once per screen open (server increments the counter).
    final id = widget.listingId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(firestoreServiceProvider).incrementViews(id).catchError((_) {});
      });
    }
  }

  /// Opens the offer sheet, then places the offer server-side.
  ///
  /// Only Aadhaar-verified buyers can make offers — unverified users get a
  /// prompt and are routed to the KYC screen.
  Future<void> _makeOffer(BuildContext context, Listing listing) async {
    final uid = ref.read(currentUidProvider);
    if (uid != null) {
      final me = await ref.read(firestoreServiceProvider).getUser(uid);
      if (me == null || !me.isKycVerified) {
        if (!context.mounted) return;
        await showTregaToast(
          context,
          'Only Aadhaar-verified buyers can make offers.',
          title: 'Verification needed',
          kind: TregaToastKind.info,
        );
        if (!context.mounted) return;
        Navigator.of(context).pushNamed(KycScreen.routeName);
        return;
      }
    }

    if (!context.mounted) return;
    final amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OfferSheet(price: listing.price),
    );
    if (amount == null || amount <= 0) return;
    try {
      await ref.read(functionsServiceProvider).placeBid(
            listingId: listing.id,
            amount: amount,
          );
      if (!context.mounted) return;
      await showTregaToast(
        context,
        'The seller has been notified and can accept or reject.',
        title: 'Offer sent',
        kind: TregaToastKind.success,
      );
    } catch (e) {
      if (!context.mounted) return;
      await showTregaToast(
        context,
        functionsErrorMessage(e,
            fallback: 'Could not send the offer. Try again.',),
        title: 'Offer failed',
        kind: TregaToastKind.error,
      );
    }
  }

  /// Reports the listing to the Trega team (reactive moderation).
  ///
  /// Fixed reasons, one report per user per listing (enforced by the
  /// `{listingId}_{uid}` doc ID in `reportListing`).
  Future<void> _reportListing(BuildContext context, Listing listing) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      await showTregaToast(
        context,
        'Sign in to report a listing.',
        kind: TregaToastKind.info,
      );
      return;
    }
    if (listing.seller.id == uid) {
      await showTregaToast(
        context,
        "You can't report your own listing.",
        kind: TregaToastKind.info,
      );
      return;
    }
    final reason = await showCupertinoModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ReportSheet(),
    );
    if (reason == null || !mounted) return;
    try {
      await ref.read(firestoreServiceProvider).reportListing(
            listingId: listing.id,
            reporterId: uid,
            reason: reason,
          );
      if (!context.mounted) return;
      await showTregaToast(
        context,
        'Our team will review this listing shortly.',
        title: 'Report submitted',
        kind: TregaToastKind.success,
      );
    } catch (_) {
      if (!context.mounted) return;
      await showTregaToast(
        context,
        "Couldn't submit the report. Try again.",
        title: 'Something went wrong',
        kind: TregaToastKind.error,
      );
    }
  }

  Future<void> _toggleLike(Listing listing) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    await ref
        .read(firestoreServiceProvider)
        .toggleLike(listing.id, uid, listing.isLiked);
  }

  @override
  Widget build(BuildContext context) {
    final listingId = widget.listingId;
    if (listingId == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Listing not found.')),
      );
    }
    final listingAsync = ref.watch(listingDetailProvider(listingId));
    final initial = widget.initialListing;
    return listingAsync.when(
      data: (listing) => listing == null
          ? (initial == null
              ? Scaffold(
                  appBar: AppBar(),
                  body: const Center(child: Text('Listing not found.')),
                )
              : _buildContent(context, initial))
          : _buildContent(context, listing),
      // Paint the known listing instantly; the stream fills in behind it.
      loading: () => initial != null
          ? _buildContent(context, initial)
          : Scaffold(
              appBar: AppBar(),
              body: const Center(child: CircularProgressIndicator()),
            ),
      error: (_, __) => initial != null
          ? _buildContent(context, initial)
          : Scaffold(
              appBar: AppBar(),
              body: const Center(
                child:
                    Text('Couldn\'t load this listing. Check your connection.'),
              ),
            ),
    );
  }

  Widget _buildContent(BuildContext context, Listing listing) {
    final product = listing.product;
    final seller = listing.seller;
    final expressConfig = ref.watch(expressConfigProvider).valueOrNull ??
        ExpressDeliveryConfig.defaults;
    final expressEligible = expressConfig.isCityEligible(listing.city);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    itemCount: product.imageUrls.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) {
                      final image = CachedNetworkImage(
                        imageUrl: product.imageUrls[i],
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: AppColors.primarySoft,
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: AppColors.primarySoft,
                          child: const Icon(PhosphorIconsRegular.prohibit),
                        ),
                      );
                      // Tap zooms into the full-screen viewer. The Hero
                      // flight target for the feed card's photo stays on
                      // the first page, untouched.
                      final page = i == 0
                          ? Hero(
                              tag: 'listing-photo-${listing.id}',
                              child: image,
                            )
                          : image;
                      return GestureDetector(
                        onTap: () => _openGallery(
                            context, product.imageUrls, i,),
                        child: page,
                      );
                    },
                  ),
                  if (product.videoUrl != null)
                    // TODO: replace with inline video_player preview.
                    const Positioned(
                      bottom: 16,
                      right: 16,
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: Icon(PhosphorIconsRegular.play, color: Colors.white),
                      ),
                    ),
                  if (product.imageUrls.length > 1)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: AnimatedSmoothIndicator(
                          activeIndex: _page,
                          count: product.imageUrls.length,
                          effect: const ExpandingDotsEffect(
                            dotWidth: 8,
                            dotHeight: 8,
                            spacing: 5,
                            expansionFactor: 2.2,
                            activeDotColor: Colors.white,
                            dotColor: Colors.white54,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              LikeButton(
                isLiked: listing.isLiked,
                unlikedColor: Colors.white,
                onTap: () => _toggleLike(listing),
              ),
              IconButton(
                icon: const Icon(PhosphorIconsRegular.shareNetwork),
                onPressed: () => _shareListing(listing),
              ),
              IconButton(
                icon: const Icon(PhosphorIconsRegular.flag),
                tooltip: 'Report listing',
                onPressed: () => _reportListing(context, listing),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Entrance(
              // Plays once on first paint; stream rebuilds keep the state
              // so it never replays when listing data refreshes.
              child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ConditionBadge(condition: product.condition),
                      const SizedBox(width: 8),
                      if (seller.isVerifiedSeller)
                        const _VerifiedPill(),
                      const Spacer(),
                      Text(
                        '${listing.viewsCount} views',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(product.title,
                      style: Theme.of(context).textTheme.headlineSmall,),
                  const SizedBox(height: 4),
                  Text(
                    formatINR(listing.price),
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(color: AppColors.primary),
                  ),
                  if (listing.negotiable)
                    Text(
                      'Negotiable — make an offer below',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.success),
                    ),
                  if (expressEligible) ...[
                    const SizedBox(height: 12),
                    ExpressBanner(
                      city: listing.city,
                      config: expressConfig,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _SellerInfo(sellerId: seller.id),
                  const SizedBox(height: 16),
                  Text('About this item',
                      style: Theme.of(context).textTheme.titleMedium,),
                  const SizedBox(height: 8),
                  Text(product.description,
                      style: Theme.of(context).textTheme.bodyMedium,),
                  if (product.specs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Specifications',
                        style: Theme.of(context).textTheme.titleMedium,),
                    const SizedBox(height: 8),
                    ...product.specs.entries.map(
                      (e) => Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(e.key,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                          color:
                                              AppColors.textSecondary,),),
                            ),
                            Text(e.value,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.w600,),),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 100),
                ],
              ),
              ),
            ),
          ),
        ],
      ),
      bottomSheet: _buildBottomBar(context, listing),
    );
  }

  /// Opens the full-screen pinch-to-zoom photo viewer.
  void _openGallery(BuildContext context, List<String> urls, int index) {
    TregaHaptics.tap();
    Navigator.of(context).push(
      PageTransition(
        type: PageTransitionType.fade,
        duration: const Duration(milliseconds: 250),
        reverseDuration: const Duration(milliseconds: 200),
        child: GalleryViewer(imageUrls: urls, initialIndex: index),
      ),
    );
  }

  /// Single state-driven action bar for the offer flow.
  ///
  /// One button, one meaning — the state comes from the caller's own offers
  /// on this listing plus the listing's reservation flag.
  Widget _buildBottomBar(BuildContext context, Listing listing) {
    final uid = ref.watch(currentUidProvider);
    final isSeller = uid != null && uid == listing.seller.id;

    Widget bar(Widget child) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SafeArea(top: false, child: child),
      );
    }

    // Sold listings: nothing to do.
    if (listing.status != ListingStatus.live) {
      return bar(
        const TregaButton(label: 'This item is sold', onPressed: null),
      );
    }

    // Seller: jump to the offers received on this listing.
    if (isSeller) {
      return bar(
        TregaButton(
          label: 'Manage Offers',
          onPressed: () => Navigator.of(context).pushNamed(
            BidsOffersScreen.routeName,
            arguments: const BidsOffersArgs(initialTab: 1),
          ),
        ),
      );
    }

    // Buyer: react to their own offer state on this listing.
    return StreamBuilder<List<Bid>>(
      stream: uid == null
          ? null
          : ref
              .read(firestoreServiceProvider)
              .watchMyBidsForListing(uid, listing.id),
      builder: (context, snap) {
        final bids = snap.data ?? [];
        Bid? open;
        Bid? accepted;
        for (final b in bids) {
          if (b.status == BidStatus.accepted) accepted ??= b;
          if (b.status == BidStatus.open) open ??= b;
        }

        // Winner: the only buyer who gets a Buy Now button, at the
        // accepted price — goes to checkout to enter the delivery address.
        if (accepted != null) {
          final amount = accepted.amount;
          return bar(
            TregaButton(
              label: 'Buy Now at ${formatINR(amount)}',
              onPressed: () => Navigator.of(context).pushNamed(
                CheckoutScreen.routeName,
                arguments: CheckoutArgs(bidId: accepted!.id),
              ),
            ),
          );
        }

        // Someone else's offer was accepted: sale in progress.
        if (listing.acceptedBidId != null) {
          return bar(
            const TregaButton(
              label: 'Offer accepted — sale in progress',
              onPressed: null,
            ),
          );
        }

        // Own offer still open: wait for the seller.
        if (open != null) {
          return bar(
            TregaButton(
              label: 'Offer of ${formatINR(open.amount)} sent — '
                  'awaiting the seller',
              secondary: true,
              onPressed: null,
            ),
          );
        }

        // No offer (or last one was rejected): the single buyer action.
        final rejected = bids.any((b) => b.status == BidStatus.rejected);
        return bar(
          TregaButton(
            label: rejected ? 'Offer again' : 'Make an Offer',
            onPressed: () => _makeOffer(context, listing),
          ),
        );
      },
    );
  }

  /// Shares the listing marketplace-style: title, price, condition and a
  /// link that opens the listing — in the app when Trega is installed
  /// (trega:// deep link), otherwise a web preview page.
  Future<void> _shareListing(Listing listing) async {
    final expressConfig = ref.read(expressConfigProvider).valueOrNull ??
        ExpressDeliveryConfig.defaults;
    final express = expressConfig.isCityEligible(listing.city);
    final city = listing.city.trim();
    final text = StringBuffer()
      ..writeln(
        '${listing.product.title} — ${formatINR(listing.price)} on Trega',
      )
      ..writeln('Condition: ${listing.product.condition.label}'
          '${city.isNotEmpty ? ' · $city' : ''}'
          '${express ? ' · Trega Express (next-day delivery)' : ''}')
      ..write('View it here: https://tregaxmuse.web.app/l/${listing.id}');
    try {
      await Share.share(text.toString(), subject: listing.product.title);
    } catch (_) {
      if (!mounted) return;
      await showTregaToast(
        context,
        'Could not open the share sheet. Please try again.',
        title: 'Share failed',
        kind: TregaToastKind.error,
      );
    }
  }
}

class _VerifiedPill extends StatelessWidget {
  const _VerifiedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsRegular.sealCheck, size: 14, color: AppColors.primary),
          SizedBox(width: 4),
          Text(
            'Verified seller',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Streams the seller's public profile (`users/{uid}`) for the card.
class _SellerInfo extends ConsumerWidget {
  final String sellerId;

  const _SellerInfo({required this.sellerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sellerAsync =
        ref.watch(firestoreServiceProvider).watchUser(sellerId);
    return StreamBuilder(
      stream: sellerAsync,
      builder: (context, snap) {
        final seller = snap.data;
        final name =
            (seller?.name.isNotEmpty ?? false) ? seller!.name : 'Seller';
        final verified = seller?.isVerifiedSeller ?? false;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primarySoft,
                  child: Icon(PhosphorIconsRegular.user, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(name,
                              style: Theme.of(context).textTheme.titleSmall,),
                          if (verified) ...[
                            const SizedBox(width: 4),
                            const Icon(PhosphorIconsRegular.sealCheck,
                                size: 16, color: AppColors.primary,),
                          ],
                        ],
                      ),
                      Text(
                        "★ ${seller?.rating.toStringAsFixed(1) ?? '–'} "
                        '· ${seller?.reviewsCount ?? 0} reviews',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // NOTE: no chat affordance — negotiation happens via bids/offers.

              ],
            ),
          ),
        );
      },
    );
  }
}

/// Amount-entry bottom sheet for bids/offers. Returns the entered amount.
class _OfferSheet extends StatefulWidget {
  final double price;

  const _OfferSheet({required this.price});

  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {
  final _amountController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Make an offer',
                style: Theme.of(context).textTheme.titleLarge,),
            const SizedBox(height: 4),
            Text(
              'Asking price: ${formatINR(widget.price)}. The seller can '
              'accept or reject — no chat needed.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Your offer',
                prefixText: '₹ ',
                hintText: '${(widget.price * 0.9).round()}',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 16),
            TregaButton(
              label: 'Send offer',
              onPressed: () {
                final amount =
                    double.tryParse(_amountController.text.trim());
                if (amount == null || amount <= 0) {
                  setState(() => _error = 'Enter a valid amount.');
                  return;
                }
                Navigator.of(context).pop(amount);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for reporting a listing: fixed reasons, no free text.
class _ReportSheet extends StatelessWidget {
  const _ReportSheet();

  static const _reasons = [
    ('Spam or misleading', PhosphorIconsRegular.flag),
    ('Fraud or scam', PhosphorIconsRegular.warning),
    ('Inappropriate content', PhosphorIconsRegular.prohibit),
    ('Wrong category', PhosphorIconsRegular.squaresFour),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Report listing', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              "What's wrong with this listing? Our team will review it.",
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final (label, icon) in _reasons)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon, color: AppColors.textSecondary),
                title: Text(label, style: textTheme.bodyLarge),
                onTap: () => Navigator.of(context).pop(label),
              ),
          ],
        ),
      ),
    );
  }
}
