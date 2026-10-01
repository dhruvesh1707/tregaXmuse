import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Flat-clean surface fills for the Trega theme.
///
/// Every member keeps its historical name (call sites across the app
/// reference them) but renders flat: solid colors or uniform
/// gradients with no specular sheen, no 3D light-falloff and no
/// ambient glows. White or light labels always sit on the solid
/// brand colors below.
abstract final class AppGradients {
  /// Page background: solid warm paper.
  static const LinearGradient page = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.background, AppColors.background],
  );

  /// Primary button: solid brand brown.
  static const LinearGradient primaryButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.primary, AppColors.primary],
  );

  /// Amber CTA: solid brand amber.
  static const LinearGradient accentButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.accent, AppColors.accent],
  );

  /// Disabled button: flat warm grey.
  static const LinearGradient disabledButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFE2D8C9), Color(0xFFE2D8C9)],
  );

  /// Frosted fill for liquid glass: uniform subtle white.
  static const LinearGradient glassTint = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x40FFFFFF), Color(0x40FFFFFF)],
  );

  /// Former glass hairline gradient — kept for API compatibility.
  /// New code should use a plain hairline border instead.
  static const LinearGradient glassBorder = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x33FFFFFF), Color(0x33FFFFFF)],
  );

  /// Former specular top-light — flattened to transparent. Kept so
  /// existing references keep compiling.
  static const LinearGradient sheen = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00FFFFFF), Color(0x00FFFFFF)],
  );

  /// Former button sheen — flattened to transparent. Kept so
  /// existing references keep compiling.
  static const LinearGradient buttonSheen = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00FFFFFF), Color(0x00FFFFFF)],
  );

  /// Card surface: solid white.
  static const LinearGradient card = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
  );

  /// Hero surfaces: solid deep brand brown.
  static const LinearGradient heroBrown = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primaryDeep, AppColors.primaryDeep],
  );

  /// Former ambient amber glow — flattened to transparent. Kept so
  /// existing references keep compiling.
  static const RadialGradient amberGlow = RadialGradient(
    colors: [Color(0x00F7B600), Color(0x00F7B600)],
  );
}
