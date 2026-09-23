import 'package:flutter/material.dart';

import 'motion.dart';

/// Primary / secondary button with Trega styling.
///
/// Wraps [ElevatedButton] / [OutlinedButton] so button language stays
/// consistent across features. Press feedback (scale + haptic) comes from
/// [PressScale].
class TregaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  final bool expanded;
  final IconData? icon;

  const TregaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.secondary = false,
    this.expanded = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          );

    final button = PressScale(
      child: secondary
          ? OutlinedButton(onPressed: onPressed, child: child)
          : ElevatedButton(onPressed: onPressed, child: child),
    );

    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
