import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_spec.dart';
import 'data/settings.dart';

/// Root widget. The active theme comes from the Profile-page setting
/// (themeSettingProvider): "system" follows the OS light/dark mode via
/// Flutter's own ThemeMode, any explicit theme is rendered as-is.
class HisablyApp extends ConsumerWidget {
  const HisablyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setting = ref.watch(themeSettingProvider);
    final spec = ref.watch(resolvedSpecProvider);

    final ThemeData theme;
    final ThemeData? darkTheme;
    final ThemeMode mode;
    if (setting == AppThemes.system.id) {
      theme = AppTheme.fromSpec(AppThemes.porcelain);
      darkTheme = AppTheme.fromSpec(AppThemes.obsidian);
      mode = ThemeMode.system;
    } else {
      theme = AppTheme.fromSpec(spec);
      darkTheme = theme;
      mode = spec.isDark ? ThemeMode.dark : ThemeMode.light;
    }

    return MaterialApp.router(
      title: 'Hisably',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: mode,
      routerConfig: appRouter,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
    );
  }
}
