import '../database/models.dart';
import 'week_calendar.dart';

/// How [ScheduleNormalizer] repaired a stored week.
enum ScheduleFixStrategy {
  /// Stored keys were already exactly the week's 7 dateKeys, in order.
  none,

  /// Stored list had 7 entries whose keys drifted from the canonical
  /// week: entries kept their positions (and every value); only each
  /// entry's dateKey was replaced by the canonical key for its index.
  relabel,

  /// Stored list had a length other than 7: entries were merged by
  /// dateKey (first occurrence wins), out-of-week keys dropped and
  /// missing dates filled with defaults.
  merge,
}

/// Outcome of normalizing one stored week.
class ScheduleNormalization {
  /// The canonical week: exactly the 7 dateKeys (Sun..Sat) in order.
  /// Always fresh [DailySchedule] copies — never the stored objects.
  final List<DailySchedule> days;

  /// True when the stored list differed from the canonical week.
  final bool changed;

  final ScheduleFixStrategy strategy;

  /// Entries whose dateKey was replaced by the canonical key at their
  /// index ([ScheduleFixStrategy.relabel] only).
  final int relabeledCount;

  /// Duplicate in-week entries dropped ([ScheduleFixStrategy.merge]).
  final int duplicatesDropped;

  /// Out-of-week entries dropped ([ScheduleFixStrategy.merge]).
  final int outOfWeekDropped;

  /// Missing dates filled with defaults ([ScheduleFixStrategy.merge]).
  final int filledCount;

  const ScheduleNormalization({
    required this.days,
    required this.changed,
    required this.strategy,
    this.relabeledCount = 0,
    this.duplicatesDropped = 0,
    this.outOfWeekDropped = 0,
    this.filledCount = 0,
  });

  /// Technical one-liner for the diagnostics log.
  String get detail => switch (strategy) {
        ScheduleFixStrategy.none => 'already canonical',
        ScheduleFixStrategy.relabel =>
          'positional relabel ($relabeledCount keys corrected)',
        ScheduleFixStrategy.merge =>
          'merge: $duplicatesDropped duplicates dropped, '
              '$outOfWeekDropped out-of-week dropped, $filledCount filled',
      };
}

/// v27.10: guarantees a stored week is exactly its 7 canonical dates.
///
/// Why this exists: a corrupted stored week (dateKeys drifted from the
/// week's real dates — e.g. Thursday twice, Saturday unreachable) used
/// to render verbatim forever, because nothing validated the stored
/// list against the week it claims to describe. Normalization is pure
/// and value-preserving:
///
/// - A list that is already canonical passes through untouched.
/// - Mohamed's confirmed field case — 7 entries, positionally correct,
///   only the dateKeys wrong from some entry on — is repaired by
///   POSITIONAL RELABEL: values stay at their index, only the key is
///   corrected. (Merging by key would move Friday's values onto
///   Thursday and destroy the week he actually set.)
/// - Any other length falls back to a first-wins merge by dateKey, so
///   the earliest stored value for a date is kept, out-of-week entries
///   are dropped, and gaps are filled with the same defaults the
///   fresh-week path uses (constructor defaults + the settings' default
///   break minutes).
class ScheduleNormalizer {
  const ScheduleNormalizer._();

  /// The 7 canonical dateKeys (Sun..Sat) of the week starting at
  /// [weekStartKey].
  static List<String> canonicalKeys(String weekStartKey) =>
      WeekCalendar.weekDays(WeekCalendar.parseDateKey(weekStartKey))
          .map(WeekCalendar.dateKey)
          .toList();

  /// True when [stored] is already exactly [canonicalKeys], in order.
  static bool hasCanonicalKeys(
      String weekStartKey, List<DailySchedule> stored) {
    final canonical = canonicalKeys(weekStartKey);
    if (stored.length != canonical.length) return false;
    for (var i = 0; i < canonical.length; i++) {
      if (stored[i].dateKey != canonical[i]) return false;
    }
    return true;
  }

  static ScheduleNormalization normalizeWeek({
    required String weekStartKey,
    required List<DailySchedule> stored,
    required int defaultBreakMinutes,
  }) {
    final canonical = canonicalKeys(weekStartKey);

    // Already canonical: pass the values through (as fresh copies, so
    // callers can never mutate the stored Hive objects through us).
    if (hasCanonicalKeys(weekStartKey, stored)) {
      return ScheduleNormalization(
        days: [for (final d in stored) _copy(d)],
        changed: false,
        strategy: ScheduleFixStrategy.none,
      );
    }

    // Primary case: 7 entries, keys drifted. The entries are
    // positionally the week's days — only their keys are wrong.
    if (stored.length == 7) {
      var relabeled = 0;
      final days = <DailySchedule>[];
      for (var i = 0; i < 7; i++) {
        if (stored[i].dateKey != canonical[i]) relabeled++;
        days.add(_copy(stored[i], dateKey: canonical[i]));
      }
      return ScheduleNormalization(
        days: days,
        changed: true,
        strategy: ScheduleFixStrategy.relabel,
        relabeledCount: relabeled,
      );
    }

    // Fallback: merge by dateKey, FIRST occurrence wins; drop
    // out-of-week keys; fill missing dates with defaults.
    final inWeek = canonical.toSet();
    final byKey = <String, DailySchedule>{};
    var duplicates = 0;
    var outOfWeek = 0;
    for (final d in stored) {
      if (!inWeek.contains(d.dateKey)) {
        outOfWeek++;
      } else if (byKey.containsKey(d.dateKey)) {
        duplicates++;
      } else {
        byKey[d.dateKey] = d;
      }
    }
    var filled = 0;
    final days = <DailySchedule>[];
    for (final key in canonical) {
      final hit = byKey[key];
      if (hit != null) {
        days.add(_copy(hit));
      } else {
        filled++;
        days.add(DailySchedule(
          dateKey: key,
          breakDurationMinutes: defaultBreakMinutes,
        ));
      }
    }
    return ScheduleNormalization(
      days: days,
      changed: true,
      strategy: ScheduleFixStrategy.merge,
      duplicatesDropped: duplicates,
      outOfWeekDropped: outOfWeek,
      filledCount: filled,
    );
  }

  static DailySchedule _copy(DailySchedule d, {String? dateKey}) =>
      DailySchedule(
        dateKey: dateKey ?? d.dateKey,
        isWorkingDay: d.isWorkingDay,
        startMinutes: d.startMinutes,
        endMinutes: d.endMinutes,
        breakDurationMinutes: d.breakDurationMinutes,
        notes: d.notes,
        // v27.12: break blocks must survive normalization, or a
        // repaired week would silently lose the user's break marks.
        breakHourStarts: List.of(d.breakHourStarts),
      );
}
