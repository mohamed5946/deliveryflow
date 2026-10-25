import 'package:flutter/material.dart';

/// How times are rendered in the v27.12 day-hours feature (Home hour
/// blocks + schedule rows) and anywhere that opts into it.
///
/// Stored on [UserSettings.timeFormat] as an int so Hive stays simple:
/// 0 = system (the pre-v27.12 behaviour — `TimeOfDay.format`, i.e. the
/// device's own 12h/24h setting), 1 = 24-hour, 2 = 12-hour.
///
/// Default is [system] precisely so existing users see NO change until
/// they pick a format in Profile: the old code rendered every time via
/// `TimeOfDay.format(context)`, and that path is untouched for mode 0.
enum TimeFormatMode { system, h24, h12 }

TimeFormatMode timeFormatModeFromStored(int? stored) => switch (stored) {
      1 => TimeFormatMode.h24,
      2 => TimeFormatMode.h12,
      _ => TimeFormatMode.system,
    };

int timeFormatModeToStored(TimeFormatMode mode) => switch (mode) {
      TimeFormatMode.system => 0,
      TimeFormatMode.h24 => 1,
      TimeFormatMode.h12 => 2,
    };

/// Pure 12h/24h rendering of minutes-since-midnight. [minutes] is
/// normalized mod 1440, so extended (overnight) block starts such as
/// 1500 (01:00 next day) render as their wall-clock hour.
///
/// 12-hour Arabic markers follow Egyptian usage: ص (morning) / م
/// (evening). English markers are AM/PM.
String formatMinutes(int minutes, TimeFormatMode mode,
    {bool arabic = false}) {
  final m = minutes % (24 * 60);
  final h = m ~/ 60;
  final min = m % 60;
  final mm = min.toString().padLeft(2, '0');
  switch (mode) {
    case TimeFormatMode.h24:
      return '${h.toString().padLeft(2, '0')}:$mm';
    case TimeFormatMode.h12:
      final h12 = h % 12 == 0 ? 12 : h % 12;
      final suffix = arabic ? (h < 12 ? ' ص' : ' م') : (h < 12 ? ' AM' : ' PM');
      return '$h12:$mm$suffix';
    case TimeFormatMode.system:
      // No context here, so no device format is available; callers
      // that need the system format must use [formatMinutesWithContext].
      // Fall back to 24-hour rather than guessing a locale convention.
      return '${h.toString().padLeft(2, '0')}:$mm';
  }
}

/// Context-aware rendering: mode [system] keeps the exact pre-v27.12
/// behaviour (`TimeOfDay.format`, device setting + locale); explicit
/// 12h/24h modes use the pure formatter above.
String formatMinutesWithContext(
    BuildContext context, int minutes, TimeFormatMode mode,
    {bool arabic = false}) {
  if (mode == TimeFormatMode.system) {
    final m = minutes % (24 * 60);
    return TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);
  }
  return formatMinutes(minutes, mode, arabic: arabic);
}
