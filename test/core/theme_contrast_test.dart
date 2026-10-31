import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hisably/core/theme/theme_spec.dart';
import 'package:hisably/core/version.dart';

/// The contract that makes "white text on white background" impossible:
/// every shipped theme must satisfy minimum WCAG contrast ratios on its
/// own surfaces. If a new theme fails here, fix the spec — never the test.
void main() {
  group('theme contrast contract (WCAG 2.1)', () {
    // `system` resolves to porcelain/obsidian, so test the resolved set.
    final specs = [
      for (final s in AppThemes.selectable)
        if (s.id != 'system') s,
      AppThemes.resolve('system', Brightness.dark),
      AppThemes.resolve('system', Brightness.light),
    ];

    for (final s in specs) {
      group(s.label, () {
        test('body text is readable on glass surfaces', () {
          expect(
            AppThemeSpec.contrastRatio(s.textPrimary, s.glassFill),
            greaterThanOrEqualTo(4.5),
            reason: '${s.label}: textPrimary on glassFill',
          );
          expect(
            AppThemeSpec.contrastRatio(s.textSecondary, s.glassFill),
            greaterThanOrEqualTo(4.5),
            reason: '${s.label}: textSecondary on glassFill',
          );
        });

        test('hints stay visible (tertiary text)', () {
          expect(
            AppThemeSpec.contrastRatio(s.textTertiary, s.glassFill),
            greaterThanOrEqualTo(3.0),
            reason: '${s.label}: textTertiary on glassFill',
          );
        });

        test('primary text has strong contrast on the page background', () {
          expect(
            AppThemeSpec.contrastRatio(s.textPrimary, s.bgTop),
            greaterThanOrEqualTo(7.0),
            reason: '${s.label}: textPrimary on bgTop',
          );
        });

        test('semantic colours read as text on the background', () {
          for (final (name, c) in [
            ('accent', s.accent),
            ('income', s.income),
            ('expense', s.expense),
          ]) {
            expect(
              AppThemeSpec.contrastRatio(c, s.bgTop),
              greaterThanOrEqualTo(3.0),
              reason: '${s.label}: $name on bgTop',
            );
            expect(
              AppThemeSpec.contrastRatio(c, s.glassFill),
              greaterThanOrEqualTo(3.0),
              reason: '${s.label}: $name on glassFill',
            );
          }
        });

        test('text on accent-filled buttons is readable', () {
          expect(
            AppThemeSpec.contrastRatio(s.onAccent, s.accent),
            greaterThanOrEqualTo(3.0),
            reason: '${s.label}: onAccent on accent',
          );
        });
      });
    }
  });

  group('theme catalogue', () {
    test('unknown ids fall back safely', () {
      expect(AppThemes.byId('nope').id, 'system');
      expect(AppThemes.resolve('porcelain', Brightness.dark).id, 'porcelain');
    });

    test('system follows platform brightness', () {
      expect(
        identical(AppThemes.resolve('system', Brightness.dark), AppThemes.obsidian),
        isTrue,
      );
      expect(
        identical(AppThemes.resolve('system', Brightness.light), AppThemes.porcelain),
        isTrue,
      );
    });

    test('every selectable theme is complete (id/label unique)', () {
      final ids = AppThemes.selectable.map((s) => s.id).toSet();
      expect(ids.length, AppThemes.selectable.length);
      for (final s in AppThemes.selectable) {
        expect(s.label, isNotEmpty);
      }
    });
  });

  test('AppVersion matches pubspec', () {
    final pubspec = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!
        .group(1)!;
    // pubspec format: <name>+<build>
    final nameOnly = pubspec.split('+').first;
    expect(nameOnly, AppVersion.string);
  });
}
