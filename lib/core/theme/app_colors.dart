import 'package:flutter/material.dart';

/// Trega brand palette, derived from the official logo.
///
/// - Primary brown  `#8B3A1C` — logo wordmark
/// - Dark brown     `#6E2E16` — pressed / emphasis states
/// - Accent yellow  `#F7B600` — logo dot, CTAs highlights, badges
/// - Background     `#FFFBF7` — warm paper
/// - Surface        `#FFFFFF` — cards, sheets
///
/// The extended tokens below (gradient stops, glass tints, espresso)
/// power the modern theme: soft gradients, soft-3D depth and liquid
/// glass surfaces. They are additive — every original value is unchanged.
abstract final class AppColors {
  static const Color primary = Color(0xFF8B3A1C);
  static const Color primaryDark = Color(0xFF6E2E16);
  static const Color primarySoft = Color(0xFFF6E7DA);
  static const Color accent = Color(0xFFF7B600);
  static const Color accentSoft = Color(0xFFFFF3D1);
  static const Color background = Color(0xFFFFFBF7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onPrimary = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF2B1A12);
  static const Color textSecondary = Color(0xFF8A6A5B);
  static const Color divider = Color(0xFFF0E4D6);

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFE65100);
  static const Color error = Color(0xFFC62828);
  static const Color info = Color(0xFF1565C0);

  // -- Gradient stops -------------------------------------------------
  /// Lighter top edge of the primary button gradient (soft-3D light).
  static const Color primaryLight = Color(0xFFA34A24);

  /// Deepest brown, bottom of the primary gradient and hero surfaces.
  static const Color primaryDeep = Color(0xFF5E2410);

  /// Lighter top edge of the amber gradient.
  static const Color accentLight = Color(0xFFFFC933);

  /// Deepest amber, bottom of the amber gradient.
  static const Color accentDeep = Color(0xFFE09600);

  // -- Page background wash --------------------------------------------
  static const Color pageTop = Color(0xFFFFFDF8);
  static const Color pageMid = Color(0xFFFFF5E8);
  static const Color pageBottom = Color(0xFFFDEEDC);

  // -- Espresso (dark brand surfaces, hero headers) ---------------------
  static const Color espresso = Color(0xFF1A0F08);
  static const Color espressoLight = Color(0xFF2A1A0E);

  // -- Soft-3D shadow tint (warm, never pure black) ----------------------
  static const Color shadowWarm = Color(0xFF3A2417);
}
