import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hisably/app.dart';
import 'package:hisably/core/db/app_database.dart';
import 'package:hisably/core/haptics/app_haptics.dart';
import 'package:hisably/core/theme/glass.dart';
import 'package:hisably/core/theme/theme_spec.dart';
import 'package:hisably/data/providers.dart';
import 'package:hisably/data/settings.dart';
import 'package:hisably/features/profile/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boots the real app against an in-memory database and mocked prefs —
/// the same overrides main() uses in production, swapped for test doubles.
Future<ProviderContainer> pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(const {});
  final db = AppDatabase.memory();
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const HisablyApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('shell shows 4 tabs and the Quick Add button inside the dock',
      (tester) async {
    await pumpApp(tester);

    // Four reachable tabs (labels also appear as page titles, hence
    // findsWidgets rather than findsOneWidget).
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Accounts'), findsWidgets);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);

    // The Quick Add button exists…
    final fabFinder = find.byType(QuickAddButton);
    expect(fabFinder, findsOneWidget);

    // …and sits fully INSIDE the navigation dock — the regression test for
    // the "Quick Add overlaps the bottom bar" bug. No corner of the button
    // may leave the dock rect.
    final dockRect = tester.getRect(find.byKey(const ValueKey('nav-dock')));
    final fabRect = tester.getRect(fabFinder);
    expect(dockRect.contains(fabRect.topLeft), isTrue,
        reason: 'Quick Add top-left must be inside the dock');
    expect(dockRect.contains(fabRect.bottomRight), isTrue,
        reason: 'Quick Add bottom-right must be inside the dock');
  });

  testWidgets('tapping Profile tab opens the profile page', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();

    expect(find.text('APPEARANCE'), findsOneWidget);

    // All six theme cards render (the grid fits the test viewport).
    for (final label in [
      'System',
      'Porcelain',
      'Obsidian',
      'Midnight',
      'Forest',
      'Sand',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    // The ListView is lazy — scroll until the feedback section is built.
    final profileList = find
        .descendant(of: find.byType(ProfileScreen), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      find.text('FEEDBACK'),
      160,
      scrollable: profileList,
    );
    await tester.pumpAndSettle();
    expect(find.text('FEEDBACK'), findsOneWidget);

    // Haptics switch exists and defaults to on.
    final switchTile = find.widgetWithText(SwitchListTile, 'Haptic feedback');
    expect(switchTile, findsOneWidget);
    final tile = tester.widget<SwitchListTile>(switchTile);
    expect(tile.value, isTrue);
  });

  testWidgets('picking a theme updates the setting and the app theme',
      (tester) async {
    final container = await pumpApp(tester);

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();

    // The card may exist just beyond the viewport (cacheExtent) — reveal it
    // before tapping, otherwise the hit test lands on nothing.
    await tester.ensureVisible(find.text('Sand'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sand'));
    await tester.pumpAndSettle();

    expect(container.read(themeSettingProvider), 'sand');
    // The MaterialApp now carries the Sand spec.
    final context = tester.element(find.byType(Navigator).first);
    final spec = Theme.of(context).extension<AppThemeSpec>();
    expect(spec, same(AppThemes.sand));
  });

  testWidgets('toggling haptics flips the AppHaptics gate', (tester) async {
    final container = await pumpApp(tester);

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();

    final profileList = find
        .descendant(of: find.byType(ProfileScreen), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      find.text('FEEDBACK'),
      160,
      scrollable: profileList,
    );
    await tester.pumpAndSettle();

    final switchTile = find.widgetWithText(SwitchListTile, 'Haptic feedback');
    await tester.ensureVisible(switchTile);
    await tester.pumpAndSettle();
    await tester.tap(switchTile);
    await tester.pumpAndSettle();

    expect(container.read(hapticsEnabledProvider), isFalse);
    expect(AppHaptics.enabled, isFalse);
  });
}
