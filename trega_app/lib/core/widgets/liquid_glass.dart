import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';
import '../theme/app_shadows.dart';

/// iOS-style "liquid glass" surface.
///
/// A frosted, refractive-looking container built from pure Flutter:
/// a real [BackdropFilter] blur over whatever is behind it, a diagonal
/// glass-tint gradient, a gradient hairline border (bright where the
/// light hits, dissolving away from it) and a specular top-light.
///
/// The gradient border uses the padding trick — an outer container
/// painted with [AppGradients.glassBorder], inset by [borderWidth] —
/// because [Border] itself cannot carry a gradient.
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

    Widget content = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: innerRadius,
          gradient: tint ?? AppGradients.glassTint,
        ),
        child: child,
      ),
    );

    // Specular top-light: the highlight a real light source leaves on
    // curved glass. Painted above the tint, never intercepts touches.
    content = Stack(
      children: [
        content,
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: innerRadius,
                gradient: AppGradients.sheen,
              ),
            ),
          ),
        ),
      ],
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: innerRadius,
          onTap: onTap,
          child: content,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: outerRadius,
        gradient: borderGradient ?? AppGradients.glassBorder,
        boxShadow: shadows ?? AppShadows.glass,
      ),
      padding: EdgeInsets.all(borderWidth),
      child: ClipRRect(
        borderRadius: innerRadius,
        child: content,
      ),
    );
  }
}

/// Frosted card with comfortable default padding.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: borderRadius,
      padding: padding,
      onTap: onTap,
      child: child,
    );
  }
}

/// Small frosted pill — badges, counts, overlay labels.
class GlassChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? foreground;
  final double? fontSize;

  const GlassChip({
    super.key,
    required this.label,
    this.icon,
    this.foreground,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? Colors.white;
    return LiquidGlass(
      borderRadius: 999,
      blur: 16,
      shadows: AppShadows.soft,
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize ?? 11.5,
              fontWeight: FontWeight.w700,
              color: fg,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Frosted circular icon button — overlays on photos, headers, maps.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final double iconSize;
  final String? tooltip;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.iconColor,
    this.iconSize = 20,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: 999,
      blur: 16,
      shadows: AppShadows.soft,
      padding: const EdgeInsets.all(10),
      onTap: onPressed,
      child: Tooltip(
        message: tooltip ?? '',
        child: Icon(
          icon,
          size: iconSize,
          color: iconColor ?? Colors.white,
        ),
      ),
    );
  }
}
