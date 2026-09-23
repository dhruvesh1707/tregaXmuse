import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/listing.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'condition_badge.dart';

/// Card used in home feed, search results, category and wishlist grids.
class ProductCard extends StatelessWidget {
  final Listing listing;
  final VoidCallback? onTap;
  final VoidCallback? onLikeToggle;

  const ProductCard({
    super.key,
    required this.listing,
    this.onTap,
    this.onLikeToggle,
  });

  @override
  Widget build(BuildContext context) {
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
                    CachedNetworkImage(
                      imageUrl: product.imageUrls.first,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: AppColors.primarySoft,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.primarySoft,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  else
                    Container(
                      color: AppColors.primarySoft,
                      child: const Icon(
                        Icons.image_outlined,
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
                    child: IconButton(
                      icon: Icon(
                        listing.isLiked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: listing.isLiked
                            ? AppColors.error
                            : AppColors.textPrimary,
                      ),
                      onPressed: onLikeToggle ??
                          () {
                            // TODO: wire wishlist toggle -> POST /wishlist/:id
                          },
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
