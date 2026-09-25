import 'package:flutter/material.dart';

/// Trega brand palette, derived from the official logo.
///
/// - Primary brown  `#8B3A1C` — logo wordmark
/// - Dark brown     `#6E2E16` — pressed / emphasis states
/// - Accent yellow  `#F7B600` — logo dot, CTAs highlights, badges
/// - Background     `#FFFBF7` — warm paper
/// - Surface        `#FFFFFF` — cards, sheets
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
}

/// Builds the app-wide [ThemeData] for Trega.
ThemeData buildTregaTheme() {
  final baseScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  );
  final scheme = baseScheme.copyWith(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primarySoft,
    onPrimaryContainer: AppColors.primaryDark,
    secondary: AppColors.accent,
    onSecondary: AppColors.textPrimary,
    secondaryContainer: AppColors.accentSoft,
    onSecondaryContainer: AppColors.textPrimary,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    error: AppColors.error,
    onError: Colors.white,
  );

  // Premium pass: tight tracking on display type, relaxed leading on body
  // copy, tabular figures on prices handled at the call site.
  const textTheme = TextTheme(
    displaySmall: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
      letterSpacing: -0.8,
      height: 1.2,
    ),
    headlineSmall: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
      letterSpacing: -0.4,
      height: 1.25,
    ),
    titleLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
      letterSpacing: -0.2,
      height: 1.3,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      letterSpacing: -0.1,
      height: 1.35,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      height: 1.4,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      color: AppColors.textPrimary,
      height: 1.5,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      color: AppColors.textPrimary,
      height: 1.5,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      color: AppColors.textSecondary,
      height: 1.45,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: AppColors.onPrimary,
      letterSpacing: 0.1,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
      letterSpacing: 0.6,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.divider,
        disabledForegroundColor: AppColors.textSecondary,
        minimumSize: const Size(48, 54),
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        disabledForegroundColor: AppColors.textSecondary,
        minimumSize: const Size(48, 54),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      // Extra headroom above the field: the floating label sits ~8px above
      // the border, and tight parents (Stepper content, dense columns)
      // otherwise clip its top edge.
      contentPadding:
          const EdgeInsets.fromLTRB(16, 20, 16, 16),
      hintStyle: const TextStyle(color: AppColors.textSecondary),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      // NOTE: no backgroundColor on the floating label. Material 3's
      // InputDecorator already cuts a clean gap in the outline behind the
      // label; painting a background box on top of that is what made the
      // sell-flow Title/Price labels look sliced.
      floatingLabelStyle: const TextStyle(
        color: AppColors.primary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
    ),
    chipTheme: baseScheme.brightness == Brightness.light
        ? const ChipThemeData(
            backgroundColor: AppColors.primarySoft,
            labelStyle: TextStyle(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w600,
            ),
            side: BorderSide.none,
            shape: StadiumBorder(),
          )
        : null,
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      elevation: 0,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  );
}
