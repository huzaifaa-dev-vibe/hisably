import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A complete, self-contained visual theme for Hisably.
///
/// Every colour the UI can use lives here — including semantic colours
/// (income/expense/accent) and all text colours. Screens must read tokens
/// from `context.spec` (or from `Theme.of(context)` styles) and never from
/// hardcoded constants, so that ALL themes are guaranteed legible.
///
/// Contrast contract (enforced by test/core/theme_contrast_test.dart):
/// * textPrimary  on glassFill ≥ 4.5 : 1   (body text, AA)
/// * textSecondary on glassFill ≥ 4.5 : 1  (captions, AA)
/// * accent / income / expense as text on bgTop ≥ 4.5 : 1
/// * onAccent on accent ≥ 4.5 : 1
@immutable
class AppThemeSpec extends ThemeExtension<AppThemeSpec> {
  const AppThemeSpec({
    required this.id,
    required this.label,
    required this.brightness,
    required this.bgTop,
    required this.bgBottom,
    required this.aurora1,
    required this.aurora2,
    required this.aurora3,
    required this.glassFill,
    required this.glassBorder,
    required this.glassHighlight,
    required this.keyFill,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.income,
    required this.expense,
    required this.warn,
    required this.transfer,
  });

  final String id;
  final String label;
  final Brightness brightness;

  // Background gradient + aurora blobs.
  final Color bgTop;
  final Color bgBottom;
  final Color aurora1;
  final Color aurora2;
  final Color aurora3;

  // Glass surfaces.
  final Color glassFill;
  final Color glassBorder;
  final Color glassHighlight;

  /// Keypad / input key fill (slightly stronger than glass in light themes).
  final Color keyFill;

  // Text.
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  // Semantics.
  final Color accent;
  final Color onAccent;
  final Color income;
  final Color expense;
  final Color warn;
  final Color transfer;

  // ---------------------------------------------------------------- derive

  /// True when this spec should be used when the OS is in dark mode.
  bool get isDark => brightness == Brightness.dark;

  @override
  AppThemeSpec copyWith({
    String? id,
    String? label,
    Brightness? brightness,
    Color? bgTop,
    Color? bgBottom,
    Color? aurora1,
    Color? aurora2,
    Color? aurora3,
    Color? glassFill,
    Color? glassBorder,
    Color? glassHighlight,
    Color? keyFill,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? onAccent,
    Color? income,
    Color? expense,
    Color? warn,
    Color? transfer,
  }) {
    return AppThemeSpec(
      id: id ?? this.id,
      label: label ?? this.label,
      brightness: brightness ?? this.brightness,
      bgTop: bgTop ?? this.bgTop,
      bgBottom: bgBottom ?? this.bgBottom,
      aurora1: aurora1 ?? this.aurora1,
      aurora2: aurora2 ?? this.aurora2,
      aurora3: aurora3 ?? this.aurora3,
      glassFill: glassFill ?? this.glassFill,
      glassBorder: glassBorder ?? this.glassBorder,
      glassHighlight: glassHighlight ?? this.glassHighlight,
      keyFill: keyFill ?? this.keyFill,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      income: income ?? this.income,
      expense: expense ?? this.expense,
      warn: warn ?? this.warn,
      transfer: transfer ?? this.transfer,
    );
  }

  @override
  AppThemeSpec lerp(AppThemeSpec? other, double t) =>
      other == null ? this : (t < 0.5 ? this : other);

  // The ThemeExtension requires equality on identity — specs are
  // singletons, so `identical` is correct and cheap.
  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);

  // ------------------------------------------------------------- contrast

  /// WCAG 2.1 contrast ratio between two colours (1.0 – 21.0).
  static double contrastRatio(Color a, Color b) {
    final la = _relativeLuminance(a);
    final lb = _relativeLuminance(b);
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double _relativeLuminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }
}

/// Convenience accessors. `context.spec` is the canonical way to read a
/// theme token from any widget.
extension AppThemeSpecX on BuildContext {
  AppThemeSpec get spec =>
      Theme.of(this).extension<AppThemeSpec>() ?? AppThemes.obsidian;

  Color get accent => spec.accent;
  Color get incomeColor => spec.income;
  Color get expenseColor => spec.expense;
  Color get glassBorder => spec.glassBorder;
  Color get glassFill => spec.glassFill;
}

/// The theme catalogue. Two lights, three darks, plus "System".
abstract final class AppThemes {
  static const system = AppThemeSpec(
    id: 'system',
    label: 'System',
    brightness: Brightness.light,
    // Placeholder tokens — never rendered; System resolves to
    // [porcelain]/[obsidian] by platform brightness at the app root.
    bgTop: Color(0xFFF3F5FA),
    bgBottom: Color(0xFFE9EDF5),
    aurora1: Color(0x269DB8FF),
    aurora2: Color(0x1FC9B8FF),
    aurora3: Color(0x1A9FE8D8),
    glassFill: Color(0xCCFFFFFF),
    glassBorder: Color(0x59FFFFFF),
    glassHighlight: Color(0xB3FFFFFF),
    keyFill: Color(0x9EFFFFFF),
    textPrimary: Color(0xFF12151C),
    textSecondary: Color(0xFF596272),
    textTertiary: Color(0xFF9AA3B2),
    accent: Color(0xFF3D6BE0),
    onAccent: Color(0xFFFFFFFF),
    income: Color(0xFF0E9F5F),
    expense: Color(0xFFE5484D),
    warn: Color(0xFFB96E00),
    transfer: Color(0xFF6E56CF),
  );

  /// Light — "Porcelain". Cool white glass, blue accent.
  static const porcelain = AppThemeSpec(
    id: 'porcelain',
    label: 'Porcelain',
    brightness: Brightness.light,
    bgTop: Color(0xFFF3F5FA),
    bgBottom: Color(0xFFE9EDF5),
    aurora1: Color(0x339DB8FF),
    aurora2: Color(0x2EC9B8FF),
    aurora3: Color(0x249FE8D8),
    glassFill: Color(0xE6FFFFFF),
    glassBorder: Color(0x8CFFFFFF),
    glassHighlight: Color(0xB3FFFFFF),
    keyFill: Color(0xB8FFFFFF),
    textPrimary: Color(0xFF10141B),
    textSecondary: Color(0xFF4E586B),
    textTertiary: Color(0xFF7D879A),
    accent: Color(0xFF3D6BE0),
    onAccent: Color(0xFFFFFFFF),
    income: Color(0xFF0B8A50),
    expense: Color(0xFFD93A44),
    warn: Color(0xFFA96400),
    transfer: Color(0xFF6E56CF),
  );

  /// Dark — "Obsidian". Near-black glass, periwinkle accent. Default.
  static const obsidian = AppThemeSpec(
    id: 'obsidian',
    label: 'Obsidian',
    brightness: Brightness.dark,
    bgTop: Color(0xFF0B0D14),
    bgBottom: Color(0xFF06070B),
    aurora1: Color(0x293D5AFE),
    aurora2: Color(0x1F7C4DFF),
    aurora3: Color(0x1400BFA5),
    glassFill: Color(0xB3141822),
    glassBorder: Color(0x24FFFFFF),
    glassHighlight: Color(0x14FFFFFF),
    keyFill: Color(0xFF14171F),
    textPrimary: Color(0xFFF0F3F9),
    textSecondary: Color(0xFFAAB4C4),
    textTertiary: Color(0xFF7C8698),
    accent: Color(0xFF8FB4FF),
    onAccent: Color(0xFF0A1020),
    income: Color(0xFF4ADE80),
    expense: Color(0xFFFF7A85),
    warn: Color(0xFFFFC069),
    transfer: Color(0xFFA5B4FC),
  );

  /// Dark — "Midnight". Deep blue-navy, cyan accent.
  static const midnight = AppThemeSpec(
    id: 'midnight',
    label: 'Midnight',
    brightness: Brightness.dark,
    bgTop: Color(0xFF0A1120),
    bgBottom: Color(0xFF060B16),
    aurora1: Color(0x2E00C2FF),
    aurora2: Color(0x263B82F6),
    aurora3: Color(0x1A22D3EE),
    glassFill: Color(0xB30F1A2E),
    glassBorder: Color(0x269EC1FF),
    glassHighlight: Color(0x149EC1FF),
    keyFill: Color(0xFF12203A),
    textPrimary: Color(0xFFEDF4FF),
    textSecondary: Color(0xFFA3B8D8),
    textTertiary: Color(0xFF7488A8),
    accent: Color(0xFF67E8F9),
    onAccent: Color(0xFF04212B),
    income: Color(0xFF34D399),
    expense: Color(0xFFF87171),
    warn: Color(0xFFFBBF24),
    transfer: Color(0xFF93C5FD),
  );

  /// Dark — "Forest". Charcoal-green, mint accent.
  static const forest = AppThemeSpec(
    id: 'forest',
    label: 'Forest',
    brightness: Brightness.dark,
    bgTop: Color(0xFF0C1512),
    bgBottom: Color(0xFF070D0B),
    aurora1: Color(0x2210B981),
    aurora2: Color(0x1A34D399),
    aurora3: Color(0x142DD4BF),
    glassFill: Color(0xB3121D18),
    glassBorder: Color(0x266EE7B7),
    glassHighlight: Color(0x146EE7B7),
    keyFill: Color(0xFF16241E),
    textPrimary: Color(0xFFECF6F0),
    textSecondary: Color(0xFFA6C3B4),
    textTertiary: Color(0xFF74948A),
    accent: Color(0xFF6EE7B7),
    onAccent: Color(0xFF05291B),
    income: Color(0xFF86EFAC),
    expense: Color(0xFFFCA5A5),
    warn: Color(0xFFFCD34D),
    transfer: Color(0xFF9BE8D8),
  );

  /// Light — "Sand". Warm paper, terracotta accent.
  static const sand = AppThemeSpec(
    id: 'sand',
    label: 'Sand',
    brightness: Brightness.light,
    bgTop: Color(0xFFF8F4EC),
    bgBottom: Color(0xFFEFE8DB),
    aurora1: Color(0x2EF59E0B),
    aurora2: Color(0x2AD97706),
    aurora3: Color(0x1E84CC16),
    glassFill: Color(0xE6FFFFFF),
    glassBorder: Color(0x8CFFFFFF),
    glassHighlight: Color(0xB3FFFFFF),
    keyFill: Color(0xB8FFFFFF),
    textPrimary: Color(0xFF231C12),
    textSecondary: Color(0xFF5C5140),
    textTertiary: Color(0xFF8C8271),
    accent: Color(0xFFC2410C),
    onAccent: Color(0xFFFFFFFF),
    income: Color(0xFF15803D),
    expense: Color(0xFFDC2626),
    warn: Color(0xFFA16207),
    transfer: Color(0xFF7C3AED),
  );

  /// Catalogue shown on the Profile page, in order.
  static const List<AppThemeSpec> selectable = [
    system,
    porcelain,
    obsidian,
    midnight,
    forest,
    sand,
  ];

  static AppThemeSpec byId(String id) =>
      selectable.firstWhere((s) => s.id == id, orElse: () => system);

  /// Resolves the special `system` entry against the platform brightness.
  static AppThemeSpec resolve(String id, Brightness platform) {
    final spec = byId(id);
    if (identical(spec, system)) {
      return platform == Brightness.dark ? obsidian : porcelain;
    }
    return spec;
  }
}
