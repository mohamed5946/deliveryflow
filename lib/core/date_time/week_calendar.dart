/// Centralized, deterministic Sunday-to-Saturday week calendar logic.
///
/// All calculations are pure functions over [DateTime] so they are easy to
/// unit test, including month/year boundaries, leap years and DST-safe day
/// arithmetic (days are compared by calendar date, never by 24h durations).
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
    return d.subtract(Duration(days: offset));
  }

  /// The Saturday ending the work week that contains [date].
  static DateTime weekEnd(DateTime date) =>
      weekStart(date).add(const Duration(days: 6));

  /// The 7 calendar days (Sunday..Saturday) of the week containing [date].
  static List<DateTime> weekDays(DateTime date) {
    final start = weekStart(date);
    return List.generate(7, (i) => start.add(Duration(days: i)));
  }

  /// The Sunday starting the *next* work week after the week containing [date].
  static DateTime nextWeekStart(DateTime date) =>
      weekStart(date).add(const Duration(days: 7));

  /// True when [a] and [b] fall on the same calendar date.
  static bool isSameDay(DateTime a, DateTime b) =>
      dateKey(a) == dateKey(b);

  /// True when both dates belong to the same Sunday–Saturday work week.
  static bool isSameWeek(DateTime a, DateTime b) =>
      isSameDay(weekStart(a), weekStart(b));

  /// Number of whole calendar days from [from] to [to] (can be negative).
  static int daysBetween(DateTime from, DateTime to) =>
      dateOnly(to).difference(dateOnly(from)).inDays;

  /// Adds [days] calendar days, DST-safe because it goes through dateOnly.
  static DateTime addDays(DateTime date, int days) =>
      dateOnly(date).add(Duration(days: days));

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

  /// Formats a double hour value with one decimal, e.g. 7.5.
  static String formatHours(double hours) => hours.toStringAsFixed(1);
}
