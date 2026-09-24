import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase/firebase_providers.dart';
import '../models/listing.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'condition_badge.dart';
import 'motion.dart';

/// Card used in home feed, search results, category and wishlist grids.
///
/// The product photo is a [Hero] into the listing detail gallery
/// (tag `listing-photo-<id>`), and the heart toggles the wishlist via
/// Firestore with a springy pop + haptic.
class ProductCard extends ConsumerWidget {
  final Listing listing;
  final VoidCallback? onTap;
  final VoidCallback? onLikeToggle;

  const ProductCard({
    super.key,
    required this.listing,
    this.onTap,
    this.onLikeToggle,
  });

  Future<void> _toggleLike(WidgetRef ref) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    await ref
        .read(firestoreServiceProvider)
        .toggleLike(listing.id, uid, listing.isLiked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = listing.product;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (product.imageUrls.isNotEmpty)
                    Hero(
                      tag: 'listing-photo-${listing.id}',
                      child: CachedNetworkImage(
                        imageUrl: product.imageUrls.first,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const ShimmerBox(
                          borderRadius: BorderRadius.zero,
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: AppColors.primarySoft,
                          child: const Icon(
                            PhosphorIconsRegular.prohibit,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: AppColors.primarySoft,
                      child: const Icon(
                        PhosphorIconsRegular.image,
                        color: AppColors.textSecondary,
                        size: 40,
                      ),
                    ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: ConditionBadge(condition: product.condition),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: LikeButton(
                      isLiked: listing.isLiked,
                      unlikedColor: AppColors.textPrimary,
                      onTap: onLikeToggle ?? () => _toggleLike(ref),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatINR(listing.price),
                    style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeAgo(listing.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
