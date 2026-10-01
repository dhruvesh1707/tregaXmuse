import 'package:flutter/material.dart';

/// The single shadow recipe for the minimal Trega glass theme, plus
/// historic aliases.
///
/// Every frosted surface (cards, sheets, dialogs, chips, app bars, tab
/// bar) uses exactly [glass]: offset (0, 6), blur 18, warm tint
/// 0xFF3A2417 at 10% alpha (`Color(0x1A3A2417)`). The other names are
/// const aliases so feature call sites keep compiling. Colored glow
/// shadows are gone.
abstract final class AppShadows {
  /// The one recipe: warm, diffused, barely-there.
  static const List<BoxShadow> glass = [
    BoxShadow(
      color: Color(0x1A3A2417),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  /// Barely-there lift for tiles and small surfaces.
  static const List<BoxShadow> soft = glass;

  /// Product cards and content cards.
  static const List<BoxShadow> card = glass;

  /// Primary buttons.
  static const List<BoxShadow> button = glass;

  /// Amber CTA buttons.
  static const List<BoxShadow> buttonAmber = glass;

  /// Selected tab pill inside the floating tab bar.
  static const List<BoxShadow> tabSelected = glass;

  /// Floating elements (tab bar, FABs).
  static const List<BoxShadow> floating = glass;
}
