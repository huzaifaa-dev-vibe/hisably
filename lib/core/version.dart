/// Single source of truth for the human-readable app version.
/// Keep in sync with `version:` in pubspec.yaml (checked by a test).
abstract final class AppVersion {
  static const String string = '0.90.12';
  static const int build = 1;
}
