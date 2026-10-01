import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'liquid_glass.dart';
import 'motion.dart';

/// Primary / secondary / accent button — flat and solid.
///
/// - Primary: solid [AppColors.primary] fill, white label.
/// - Accent: solid [AppColors.accent] fill, dark label — the loudest CTA
///   on a screen.
/// - Secondary: true light-glass pill, [AppColors.primary] label.
///
/// Radius 16 everywhere. Press feedback (scale + haptic) comes from
/// [PressScale]; the label centers via a full-width Row — never
/// Center/Align, which expand to max height under finite-loose
/// constraints (Scaffold.bottomSheet, dialogs) and blow the button up
/// full-screen.
class TregaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  final bool expanded;
  final IconData? icon;

  /// Amber solid variant for the loudest CTA on a screen.
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

    late final Widget button;
    if (secondary) {
      final fg = enabled ? AppColors.primary : AppColors.textSecondary;
      button = LiquidGlass(
        borderRadius: 16,
        blur: 14,
        onTap: onPressed,
        padding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        child: _labelRow(baseStyle.copyWith(color: fg), fg),
      );
    } else {
      final Color fill;
      final Color fg;
      if (!enabled) {
        fill = const Color(0xFFE4D9CC);
        fg = AppColors.textSecondary;
      } else if (accent) {
        fill = AppColors.accent;
        fg = AppColors.textPrimary;
      } else {
        fill = AppColors.primary;
        fg = Colors.white;
      }
      button = Container(
        decoration: BoxDecoration(
          borderRadius: _radius,
          color: fill,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: _radius,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 20,
              ),
              child: _labelRow(baseStyle.copyWith(color: fg), fg),
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
