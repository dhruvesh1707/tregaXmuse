import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Full-screen photo viewer, WhatsApp-style: tap a profile picture (or any
/// image) to see it large on a black background with pinch-to-zoom.
/// Dismiss with the close button or the system back button/gesture.
Future<void> showFullScreenPhoto(BuildContext context, String imageUrl) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Pinch-to-zoom image, centered.
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                    child:
                        CircularProgressIndicator(color: Colors.white70),
                  ),
                  errorWidget: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Close button, top-left.
          Positioned(
            top: MediaQuery.of(dialogContext).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}
