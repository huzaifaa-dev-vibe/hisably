import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/haptics/app_haptics.dart';
import '../core/theme/theme_spec.dart';
import 'providers.dart';

/// Which theme the user picked on the Profile page. Stored as the spec id;
/// `system` follows the OS light/dark mode.
final themeSettingProvider =
    NotifierProvider<ThemeSetting, String>(ThemeSetting.new);

class ThemeSetting extends Notifier<String> {
  static const _key = 'theme_id';

  @override
  String build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_key);
    return saved != null && AppThemes.byId(saved).id == saved
        ? saved
        : AppThemes.system.id;
  }

  Future<void> set(String id) async {
    if (AppThemes.byId(id).id != id) return;
    state = id;
    await ref.read(sharedPreferencesProvider).setString(_key, id);
  }
}

/// The concrete spec the app should render with right now: resolves the
/// special `system` entry against the platform brightness and rebuilds
/// automatically when the user changes either the setting or the OS mode.
final resolvedSpecProvider = Provider<AppThemeSpec>((ref) {
  final id = ref.watch(themeSettingProvider);
  final platformBrightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  return AppThemes.resolve(id, platformBrightness);
});

/// Whether the device should buzz on interactions (Profile → Feedback).
final hapticsEnabledProvider =
    NotifierProvider<HapticsEnabled, bool>(HapticsEnabled.new);

class HapticsEnabled extends Notifier<bool> {
  static const _key = 'haptics_enabled';

  @override
  bool build() {
    final saved = ref.watch(sharedPreferencesProvider).getBool(_key);
    final value = saved ?? true;
    // Keep the static haptics gate in sync from this single place.
    AppHaptics.enabled = value;
    return value;
  }

  Future<void> set(bool value) async {
    state = value;
    AppHaptics.enabled = value;
    await ref.read(sharedPreferencesProvider).setBool(_key, value);
  }
}

/// The user's display name shown on the Profile page.
final displayNameProvider =
    NotifierProvider<DisplayName, String>(DisplayName.new);

class DisplayName extends Notifier<String> {
  static const _key = 'display_name';
  static const fallback = 'Hisably user';

  @override
  String build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_key);
    return (saved == null || saved.trim().isEmpty) ? fallback : saved.trim();
  }

  Future<void> set(String value) async {
    final v = value.trim();
    state = v.isEmpty ? fallback : v;
    await ref.read(sharedPreferencesProvider).setString(_key, v);
  }
}
