import 'dart:ui';

import 'package:flutter/material.dart';

import '../icons/phosphor_icons.dart';
import '../theme/app_theme.dart';
import 'motion.dart';

/// iOS-style floating tab bar: a rounded, blurred pill hovering above the
/// content instead of docking to the screen edge.
///
/// Destinations and tap behaviour are unchanged from the old
/// [BottomNavigationBar] — only the presentation is new.
class FloatingTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const FloatingTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const List<({IconData icon, String label})> _items = [
    (icon: PhosphorIconsRegular.house, label: 'Home'),
    (icon: PhosphorIconsRegular.magnifyingGlass, label: 'Search'),
    (icon: PhosphorIconsRegular.plusCircle, label: 'Sell'),
    (icon: PhosphorIconsRegular.gavel, label: 'Bids'),
    (icon: PhosphorIconsRegular.user, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _TabButton(
                    icon: _items[i].icon,
                    label: _items[i].label,
                    selected: i == currentIndex,
                    onTap: () {
                      TregaHaptics.tap();
                      onTap(i);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor =
        selected ? AppColors.primary : scheme.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              height: 1.1,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? AppColors.primary
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
