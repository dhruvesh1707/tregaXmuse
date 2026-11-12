import 'package:flutter/material.dart';

import '../icons/phosphor_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import 'motion.dart';

/// Floating tab bar: a solid white pill hovering above the content
/// instead of docking to the screen edge.
///
/// The flat fill, hairline border and the one shadow come from the bar
/// container below; the selected destination is a solid
/// [AppColors.primary] pill, and the center Sell tab is a raised brown
/// circle overlapping the top edge of the bar.
///
/// Destinations and tap behaviour are unchanged from the old
/// [BottomNavigationBar], only the presentation is new.
class FloatingTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Optional per-item anchor keys (same order as the destinations).
  /// Used by the first-run tour to point at individual tabs; screens
  /// that don't pass it are unaffected.
  final List<GlobalKey?>? itemKeys;

  const FloatingTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.itemKeys,
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
    // Plain Container, no clipping: the raised Sell circle paints above
    // the top edge of the bar without being cut off.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.divider, width: 1),
        boxShadow: AppShadows.floating,
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: i == 2
                  ? _SellTabButton(
                      key: (itemKeys != null && i < itemKeys!.length)
                          ? itemKeys![i]
                          : null,
                      icon: _items[i].icon,
                      label: _items[i].label,
                      selected: i == currentIndex,
                      // Release haptic + press scale come from Pressable
                      // below.
                      onTap: () => onTap(i),
                    )
                  : _TabButton(
                      key: (itemKeys != null && i < itemKeys!.length)
                          ? itemKeys![i]
                          : null,
                      icon: _items[i].icon,
                      label: _items[i].label,
                      selected: i == currentIndex,
                      // Release haptic + press scale come from Pressable below.
                      onTap: () => onTap(i),
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
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Pressable composes with the inner GestureDetector: it only scales
    // + haptics, so the existing onTap still fires unchanged.
    return Pressable(
      child: GestureDetector(
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
                    borderRadius:
                        BorderRadius.all(Radius.circular(20)),
                    color: AppColors.primary,
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
      ),
    );
  }
}

/// Raised center tab: a solid brown circle overlapping the top edge of
/// the bar, with the destination label below it.
///
/// The circle is positioned above the icon slot inside a [Stack] with
/// [Clip.none], so it is never clipped by the bar. The tab slot keeps
/// the same height as the other tabs: the 56dp circle paints above the
/// bar edge without pushing the bar taller. Tap behaviour matches
/// [_TabButton]: [Pressable] plus an opaque [GestureDetector].
class _SellTabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SellTabButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Pressable composes with the inner GestureDetector: it only scales
    // + haptics, so the existing onTap still fires unchanged.
    return Pressable(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reserves the icon slot height used by the other tabs
                // (7 + 24 + 7), so every tab slot is the same height.
                const SizedBox(height: 38),
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
            Positioned(
              top: -18,
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                  boxShadow: AppShadows.floating,
                ),
                child: Icon(icon, size: 28, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
