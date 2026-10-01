import 'package:flutter/material.dart';

/// Flat-clean shadow recipes for the Trega theme.
///
/// Every shadow is warm-tinted ([AppColors.shadowWarm]) rather than
/// pure black, with a small offset (0..4), modest blur (6..16) and low
/// alpha (0.06..0.14) — quiet separation instead of floating 3D
/// depth. No colored glow shadows. Shadows are `const` lists so they
/// cost nothing to reuse.
abstract final class AppShadows {
  /// Barely-there lift for tiles and small surfaces.
  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Color(0x143A2417),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Product cards and content cards.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x143A2417),
      blurRadius: 10,
      offset: Offset(0, 3),
    ),
  ];

  /// Primary buttons: one subtle warm shadow.
  static const List<BoxShadow> button = [
    BoxShadow(
      color: Color(0x263A2417),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Amber CTA buttons: the same quiet shadow, warm-tinted — no amber
  /// glow.
  static const List<BoxShadow> buttonAmber = [
    BoxShadow(
      color: Color(0x263A2417),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Liquid glass surfaces: diffused but quiet, so frosted elements
  /// sit cleanly over the content beneath.
  static const List<BoxShadow> glass = [
    BoxShadow(
      color: Color(0x1F3A2417),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  /// Selected tab pill inside the floating tab bar.
  static const List<BoxShadow> tabSelected = [
    BoxShadow(
      color: Color(0x1F3A2417),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Floating elements (tab bar, FABs): the deepest shadow in the set,
  /// still quiet.
  static const List<BoxShadow> floating = [
    BoxShadow(
      color: Color(0x223A2417),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];
}
