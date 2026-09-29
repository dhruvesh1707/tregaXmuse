import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Soft gradients for the modern Trega theme.
///
/// Everything here is deliberately low-contrast and warm: the gradients
/// add depth and light without ever shouting over the content.
abstract final class AppGradients {
  /// Page background wash: warm paper that deepens gently toward the
  /// bottom. Used by [TregaScaffold].
  static const LinearGradient page = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.pageTop,
      AppColors.pageMid,
      AppColors.pageBottom,
    ],
  );

  /// Primary button: light falls from the top, weight settles at the
  /// bottom — the soft-3D look. Stops keep the mid-tone dominant so
  /// white labels stay crisp.
  static const LinearGradient primaryButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.primaryLight,
      AppColors.primary,
      AppColors.primaryDark,
    ],
    stops: [0.0, 0.55, 1.0],
  );

  /// Amber CTA gradient, same light logic as [primaryButton].
  static const LinearGradient accentButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.accentLight,
      AppColors.accent,
      AppColors.accentDeep,
    ],
    stops: [0.0, 0.55, 1.0],
  );

  /// Disabled button: flat warm grey, no depth.
  static const LinearGradient disabledButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFE9E0D4), Color(0xFFD9CDBE)],
  );

  /// Frosted fill for liquid glass: brighter top-left, softer middle,
  /// a touch of weight at the bottom-right — like light through glass.
  static const LinearGradient glassTint = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xA6FFFFFF),
      Color(0x59FFFFFF),
      Color(0x8CFFFFFF),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  /// Hairline border for liquid glass: bright where the light hits
  /// (top-left), dissolving toward the bottom-right.
  static const LinearGradient glassBorder = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xD9FFFFFF),
      Color(0x40FFFFFF),
      Color(0x99FFFFFF),
    ],
    stops: [0.0, 0.55, 1.0],
  );

  /// Specular top-light: painted over buttons, cards and glass to fake
  /// the highlight a real light source leaves on a curved surface.
  static const LinearGradient sheen = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
    stops: [0.0, 0.5],
  );

  /// Gentler sheen for buttons (painted over the button gradient).
  static const LinearGradient buttonSheen = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
    stops: [0.0, 0.6],
  );

  /// Card surface: barely-there diagonal light, keeps cards from
  /// looking flat against the page wash.
  static const LinearGradient card = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFFFF7EE)],
  );

  /// Rich espresso gradient for hero headers and dark moments.
  static const LinearGradient heroBrown = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.espressoLight, AppColors.primaryDeep],
  );

  /// Soft ambient amber glow, used behind floating elements.
  static const RadialGradient amberGlow = RadialGradient(
    colors: [Color(0x59F7B600), Color(0x00F7B600)],
    stops: [0.0, 1.0],
  );
}
