import 'package:flutter/material.dart';

import 'theme_spec.dart';

/// Motion tokens — short, spring-flavoured, restrained.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 140);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);

  /// Entrance: fast start, gentle settle (Material 3 emphasized decelerate).
  static const Curve enter = Easing.emphasizedDecelerate;

  /// Exit: quick wind-up, accelerate out.
  static const Curve exit = Easing.emphasizedAccelerate;

  /// Micro interactions (amount pulse, chips).
  static const Curve micro = Curves.easeOutCubic;
}

/// Radii used across the glass system.
abstract final class AppRadii {
  static const card = 24.0;
  static const panel = 28.0;
  static const chip = 14.0;
  static const key = 34.0; // keypad keys are round-ish
}

abstract final class AppDimens {
  static const pagePadding = EdgeInsets.symmetric(horizontal: 20, vertical: 12);
  static const minTouchTarget = 48.0;
}

/// Builds a [ThemeData] from an [AppThemeSpec]. Every text style carries an
/// explicit colour from the spec — nothing relies on inherited defaults, so
/// light-on-light / dark-on-dark bugs are impossible by construction.
abstract final class AppTheme {
  static ThemeData fromSpec(AppThemeSpec s) {
    final dark = s.isDark;

    final scheme = ColorScheme(
      brightness: s.brightness,
      primary: s.accent,
      onPrimary: s.onAccent,
      secondary: s.income,
      onSecondary: s.onAccent,
      tertiary: s.expense,
      onTertiary: s.onAccent,
      error: s.expense,
      onError: s.onAccent,
      surface: s.glassFill,
      onSurface: s.textPrimary,
      surfaceContainerHighest: s.glassFill,
      onSurfaceVariant: s.textSecondary,
      outline: s.glassBorder,
      outlineVariant: s.glassBorder,
      primaryContainer: s.accent.withValues(alpha: 0.18),
      onPrimaryContainer: s.textPrimary,
      surfaceContainer: s.glassFill,
      surfaceContainerHigh: s.glassFill,
      inverseSurface: s.textPrimary,
      onInverseSurface: s.bgTop,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: s.brightness,
      extensions: <ThemeExtension<dynamic>>{s},
    );

    return base.copyWith(
      scaffoldBackgroundColor: s.bgBottom,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(s),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: s.accent.withValues(alpha: 0.16),
        height: 64,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF1D2230) : const Color(0xFF232A3A),
        contentTextStyle: TextStyle(color: s.textPrimary, fontSize: 14),
        actionTextColor: s.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.chip)),
        side: BorderSide(color: s.glassBorder),
        labelStyle: TextStyle(color: s.textPrimary),
        secondaryLabelStyle: TextStyle(color: s.textPrimary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xFF141824) : Colors.white,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xFF171B26) : Colors.white,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: s.textPrimary,
        ),
        contentTextStyle: TextStyle(fontSize: 14.5, color: s.textSecondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.panel)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: dark ? const Color(0xFF171B26) : Colors.white,
        headerForegroundColor: s.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.panel)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: dark ? const Color(0xFF171B26) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.panel)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? s.onAccent : s.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? s.accent
              : (dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.10)),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.transparent : s.glassBorder,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: s.accent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: s.accent,
          foregroundColor: s.onAccent,
        ),
      ),
      iconTheme: IconThemeData(color: s.textPrimary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.035),
        hintStyle: TextStyle(color: s.textTertiary),
        labelStyle: TextStyle(color: s.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: s.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: s.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: s.accent, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: DividerThemeData(color: s.glassBorder, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: s.textSecondary,
        titleTextStyle: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: s.textPrimary),
        subtitleTextStyle: TextStyle(fontSize: 13, color: s.textSecondary),
      ),
    );
  }

  static TextTheme _textTheme(AppThemeSpec s) {
    TextStyle t(
      double size,
      FontWeight w, {
      Color? color,
      double? height,
      double? letterSpacing,
      bool tabular = false,
    }) =>
        TextStyle(
          fontSize: size,
          fontWeight: w,
          // Explicit colour on EVERY style — the root fix for the
          // "white text on white background" class of bugs.
          color: color ?? s.textPrimary,
          height: height,
          letterSpacing: letterSpacing,
          fontFeatures: tabular ? [FontFeature.tabularFigures()] : null,
        );

    return TextTheme(
      displayLarge: t(54, FontWeight.w600, letterSpacing: -1.2, tabular: true), // Quick Add amount
      displayMedium: t(34, FontWeight.w600, letterSpacing: -0.8, tabular: true),
      displaySmall: t(28, FontWeight.w600, letterSpacing: -0.6, tabular: true),
      headlineSmall: t(22, FontWeight.w600, letterSpacing: -0.3),
      titleLarge: t(18, FontWeight.w600, letterSpacing: -0.2),
      titleMedium: t(15.5, FontWeight.w600),
      titleSmall: t(13.5, FontWeight.w600, color: s.textSecondary),
      bodyLarge: t(15.5, FontWeight.w400, height: 1.45),
      bodyMedium: t(14, FontWeight.w400, height: 1.4, color: s.textSecondary),
      bodySmall: t(12.5, FontWeight.w400, color: s.textSecondary),
      labelLarge: t(15, FontWeight.w600),
      labelMedium: t(12.5, FontWeight.w500, color: s.textSecondary),
      labelSmall: t(11, FontWeight.w500, color: s.textTertiary),
    );
  }
}
