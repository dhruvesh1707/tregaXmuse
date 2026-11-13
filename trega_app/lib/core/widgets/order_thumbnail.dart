import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';

import '../theme/app_colors.dart';

/// Small rounded thumbnail for order surfaces (order list cards, order
/// tracking), 48px like a profile pic. Decoded small; no disk-cache cap
/// on purpose, the disk file is shared with the listing detail gallery
/// by URL.
class OrderThumbnail extends StatelessWidget {
  final String? photoUrl;

  const OrderThumbnail({super.key, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    if (photoUrl == null) return _fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: photoUrl!,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        memCacheWidth: 200,
        memCacheHeight: 200,
        placeholder: (context, url) => _fallback(),
        errorWidget: (context, url, error) => _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.tileBackground,
      ),
      child: const Icon(
        PhosphorIconsRegular.image,
        color: AppColors.primary,
      ),
    );
  }
}
