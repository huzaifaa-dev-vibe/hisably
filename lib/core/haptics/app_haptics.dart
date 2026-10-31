import 'package:flutter/services.dart';

/// Central haptic vocabulary so feedback stays consistent and restrained.
///
/// All calls are no-ops in widget tests (platform channels are mocked), and
/// this is the ONLY place allowed to call HapticFeedback. Respect the
/// user-facing toggle (Profile → Feedback → Haptics) via [enabled]; the
/// flag is wired to SharedPreferences by the settings providers.
abstract final class AppHaptics {
  /// Wired to the Profile toggle at bootstrap and on change.
  static bool enabled = true;

  static void _vibrate(void Function() fn) {
    if (enabled) fn();
  }

  /// Keypad taps, chip selection, light UI touches.
  static void tap() => _vibrate(HapticFeedback.selectionClick);

  /// Committing a choice: In/Out direction, saving.
  static void confirm() => _vibrate(HapticFeedback.mediumImpact);

  /// Successful save animation peak.
  static void success() => _vibrate(HapticFeedback.heavyImpact);

  /// Validation failure / blocked action.
  static void warn() => _vibrate(HapticFeedback.vibrate);
}
