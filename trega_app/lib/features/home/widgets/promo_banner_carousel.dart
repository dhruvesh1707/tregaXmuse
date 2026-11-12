import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/icons/phosphor_icons.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_dialog.dart';
import '../../profile/screens/help_screen.dart';
import '../../profile/screens/kyc_screen.dart';
import '../../sell/screens/sell_flow_screen.dart';

/// Promo banner carousel for the home feed: espresso gradient cards
/// with white text, an amber pill CTA, product photo art on the right,
/// and the dots inside the card, bottom-left. Radius 24.
///
/// The carousel auto-advances every few seconds and the dots animate.
/// Tapping a card opens the screen it promotes, or explains the promo
/// in a dialog for informational slides.
class PromoBannerCarousel extends StatefulWidget {
  const PromoBannerCarousel({super.key});

  @override
  State<PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoSlide {
  final String title;
  final String subtitle;
  final String cta;

  /// Named route to open on tap. Null makes the card informational, tap
  /// shows [infoBody] in a dialog instead.
  final String? routeName;
  final String? infoBody;

  const _PromoSlide({
    required this.title,
    required this.subtitle,
    required this.cta,
    this.routeName,
    this.infoBody,
  });
}

const List<_PromoSlide> _slides = [
  _PromoSlide(
    title: 'Trega Express is here',
    subtitle: 'Faster delivery in select cities.',
    cta: 'How it works',
    infoBody:
        'Look for the Express badge on listings. When you and the seller are in the same select city, order before 9 PM and express delivery is available in select cities.',
  ),
  _PromoSlide(
    title: 'Turn gear into cash',
    subtitle: 'List in under a minute, just your camera.',
    cta: 'Start selling',
    routeName: SellFlowScreen.routeName,
  ),
  _PromoSlide(
    title: 'Aadhaar-verified community',
    subtitle: 'Every seller is ID-verified.',
    cta: 'Get verified',
    routeName: KycScreen.routeName,
  ),
  _PromoSlide(
    title: 'Secure payments',
    subtitle: 'UPI, cards & netbanking via Cashfree.',
    cta: 'How bidding works',
    routeName: HelpScreen.routeName,
  ),
];

class _PromoBannerCarouselState extends State<PromoBannerCarousel> {
  late final PageController _controller;
  late final Timer _autoPlay;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.92);
    _autoPlay = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % _slides.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoPlay.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The dots live inside the card, bottom-left, like the reference
    // frames, so the carousel reads as one unit. The active card
    // always starts at the left edge of the viewport, so the overlay
    // sits inside it on every page.
    return SizedBox(
      height: 168,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => _PromoCard(slide: _slides[i]),
          ),
          Positioned(
            left: 30,
            bottom: 12,
            child: AnimatedSmoothIndicator(
              activeIndex: _index,
              count: _slides.length,
              effect: WormEffect(
                dotWidth: 6,
                dotHeight: 6,
                spacing: 6,
                radius: 3,
                activeDotColor: AppColors.accent,
                dotColor: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One promo card: an espresso gradient card with the headline copy
/// and amber pill CTA on the left and product photo art on the right.
/// Tapping navigates or shows the info dialog (see [_onSlideTap]).
/// The bottom padding clears the dots overlay that sits inside the
/// card, bottom-left.
class _PromoCard extends StatelessWidget {
  final _PromoSlide slide;

  const _PromoCard({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: () => _onSlideTap(context, slide),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppGradients.headerEspresso,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
            child: Row(
              children: [
                Expanded(
                  child: _PromoCopy(slide: slide),
                ),
                const SizedBox(width: 12),
                const _PromoArt(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tapping a slide either navigates (routeName set) or explains the
  /// promo in a dialog (informational slide, e.g. Trega Express).
  void _onSlideTap(BuildContext context, _PromoSlide slide) {
    final route = slide.routeName;
    if (route != null) {
      Navigator.of(context).pushNamed(route);
      return;
    }
    final info = slide.infoBody;
    if (info == null) return;
    showGlassDialog(
      context: context,
      builder: (_) => GlassDialog(
        title: Text(slide.title),
        content: Text(info),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

/// Headline copy and amber pill CTA for one promo card. Titles and
/// subtitles clamp to two lines so a long headline can never push the
/// CTA into the dots row.
class _PromoCopy extends StatelessWidget {
  final _PromoSlide slide;

  const _PromoCopy({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          slide.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          slide.subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.82),
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                slide.cta,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                PhosphorIconsRegular.caretRight,
                color: AppColors.textPrimary,
                size: 16,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Product photo art for the right side of a promo card: two
/// overlapping category photos, the same brand motif on every slide,
/// echoing the product imagery in the reference frames. A photo that
/// fails to load falls back to a plain tile, never an error box.
class _PromoArt extends StatelessWidget {
  const _PromoArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 96,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/categories/gaming.jpg',
                width: 58,
                height: 58,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 58,
                  height: 58,
                  color: AppColors.tileBackground,
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.espresso, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.asset(
                  'assets/categories/mobile.jpg',
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 52,
                    height: 52,
                    color: AppColors.tileBackground,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
