import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/icons/phosphor_icons.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_dialog.dart';
import '../../profile/screens/help_screen.dart';
import '../../profile/screens/kyc_screen.dart';
import '../../sell/screens/sell_flow_screen.dart';

/// Animated promo banner carousel for the home feed: solid deep-brown
/// cards advertising Trega itself (selling, verification, secure payments).
///
/// The carousel auto-advances every few seconds and the dots animate.
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

  /// Named route to open on tap. Null makes the card informational — tap
  /// shows [infoBody] in a dialog instead.
  final String? routeName;
  final String? infoBody;

  const _PromoSlide({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cta,
    this.routeName,
    this.infoBody,
  });
}

const List<_PromoSlide> _slides = [
  _PromoSlide(
    icon: PhosphorIconsRegular.truck,
    title: 'Trega Express is here',
    subtitle: 'Order today, get it tomorrow — in select cities.',
    cta: 'How it works',
    infoBody:
        'Look for the Express badge on listings. When you and the seller are in the same select city, order before 9 PM and the item arrives the next day.',
  ),
  _PromoSlide(
    icon: PhosphorIconsRegular.camera,
    title: 'Turn gear into cash',
    subtitle: 'List in under a minute — just your camera.',
    cta: 'Start selling',
    routeName: SellFlowScreen.routeName,
  ),
  _PromoSlide(
    icon: PhosphorIconsRegular.sealCheck,
    title: 'Aadhaar-verified community',
    subtitle: 'Every buyer and seller is ID-verified.',
    cta: 'Get verified',
    routeName: KycScreen.routeName,
  ),
  _PromoSlide(
    icon: PhosphorIconsRegular.lightning,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 156,
          child: PageView.builder(
            controller: _controller,
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => _PromoCard(slide: _slides[i]),
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

/// One promo card: solid deep-brown surface, glass icon tile,
/// headline copy and a CTA row.
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
            color: AppColors.primaryDeep,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                          color: Colors.white.withValues(alpha: 0.82),
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
