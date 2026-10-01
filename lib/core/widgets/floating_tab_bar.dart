import 'package:flutter/material.dart';

import '../icons/phosphor_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import 'liquid_glass.dart';
import 'motion.dart';

/// iOS-style floating tab bar: a liquid-glass pill hovering above the
/// content instead of docking to the screen edge.
///
/// Frosted blur comes from [LiquidGlass]; the selected destination
/// gets a solid primary pill.
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
    return LiquidGlass(
      borderRadius: 30,
      blur: 24,
      shadows: AppShadows.floating,
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
            decoration: selected
                ? const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                    color: AppColors.primary,
                    boxShadow: AppShadows.tabSelected,
                  )
                : null,
            child: Icon(
              icon,
              size: 24,
              color: selected ? Colors.white : scheme.onSurfaceVariant,
            ),
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
