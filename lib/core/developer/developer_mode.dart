/// Developer Mode gate (v27.4).
///
/// The diagnostics tools (notification tests, diagnostics log viewer,
/// notification status card) are for the developer only — Mohamed's
/// other users should never see them. A single settings entry ("نسخة
/// المطور") asks for this password ONCE; a correct entry persists
/// `UserSettings.developerModeUnlocked`, so the tools stay visible on
/// that phone across restarts until he turns the mode off again.
///
/// The value lives here and ONLY here (plus the settings flag). Never
/// log it, never print it, never put it in a diagnostics entry.
class DeveloperMode {
  DeveloperMode._();

  /// The unlock password. Deliberately a plain const: the gate is a
  /// courtesy lock against casual users, not a security boundary.
  static const String password = '5184';

  /// True when [input] matches the unlock password (whitespace around
  /// the typed value is ignored).
  static bool accepts(String input) => input.trim() == password;
}
