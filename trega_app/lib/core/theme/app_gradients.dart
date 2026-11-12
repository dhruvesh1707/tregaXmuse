import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Solid / subtle fills for the espresso-and-cream theme.
///
/// Every historic member name is kept so feature call sites keep
/// compiling, but the gradients are flattened: surfaces are solid and
/// ambient glows are fully transparent. The spec forbids gradient
/// washes, glow blobs and sheens, these tokens now encode that by being
/// solid. The one real gradient is [headerEspresso], the espresso
/// header zone blend.
abstract final class AppGradients {
  /// Page background: flat warm paper. Kept as a same-color gradient so
  /// call sites passing it to `gradient:` keep compiling.
  static const LinearGradient page = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.background,
      AppColors.background,
    ],
  );

  /// Primary button: solid brand brown.
  static const LinearGradient primaryButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.primary,
      AppColors.primary,
    ],
  );

  /// Amber CTA: solid accent.
  static const LinearGradient accentButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.accent,
      AppColors.accent,
    ],
  );

  /// Disabled button: flat warm grey, no depth.
  static const LinearGradient disabledButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFE4D9CC), Color(0xFFE4D9CC)],
  );

  /// Translucent white fill (alpha 0.70), kept for call-site compatibility.
  static const LinearGradient glassTint = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xB3FFFFFF),
      Color(0xB3FFFFFF),
    ],
  );

  /// Hairline border: white at 0.60 alpha, kept for call-site compatibility.
  static const LinearGradient glassBorder = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x99FFFFFF),
      Color(0x99FFFFFF),
    ],
  );

  /// Specular top-light: removed, fully transparent. Do not paint
  /// highlights over surfaces.
  static const LinearGradient sheen = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00FFFFFF), Color(0x00FFFFFF)],
  );

  /// Button sheen: removed, fully transparent.
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

  /// Hero surfaces: solid espresso.
  static const LinearGradient heroBrown = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.espresso, AppColors.espresso],
  );

  /// Espresso header zone: espresso to espressoLight.
  static const LinearGradient headerEspresso = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.espresso, AppColors.espressoLight]);

  /// Ambient amber glow: removed, fully transparent. No glow blobs.
  static const RadialGradient amberGlow = RadialGradient(
    colors: [Color(0x00F7B600), Color(0x00F7B600)],
    stops: [0.0, 1.0],
  );
}
