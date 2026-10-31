import 'package:flutter/material.dart';

/// Account colour palette — shared across themes because these decorate
/// small tinted bubbles next to fixed account names, not text. ALL other
/// colours (text, glass, semantics) live in [AppThemeSpec] and must be read
/// from `context.spec` so every theme stays legible.
abstract final class AppColors {
  static const accountPalette = <String, Color>{
    'blue': Color(0xFF5B8DEF),
    'teal': Color(0xFF2BC5B4),
    'violet': Color(0xFF9B7BFF),
    'amber': Color(0xFFFFB74D),
    'rose': Color(0xFFFF7A93),
    'green': Color(0xFF3DDC84),
  };

  /// Extra colours for khata people avatars.
  static const personPalette = <String, Color>{
    'blue': Color(0xFF5B8DEF),
    'violet': Color(0xFF9B7BFF),
    'rose': Color(0xFFFF7A93),
    'amber': Color(0xFFFFB74D),
    'teal': Color(0xFF2BC5B4),
    'green': Color(0xFF3DDC84),
  };

  static Color accountColor(String key) => accountPalette[key] ?? accountPalette['blue']!;
  static Color personColor(String key) => personPalette[key] ?? personPalette['blue']!;
}
