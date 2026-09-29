import 'package:flutter/material.dart';

/// Soft-3D shadow recipes for the modern Trega theme.
///
/// Every shadow is warm-tinted ([AppColors.shadowWarm]) rather than pure
/// black, and uses a large blur with a modest offset — depth you feel
/// rather than see. Shadows are `const` lists so they cost nothing to
/// reuse.
abstract final class AppShadows {
  /// Barely-there lift for tiles and small surfaces.
  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Color(0x143A2417),
      blurRadius: 24,
      offset: Offset(0, 10),
    ),
  ];

  /// Product cards and content cards.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x1A3A2417),
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
  ];

  /// Primary buttons: a colored lift shadow in brand brown plus a soft
  /// ambient — the button floats instead of sitting flat.
  static const List<BoxShadow> button = [
    BoxShadow(
      color: Color(0x668B3A1C),
      blurRadius: 16,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x143A2417),
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
  ];

  /// Amber CTA buttons: warm glow instead of brown.
  static const List<BoxShadow> buttonAmber = [
    BoxShadow(
      color: Color(0x66F7B600),
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x143A2417),
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
  ];

  /// Liquid glass surfaces: deep but diffused, so frosted elements
  /// hover over the content beneath.
  static const List<BoxShadow> glass = [
    BoxShadow(
      color: Color(0x243A2417),
      blurRadius: 32,
      offset: Offset(0, 14),
    ),
  ];

  /// Selected tab pill inside the floating tab bar.
  static const List<BoxShadow> tabSelected = [
    BoxShadow(
      color: Color(0x598B3A1C),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// Floating elements (tab bar, FABs): the deepest shadow in the set.
  static const List<BoxShadow> floating = [
    BoxShadow(
      color: Color(0x2E3A2417),
      blurRadius: 40,
      offset: Offset(0, 16),
    ),
  ];
}
