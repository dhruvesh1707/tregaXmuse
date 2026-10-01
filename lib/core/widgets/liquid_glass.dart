import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';

/// The canonical light-glass surface for the minimal Trega theme.
///
/// Exactly one recipe, applied everywhere:
/// - fill: white at 0.70 alpha over a real [BackdropFilter] blur
/// - hairline border: white at 0.60 alpha, width 1
///   (or [AppColors.divider] on solid, non-frosted contexts)
/// - exactly one shadow: [AppShadows.glass]
///   (offset (0, 6), blur 18, warm tint 0xFF3A2417 at 10% alpha)
///
/// Blur guidance: 18 for cards / sheets / bars, 14 for chips and small
/// surfaces, 24 for dialogs.
///
/// The constructor keeps its historic parameters so existing call sites
/// keep compiling: pass [tint] / [borderGradient] only to override the
/// default fill / hairline border.
///
/// Keep blur radii modest and glass surfaces few: every [BackdropFilter]
/// repaints the content behind it.
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final Gradient? tint;
  final Gradient? borderGradient;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTap;
  final double borderWidth;

  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.blur = 20,
    this.padding,
    this.tint,
    this.borderGradient,
    this.shadows,
    this.onTap,
    this.borderWidth = 1.2,
  });

  @override
  Widget build(BuildContext context) {
    final outerRadius = BorderRadius.circular(borderRadius);
    final innerRadius = BorderRadius.circular(
      math.max(0.0, borderRadius - borderWidth),
    );
    final hasGradientBorder = borderGradient != null;

    Widget inner = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: hasGradientBorder ? innerRadius : outerRadius,
          // Default fill: flat translucent white. A custom [tint]
          // replaces it outright.
          color: tint == null
              ? Colors.white.withValues(alpha: 0.7)
              : null,
          gradient: tint,
          border: hasGradientBorder
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 1,
                ),
        ),
        child: child,
      ),
    );

    if (onTap != null) {
      inner = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
              hasGradientBorder ? innerRadius : outerRadius,
          onTap: onTap,
          child: inner,
        ),
      );
    }

    // The shadow lives on the outer wrapper so the inner ClipRRect never
    // clips it. A custom [borderGradient] keeps the legacy treatment:
    // the gradient paints an outer shell and the frosted fill insets by
    // [borderWidth].
    return Container(
      decoration: BoxDecoration(
        borderRadius: outerRadius,
        gradient: borderGradient,
        boxShadow: shadows ?? AppShadows.glass,
      ),
      padding:
          hasGradientBorder ? EdgeInsets.all(borderWidth) : EdgeInsets.zero,
      child: ClipRRect(
        borderRadius:
            hasGradientBorder ? innerRadius : outerRadius,
        child: inner,
      ),
    );
  }
}

/// Frosted card with comfortable default padding.
///
/// The standard content surface: blur 18, radius 18, the one shadow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 18.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: borderRadius,
      blur: 18,
      padding: padding,
      onTap: onTap,
      child: child,
    );
  }
}

/// Small frosted pill — filter chips, badges, counts, overlay labels.
///
/// Unselected: light glass (white 0.70 + blur 14 + hairline border).
/// Selected: solid [AppColors.primary]; the fill animates via an
/// [AnimatedContainer]. Label color is the caller's job — white when
/// selected, [AppColors.textPrimary] when not.
///
/// NOTE: the inner container sets `alignment: Alignment.center` — a
/// horizontal ListView hands chips a tight height, and without it labels
/// sit high in the pill (real user-reported bug, do not regress).
class GlassChip extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsetsGeometry padding;

  const GlassChip({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.padding =
        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(999));
    return Container(
      decoration: const BoxDecoration(
        borderRadius: radius,
        boxShadow: AppShadows.glass,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: padding,
                // CRITICAL: centers the label vertically when a
                // horizontal ListView hands the chip a tight height.
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: selected
                      ? AppColors.primary
                      : Colors.white.withValues(alpha: 0.7),
                  border: Border.all(
                    color: selected
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted circular icon button — overlays on photos, headers, maps.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color iconColor;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.iconColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return GlassChip(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: Icon(icon, size: 20, color: iconColor),
    );
  }
}
