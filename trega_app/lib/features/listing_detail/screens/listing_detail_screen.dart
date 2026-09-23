import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/listing.dart';
import '../../../core/payments/cashfree_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/condition_badge.dart';
import '../../../core/widgets/trega_button.dart';
import '../../home/providers/listing_providers.dart';
import '../../orders/screens/orders_screen.dart';

/// Full listing page: media gallery (photos + video), condition badge,
/// verified seller card, specs, and Buy / Make Offer / Place Bid actions.
///
/// Streams the listing document from Firestore.
///
/// TODO(detail): implement video playback with video_player when
/// product.videoUrl is present.
class ListingDetailScreen extends ConsumerStatefulWidget {
  static const String routeName = '/listing';

  final String? listingId;

  const ListingDetailScreen({super.key, this.listingId});

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

  /// Places a bid/offer via the server-side `placeBid` callable.
  Future<void> _placeBid(BuildContext context, Listing listing) async {
    final amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BidSheet(price: listing.price),
    );
    if (amount == null || amount <= 0) return;
    try {
      await ref.read(functionsServiceProvider).placeBid(
            listingId: listing.id,
            amount: amount,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your offer was sent to the seller.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not place the bid. Try again.')),
      );
    }
  }

  /// Starts checkout: creates a Cashfree order server-side, then hands the
  /// `paymentSessionId` to the Cashfree SDK drop checkout.
  ///
  /// The SDK callback only drives UI — payment truth comes from the
  /// `cashfreeWebhook` function flipping the order's `paymentStatus`, which
  /// the Orders screen streams.
  Future<void> _buyNow(BuildContext context, Listing listing) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to buy.')),
      );
      return;
    }
    try {
      final user = await ref.read(firestoreServiceProvider).getUser(uid);
      final result = await ref.read(functionsServiceProvider).createCashfreeOrder(
            listingId: listing.id,
            customerPhone: user?.phone ?? '',
          );
      if (!context.mounted) return;
      final sessionId = result['paymentSessionId'] as String?;
      final orderId = result['orderId'] as String?;
      if (sessionId == null || orderId == null) {
        throw StateError('no session');
      }
      // Merchant order id sent to Cashfree is `trega_<orderId>` (see
      // trega_functions/src/payments.ts); prefer the backend-echoed value
      // so the app keeps working if that format ever changes.
      final cfOrderId =
          (result['cfOrderRef'] as String?) ?? 'trega_$orderId';
      CashfreeService().pay(
        cfOrderId: cfOrderId,
        paymentSessionId: sessionId,
        onVerified: (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment done! Confirming your order...'),
            ),
          );
          Navigator.of(context).pushReplacementNamed(OrdersScreen.routeName);
        },
        onError: (message, _) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment failed: $message')),
          );
        },
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start checkout. Try again.')),
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
    return listingAsync.when(
      data: (listing) => listing == null
          ? Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('Listing not found.')),
            )
          : _buildContent(context, listing),
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text('Couldn\'t load this listing. Check your connection.'),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Listing listing) {
    final product = listing.product;
    final seller = listing.seller;

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
                    itemBuilder: (context, i) => CachedNetworkImage(
                      imageUrl: product.imageUrls[i],
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: AppColors.primarySoft,
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.primarySoft,
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
                  ),
                  if (product.videoUrl != null)
                    // TODO: replace with inline video_player preview.
                    const Positioned(
                      bottom: 16,
                      right: 16,
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.play_arrow, color: Colors.white),
                      ),
                    ),
                  if (product.imageUrls.length > 1)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          product.imageUrls.length,
                          (i) => Container(
                            margin:
                                const EdgeInsets.symmetric(horizontal: 3),
                            width: _page == i ? 20 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _page == i
                                  ? Colors.white
                                  : Colors.white54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  listing.isLiked ? Icons.favorite : Icons.favorite_border,
                  color: listing.isLiked ? AppColors.error : null,
                ),
                onPressed: () => _toggleLike(listing),
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () {
                  // TODO: share trega://listing/<id> deep link.
                },
              ),
            ],
          ),
          SliverToBoxAdapter(
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
                      style: Theme.of(context).textTheme.headlineSmall),
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
                  const SizedBox(height: 16),
                  _SellerInfo(sellerId: seller.id),
                  const SizedBox(height: 16),
                  Text('About this item',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(product.description,
                      style: Theme.of(context).textTheme.bodyMedium),
                  if (product.specs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Specifications',
                        style: Theme.of(context).textTheme.titleMedium),
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
                                              AppColors.textSecondary)),
                            ),
                            Text(e.value,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.w600)),
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
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: TregaButton(
                  label: 'Place Bid',
                  secondary: true,
                  onPressed: () => _placeBid(context, listing),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TregaButton(
                  label: 'Make Offer',
                  secondary: true,
                  onPressed: () => _placeBid(context, listing),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TregaButton(
                  label: 'Buy Now',
                  onPressed: () => _buyNow(context, listing),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
          Icon(Icons.verified, size: 14, color: AppColors.primary),
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
                  child: Icon(Icons.person, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(name,
                              style: Theme.of(context).textTheme.titleSmall),
                          if (verified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified,
                                size: 16, color: AppColors.primary),
                          ],
                        ],
                      ),
                      Text(
                        '★ ${seller?.rating.toStringAsFixed(1) ?? '–'} '
                        '· ${seller?.reviewsCount ?? 0} reviews',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // NOTE: no chat affordance — negotiation happens via bids/offers.
                TextButton(
                  onPressed: () {
                    // TODO: open seller's other listings.
                  },
                  child: const Text('View shop'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Amount-entry bottom sheet for bids/offers. Returns the entered amount.
class _BidSheet extends StatefulWidget {
  final double price;

  const _BidSheet({required this.price});

  @override
  State<_BidSheet> createState() => _BidSheetState();
}

class _BidSheetState extends State<_BidSheet> {
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
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Asking price: ${formatINR(widget.price)}. The seller can '
              'accept, reject or counter — no chat needed.',
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
