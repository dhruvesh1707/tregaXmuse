import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/icons/phosphor_icons.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/screens/help_screen.dart';
import '../../profile/screens/kyc_screen.dart';
import '../../sell/screens/sell_flow_screen.dart';

/// Animated promo banner carousel for the home feed: full-bleed gradient
/// cards advertising Trega itself (selling, verification, secure payments).
///
/// Each card has slowly drifting translucent blobs behind the copy, the
/// carousel auto-advances every few seconds, and the dots animate.
/// Tapping a card opens the screen it promotes.
class PromoBannerCarousel extends StatefulWidget {
  const PromoBannerCarousel({super.key});

  @override
  State<PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoSlide {
  final IconData icon;
  final String title;
  final String subtitle;
  final String cta;
  final String routeName;
  final List<Color> gradient;

  const _PromoSlide({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.routeName,
    required this.gradient,
  });
}

const List<_PromoSlide> _slides = [
  _PromoSlide(
    icon: PhosphorIconsRegular.camera,
    title: 'Turn gear into cash',
    subtitle: 'List in under a minute — just your camera.',
    cta: 'Start selling',
    routeName: SellFlowScreen.routeName,
    gradient: [Color(0xFF9A441F), Color(0xFF5E2410)],
  ),
  _PromoSlide(
    icon: PhosphorIconsRegular.sealCheck,
    title: 'Aadhaar-verified community',
    subtitle: 'Every buyer and seller is ID-verified.',
    cta: 'Get verified',
    routeName: KycScreen.routeName,
    gradient: [Color(0xFFB7791F), Color(0xFF7A3A12)],
  ),
  _PromoSlide(
    icon: PhosphorIconsRegular.lightning,
    title: 'Secure payments',
    subtitle: 'UPI, cards & netbanking via Cashfree.',
    cta: 'How bidding works',
    routeName: HelpScreen.routeName,
    gradient: [Color(0xFF6E2E16), Color(0xFF381407)],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 156,
          child: PageView.builder(
            controller: _controller,
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) =>
                _PromoCard(slide: _slides[i]),
          ),
        ),
        const SizedBox(height: 10),
        AnimatedSmoothIndicator(
          activeIndex: _index,
          count: _slides.length,
          effect: WormEffect(
            dotWidth: 6,
            dotHeight: 6,
            spacing: 6,
            radius: 3,
            activeDotColor: AppColors.primary,
            dotColor: AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
      ],
    );
  }
}

/// One promo card: gradient, drifting translucent blobs, glass icon,
/// headline copy and a CTA row.
class _PromoCard extends StatefulWidget {
  final _PromoSlide slide;

  const _PromoCard({required this.slide});

  @override
  State<_PromoCard> createState() => _PromoCardState();
}

class _PromoCardState extends State<_PromoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slide;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: () =>
            Navigator.of(context).pushNamed(slide.routeName),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AnimatedBuilder(
            animation: _drift,
            builder: (context, child) {
              final t = _drift.value * 2 * math.pi;
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: slide.gradient,
                  ),
                ),
                child: Stack(
                  children: [
                    // Drifting translucent blobs.
                    Positioned(
                      left: -40 + 26 * math.sin(t),
                      top: -50 + 18 * math.cos(t * 0.8),
                      child: _blob(150),
                    ),
                    Positioned(
                      right: -30 + 20 * math.cos(t * 1.2),
                      bottom: -60 + 22 * math.sin(t * 0.9),
                      child: _blob(120),
                    ),
                    child!,
                  ],
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      slide.icon,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          slide.title,
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
                          style: TextStyle(
                            color: Colors.white
                                .withValues(alpha: 0.82),
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              slide.cta,
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              PhosphorIconsRegular.caretRight,
                              color: AppColors.accent,
                              size: 16,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _blob(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.10),
        ),
      );
}
