/// Centralized, deterministic Sunday-to-Saturday week calendar logic.
///
/// All calculations are pure functions over [DateTime] so they are easy to
/// unit test, including month/year boundaries, leap years and DST-safe day
/// arithmetic (days are compared by calendar date, never by 24h durations).
///
/// v27.11: ALL day stepping goes through the [DateTime] CONSTRUCTOR
/// (`DateTime(y, m, d + n)` — pure wall-clock calendar arithmetic).
/// `DateTime.add(Duration(days: n))` is ABSOLUTE 24h arithmetic: across
/// Egypt's DST fall-back (Thu 2026-10-29 24:00 EEST, clocks back an
/// hour) it generated the week Sun 2026-10-25..Sat 2026-10-31 as
/// [25, 26, 27, 28, 29, 29, 30] — a duplicate Thursday and no Saturday
/// at all. That drifted key list is what corrupted Mohamed's stored
/// schedule week (and, via ScheduleNormalizer.canonicalKeys, hid the
/// corruption from the v27.10 self-heal, which compared against the
/// same broken generator). Never reintroduce Duration-based day math
/// here; test/week_calendar_dst_test.dart locks this in.
class WeekCalendar {
  const WeekCalendar._();

  /// Strips the time component, keeping the date in the local calendar.
  static DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  /// Stable storage key for a calendar date: `yyyy-MM-dd`.
  static String dateKey(DateTime dt) {
    final d = dateOnly(dt);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// Parses a [dateKey] back into a local-midnight [DateTime].
  static DateTime parseDateKey(String key) {
    final parts = key.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// The Sunday starting the work week that contains [date].
  /// Dart: Monday=1 ... Sunday=7.
  static DateTime weekStart(DateTime date) {
    final d = dateOnly(date);
    final offset = d.weekday % 7; // Sunday -> 0, Monday -> 1, ...
    // Constructor arithmetic: stepping back over a DST transition day
    // must land on the calendar date, not 23/25 hours earlier.
    return DateTime(d.year, d.month, d.day - offset);
  }

  /// The Saturday ending the work week that contains [date].
  static DateTime weekEnd(DateTime date) => addDays(weekStart(date), 6);

  /// The 7 calendar days (Sunday..Saturday) of the week containing [date].
  static List<DateTime> weekDays(DateTime date) {
    final start = weekStart(date);
    return List.generate(
        7, (i) => DateTime(start.year, start.month, start.day + i));
  }

  /// The Sunday starting the *next* work week after the week containing [date].
  static DateTime nextWeekStart(DateTime date) =>
      addDays(weekStart(date), 7);

  /// True when [a] and [b] fall on the same calendar date.
  static bool isSameDay(DateTime a, DateTime b) =>
      dateKey(a) == dateKey(b);

  /// True when both dates belong to the same Sunday–Saturday work week.
  static bool isSameWeek(DateTime a, DateTime b) =>
      isSameDay(weekStart(a), weekStart(b));

  /// Number of whole calendar days from [from] to [to] (can be negative).
  ///
  /// Computed on UTC midnights built from the calendar fields, so a
  /// 23- or 25-hour local day can never skew the count (a local
  /// difference across the fall-back day measures 47/49 hours and
  /// truncates to the wrong whole-day count).
  static int daysBetween(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  /// Adds [days] calendar days (may be negative), DST-safe: the step
  /// goes through the [DateTime] constructor, not a 24h duration.
  static DateTime addDays(DateTime date, int days) {
    final d = dateOnly(date);
    return DateTime(d.year, d.month, d.day + days);
  }

  /// Computes net working minutes for a shift.
  ///
  /// [startMinutes] / [endMinutes] are minutes since midnight.
  /// Overnight shifts (end <= start) are treated as ending the next day.
  /// Returns a non-negative value; break minutes are clamped to the shift.
  static int netShiftMinutes(
      int startMinutes, int endMinutes, int breakMinutes) {
    var end = endMinutes;
    if (end <= startMinutes) end += 24 * 60; // overnight
    final gross = end - startMinutes;
    final brk = breakMinutes.clamp(0, gross);
    return gross - brk;
  }

  /// Formats minutes as `H:MM`, e.g. 90 -> `1:30`.
  static String formatMinutes(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  /// Mockup style: "5h 32m".
  static String formatHoursMinutes(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h}h ${m}m';
  }

  /// Formats a double hour value with one decimal, e.g. 7.5.
  static String formatHours(double hours) => hours.toStringAsFixed(1);

  /// Compact km formatting: 12.5 / 12 (no trailing .0).
  static String formatKm(double km) {
    final s = km.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
}
