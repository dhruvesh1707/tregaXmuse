import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/icons/phosphor_icons.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_dialog.dart';
import '../../profile/screens/help_screen.dart';
import '../../profile/screens/kyc_screen.dart';
import '../../sell/screens/sell_flow_screen.dart';

/// Promo banner carousel for the home feed: warm espresso cards with
/// white text, an amber pill CTA, a dedicated photo per slide matched
/// to the card's message, and the dots inside the card, bottom-left.
/// Radius 24.
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

  /// The dedicated photo for this card, generated for the card's
  /// message. Every slide has its own image.
  final String art;

  /// Named route to open on tap. Null makes the card informational, tap
  /// shows [infoBody] in a dialog instead.
  final String? routeName;
  final String? infoBody;

  const _PromoSlide({
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.art,
    this.routeName,
    this.infoBody,
  });
}

const List<_PromoSlide> _slides = [
  _PromoSlide(
    title: 'Trega Express is here',
    subtitle: 'Faster delivery in select cities.',
    cta: 'How it works',
    art: 'assets/promo/express.jpg',
    infoBody:
        'Look for the Express badge on listings. When you and the seller are in the same select city, order before 9 PM and express delivery is available in select cities.',
  ),
  _PromoSlide(
    title: 'Turn gear into cash',
    subtitle: 'List in under a minute, just your camera.',
    cta: 'Start selling',
    art: 'assets/promo/sell.jpg',
    routeName: SellFlowScreen.routeName,
  ),
  _PromoSlide(
    title: 'Aadhaar-verified community',
    subtitle: 'Every seller is ID-verified.',
    cta: 'Get verified',
    art: 'assets/promo/verified.jpg',
    routeName: KycScreen.routeName,
  ),
  _PromoSlide(
    title: 'Secure payments',
    subtitle: 'UPI, cards & netbanking via Cashfree.',
    cta: 'How bidding works',
    art: 'assets/promo/payments.jpg',
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

/// One promo card: a warm espresso card with the headline copy and
/// amber pill CTA on the left, a soft glow at the top-right, a hairline
/// edge, and the slide's dedicated photo on the right.
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
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.espressoLight, AppColors.espresso],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.9, -0.4),
                        radius: 1.0,
                        colors: [
                          AppColors.primaryLight.withValues(alpha: 0.35),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
                  child: Row(
                    children: [
                      Expanded(
                        child: _PromoCopy(slide: slide),
                      ),
                      const SizedBox(width: 12),
                      _PromoArt(asset: slide.art),
                    ],
                  ),
                ),
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

/// The slide's dedicated photo on the right side of a promo card:
/// one square image, generated for the card's message, lifted with a
/// soft shadow. A photo that fails to load falls back to a plain tile,
/// never an error box.
class _PromoArt extends StatelessWidget {
  final String asset;

  const _PromoArt({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset(
          asset,
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 96,
            height: 96,
            color: AppColors.tileBackground,
          ),
        ),
      ),
    );
  }
}
