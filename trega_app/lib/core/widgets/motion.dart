import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Trega's motion language: warm, physical, confident.
///
/// - Entrances: fade + slight rise, easeOutCubic, <= 450ms, staggered on grids.
/// - Press feedback: scale to 0.96 + light haptic on release.
/// - Loading: shimmer skeletons on content surfaces, never bare spinners.
/// - Route transitions: fade + gentle rise (see `_TregaPageRoute` in app.dart).
/// - Celebrations (like, bid placed): springy scale pop + haptic.
///
/// Durations are deliberately short — motion should feel snappy on
/// low-end devices, never decorative-slow.

/// Fades + rises its child in once, the first time it is built.
///
/// Give grid items an index-based [delay] for a staggered entrance.
/// Replays only if the element itself is rebuilt from scratch (e.g.
/// navigating back to the feed), which is the desired behaviour.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 450),
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  late final Animation<Offset> _offset =
      Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

/// Skeleton shimmer box for loading states.
///
/// One looping gradient sweep; cheap enough to use several per screen.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadiusGeometry borderRadius;

  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                AppColors.divider,
                AppColors.primarySoft,
                AppColors.divider,
              ],
              stops: [
                (t - 0.35).clamp(0.0, 1.0),
                t.clamp(0.0, 1.0),
                (t + 0.35).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton matching [ProductCard]'s layout, for feed/search grids.
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ShimmerBox(borderRadius: BorderRadius.zero),
          ),
          Padding(
            padding: EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(height: 14),
                SizedBox(height: 8),
                ShimmerBox(width: 90, height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for list rows (bids, offers, orders).
class RowSkeleton extends StatelessWidget {
  const RowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBox(height: 16),
            SizedBox(height: 10),
            ShimmerBox(width: 140, height: 12),
          ],
        ),
      ),
    );
  }
}

/// Scales its child to 0.96 while pressed, with a light haptic on release.
///
/// Only handles press phases (no `onTap`), so wrapped buttons keep their
/// own tap handling untouched.
class PressScale extends StatefulWidget {
  final Widget child;
  final double pressedScale;

  const PressScale({
    super.key,
    required this.child,
    this.pressedScale = 0.96,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    if (!value) TregaHaptics.tap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Heart button with a springy pop when it turns liked.
class LikeButton extends StatefulWidget {
  final bool isLiked;
  final VoidCallback? onTap;
  final Color? unlikedColor;

  const LikeButton({
    super.key,
    required this.isLiked,
    this.onTap,
    this.unlikedColor,
  });

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.4, end: 0.88), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 0.88, end: 1.0), weight: 35),
  ]).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOut),
  );

  @override
  void didUpdateWidget(LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLiked && !oldWidget.isLiked) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: IconButton(
        icon: Icon(
          widget.isLiked ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
          color: widget.isLiked ? AppColors.error : widget.unlikedColor,
        ),
        onPressed: () {
          TregaHaptics.tap();
          widget.onTap?.call();
        },
      ),
    );
  }
}

/// Semantic haptics — a single place to tune or disable.
abstract final class TregaHaptics {
  static void tap() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  static void success() {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }
}


/// Premium staggered entrance: fade + gentle rise, driven by flutter_animate.
///
/// Pass the item [index] inside lists/grids for the signature staggered
/// cascade. The per-item [baseDelay] step is small (55ms) so the first
/// items appear almost immediately — lists feel alive, never slow.
///
/// This is the standard entrance for feed cards, list rows and grid tiles.
/// [FadeSlideIn] is kept for one-off entrances that predate this helper.
class Entrance extends StatelessWidget {
  final Widget child;
  final int index;
  final Duration baseDelay;
  final Duration duration;

  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.baseDelay = const Duration(milliseconds: 55),
    this.duration = const Duration(milliseconds: 450),
  });

  @override
  Widget build(BuildContext context) {
    return child
        .animate(delay: baseDelay * index)
        .fadeIn(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        )
        .slideY(
          begin: 0.14,
          end: 0,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
  }
}

/// Animated draw-on success check: the circle pops in with a spring, then
/// the tick draws itself. Fires a success haptic on completion.
///
/// A lightweight, dependency-free moment for order-placed, payment-success,
/// bid-accepted and KYC-verified celebrations — no Lottie asset needed.
class SuccessCheck extends StatefulWidget {
  final double size;
  final Color color;
  final Color checkColor;

  const SuccessCheck({
    super.key,
    this.size = 96,
    this.color = AppColors.success,
    this.checkColor = Colors.white,
  });

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck> {
  bool _hapticFired = false;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 750),
      curve: Curves.easeOutCubic,
      onEnd: () {
        if (!_hapticFired) {
          _hapticFired = true;
          TregaHaptics.success();
        }
      },
      builder: (context, t, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _SuccessCheckPainter(
          progress: t,
          color: widget.color,
          checkColor: widget.checkColor,
        ),
      ),
    );
  }
}

class _SuccessCheckPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final Color checkColor;

  _SuccessCheckPainter({
    required this.progress,
    required this.color,
    required this.checkColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    // Circle pops in over the first 40% with an overshoot spring.
    final circleT = (progress / 0.4).clamp(0.0, 1.0);
    if (circleT > 0) {
      final r = radius * Curves.easeOutBack.transform(circleT);
      canvas.drawCircle(center, r, Paint()..color = color);
    }

    // Tick draws itself over the remaining 60%.
    final checkT = ((progress - 0.35) / 0.65).clamp(0.0, 1.0);
    if (checkT > 0) {
      final path = Path()
        ..moveTo(size.width * 0.30, size.height * 0.545)
        ..lineTo(size.width * 0.45, size.height * 0.685)
        ..lineTo(size.width * 0.705, size.height * 0.335);
      final metric = path.computeMetrics().first;
      final drawn =
          metric.extractPath(0, metric.length * checkT);
      canvas.drawPath(
        drawn,
        Paint()
          ..color = checkColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.095
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SuccessCheckPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.checkColor != checkColor;
}
