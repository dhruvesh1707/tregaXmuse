import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import 'liquid_glass.dart';
import 'motion.dart';

/// Primary / secondary button with Trega styling — flat solid fills.
///
/// Primary buttons are solid brand brown with a white label and one
/// subtle shadow; the amber accent variant is solid amber with a dark
/// label; disabled is flat warm grey. Secondary buttons are liquid
/// glass. Press feedback (scale + haptic) comes from [PressScale].
class TregaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  final bool expanded;
  final IconData? icon;

  /// Amber variant for the loudest CTA on a screen.
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
        // NOTE: no Center/Align here — under finite-loose constraints
        // (Scaffold.bottomSheet, dialogs) they expand to max height and
        // the button fills the screen. The Row centers itself instead.
        child: _labelRow(baseStyle.copyWith(color: fg), fg),
      );
    } else {
      final fill = !enabled
          ? const Color(0xFFE2D8C9)
          : accent
              ? AppColors.accent
              : AppColors.primary;
      final fg = !enabled
          ? AppColors.textSecondary
          : accent
              ? AppColors.textPrimary
              : Colors.white;
      button = Container(
        decoration: BoxDecoration(
          borderRadius: _radius,
          color: fill,
          boxShadow: enabled ? AppShadows.button : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: _radius,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: 15, horizontal: 20,),
              // NOTE: no Center/Align here — under finite-loose
              // constraints (Scaffold.bottomSheet, dialogs) they expand
              // to max height and the button fills the screen. The Row
              // centers itself instead.
              child: _labelRow(baseStyle.copyWith(color: fg), fg,),
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
    // MainAxisSize.max + center: the label centers itself horizontally
    // without a Center/Align widget (those expand to max height under
    // finite-loose constraints and would blow the button up full-screen).
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
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
