import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

/// Full-screen photo viewer for listing galleries: pinch-to-zoom,
/// swipe between photos, animated page indicator.
///
/// Opened by tapping any photo on the listing detail screen with a soft
/// fade — no Hero involved (the feed→detail Hero already owns the shared
/// photo tag while both routes are alive).
class GalleryViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const GalleryViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_index + 1} / ${widget.imageUrls.length}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            itemCount: widget.imageUrls.length,
            builder: (context, i) => PhotoViewGalleryPageOptions(
              // Reuses the feed's image cache — no re-download.
              imageProvider:
                  CachedNetworkImageProvider(widget.imageUrls[i]),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3.0,
              initialScale: PhotoViewComputedScale.contained,
            ),
            pageController: _controller,
            onPageChanged: (i) => setState(() => _index = i),
            backgroundDecoration:
                const BoxDecoration(color: Colors.black),
          ),
          Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedSmoothIndicator(
                activeIndex: _index,
                count: widget.imageUrls.length,
                effect: const ExpandingDotsEffect(
                  dotWidth: 6,
                  dotHeight: 6,
                  spacing: 6,
                  expansionFactor: 2.4,
                  activeDotColor: Colors.white,
                  dotColor: Colors.white38,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
