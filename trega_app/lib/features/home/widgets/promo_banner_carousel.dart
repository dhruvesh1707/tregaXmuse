import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/icons/phosphor_icons.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_dialog.dart';
import '../../profile/screens/help_screen.dart';
import '../../profile/screens/kyc_screen.dart';
import '../../sell/screens/sell_flow_screen.dart';

/// Motion promo banner carousel for the home feed: slow-shifting
/// brand-palette gradients (deep browns → espresso) with soft drifting
/// amber/brown glow blobs behind the content, plus a single gentle sheen
/// sweep across the headline each time a slide becomes active.
///
/// The carousel auto-advances every few seconds and the dots animate.
/// Tapping a card opens the screen it promotes.
///
/// Motion notes (perf): one looping [AnimationController] per card drives
/// the gradient + blobs through [AnimatedBuilder] (no per-frame setState);
/// the blobs are soft [RadialGradient] circles (no BackdropFilter in the
/// animated layer). Controllers are disposed with the card state.
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
            itemBuilder: (context, i) =>
                _PromoCard(slide: _slides[i], active: i == _index),
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

/// One promo card: animated brand gradient background with drifting glow
/// blobs, glass icon tile, headline copy (with a one-pass sheen when the
/// slide becomes active) and a CTA row.
class _PromoCard extends StatefulWidget {
  final _PromoSlide slide;

  /// True when this card is the currently visible slide.
  final bool active;

  const _PromoCard({required this.slide, required this.active});

  @override
  State<_PromoCard> createState() => _PromoCardState();
}

class _PromoCardState extends State<_PromoCard> with TickerProviderStateMixin {
  /// Slow ping-pong loop driving the background gradient and blob drift.
  late final AnimationController _drift;

  /// One-pass headline sheen; replays each time the slide becomes active.
  late final AnimationController _sheen;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _sheen = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.active) _sheen.forward();
  }

  @override
  void didUpdateWidget(covariant _PromoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _sheen.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: () => _onSlideTap(context, widget.slide),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Animated background, isolated behind a repaint boundary so
              // the static content below is never repainted on animation ticks.
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _drift,
                    builder: (context, _) {
                      final t = _drift.value;
                      final angle = t * math.pi * 2;
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin:
                                Alignment(-0.9 + 0.35 * math.sin(angle), -1.0),
                            end: Alignment(
                                0.9 + 0.35 * math.sin(angle + 1.2), 1.0),
                            colors: [
                              Color.lerp(
                                  AppColors.primaryDeep, AppColors.espresso, t)!,
                              Color.lerp(
                                  AppColors.primaryDark, AppColors.primary, t)!,
                            ],
                          ),
                        ),
                        child: Stack(
                          children: [
                            // Warm amber glow drifting across the top-right.
                            Positioned(
                              left: 150 + 34 * math.sin(angle),
                              top: -56 + 22 * math.cos(angle * 0.8),
                              child: const _Blob(
                                size: 190,
                                color: AppColors.accentDeep,
                                opacity: 0.30,
                              ),
                            ),
                            // Soft brown glow drifting along the bottom-left.
                            Positioned(
                              left: -64 + 26 * math.cos(angle * 0.7),
                              top: 74 + 20 * math.sin(angle * 0.9),
                              child: const _Blob(
                                size: 170,
                                color: AppColors.primaryLight,
                                opacity: 0.28,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
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
                        widget.slide.icon,
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
                          _SheenTitle(
                            text: widget.slide.title,
                            sheen: _sheen,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.slide.subtitle,
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
                                widget.slide.cta,
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
            ],
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

/// Soft glowing circle: a radial gradient fading to transparent, which
/// reads as a blurred blob with no BackdropFilter in the animated layer.
class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const _Blob({
    required this.size,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Headline text with a single gentle sheen sweep: a narrow warm band
/// glides across the white text once per [_PromoCardState._sheen] run.
/// When the animation is idle the band sits off-text, so the title renders
/// plain white — no strobing.
class _SheenTitle extends StatelessWidget {
  final String text;

  /// The card's one-shot sheen controller; the sweep replays when it runs.
  final Animation<double> sheen;

  const _SheenTitle({required this.text, required this.sheen});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sheen,
      builder: (context, _) {
        final s = sheen.value * 1.6 - 0.3;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: const [
              Colors.white,
              Colors.white,
              AppColors.accentSoft,
              Colors.white,
              Colors.white,
            ],
            stops: [
              0.0,
              s.clamp(0.0, 1.0),
              (s + 0.14).clamp(0.0, 1.0),
              (s + 0.28).clamp(0.0, 1.0),
              1.0,
            ],
          ).createShader(bounds),
          child: _plainTitle(),
        );
      },
    );
  }

  Widget _plainTitle() => Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      );
}
