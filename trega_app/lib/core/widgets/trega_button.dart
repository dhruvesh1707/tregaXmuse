import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';
import '../theme/app_shadows.dart';
import 'liquid_glass.dart';
import 'motion.dart';

/// Primary / secondary button with Trega styling — soft 3D gradient.
///
/// Primary buttons render a warm brown gradient (light falling from the
/// top) with a specular top-light and a soft colored lift shadow, so
/// they float instead of sitting flat. Secondary buttons are liquid
/// glass. Press feedback (scale + haptic) comes from [PressScale].
class TregaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  final bool expanded;
  final IconData? icon;

  /// Amber gradient variant for the loudest CTA on a screen.
  final bool accent;

  const TregaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.secondary = false,
    this.expanded = true,
    this.icon,
    this.accent = false,
  });

  static const _radius = BorderRadius.all(Radius.circular(16));

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    const baseStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );

    Widget button;
    if (secondary) {
      final fg = enabled ? AppColors.primary : AppColors.textSecondary;
      button = LiquidGlass(
        borderRadius: 16,
        blur: 14,
        onTap: onPressed,
        padding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        child: Center(child: _labelRow(baseStyle.copyWith(color: fg), fg)),
      );
    } else {
      final gradient = !enabled
          ? AppGradients.disabledButton
          : accent
              ? AppGradients.accentButton
              : AppGradients.primaryButton;
      final fg = !enabled
          ? AppColors.textSecondary
          : accent
              ? AppColors.textPrimary
              : Colors.white;
      button = Container(
        decoration: BoxDecoration(
          borderRadius: _radius,
          gradient: gradient,
          boxShadow: enabled
              ? (accent ? AppShadows.buttonAmber : AppShadows.button)
              : const [],
        ),
        // Inner container paints the specular top-light over the
        // gradient without needing a Stack (which would collapse).
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: _radius,
            gradient: AppGradients.buttonSheen,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: _radius,
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 15, horizontal: 20,),
                child: Center(
                    child: _labelRow(baseStyle.copyWith(color: fg), fg,),),
              ),
            ),
          ),
        ),
      );
    }

    final wrapped = PressScale(child: button);
    if (!expanded) return wrapped;
    return SizedBox(width: double.infinity, child: wrapped);
  }

  Widget _labelRow(TextStyle style, Color iconColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
