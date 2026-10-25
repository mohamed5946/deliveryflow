import '../database/models.dart';
import 'week_calendar.dart';

/// v27.12 Home hour blocks: pure logic over a [DailySchedule], kept
/// separate from widgets so it is unit-testable under any timezone.
///
/// A work day renders as one full-width block per work HOUR,
/// END-EXCLUSIVE: 8:00–11:00 is blocks 8, 9, 10 (no 11 block);
/// 11:00–22:00 is 11 blocks (11..21, no 22 block). Overnight shifts
/// follow the existing schedule convention (end <= start means the
/// end is next day, i.e. end + 1440) — 22:00–02:00 is blocks
/// 22, 23, 0, 1, stored internally as extended starts
/// 1320, 1380, 1440, 1500 so a post-midnight break hour can never
/// collide with a morning hour of the same day.
///
/// Break positions are stored on [DailySchedule.breakHourStarts] as
/// those same extended start-minutes. The legacy
/// [DailySchedule.breakDurationMinutes] is NOT touched by any of this:
/// it still applies (and is still displayed) for days where no block
/// has been marked as a break, and it is never zeroed or overwritten
/// when blocks are toggled — once blocks exist they ARE the break
/// record, so the legacy minutes stop being subtracted to avoid
/// double-counting the same break.
enum HourBlockState {
  /// A work hour already finished (past day, or earlier today).
  worked,

  /// The work hour containing now (today only).
  current,

  /// A work hour still to come (future day, or later today).
  upcoming,

  /// A break hour — counts as neither worked nor remaining.
  onBreak,
}

/// Effective (possibly next-day) end of [day] in minutes, following
/// the existing schedule convention: end <= start means overnight.
int effectiveEndMinutes(DailySchedule day) {
  if (day.endMinutes <= day.startMinutes) return day.endMinutes + 24 * 60;
  return day.endMinutes;
}

/// End-exclusive block starts for [day] (extended minutes, see the
/// file doc). Empty for a day off. A day whose gross span is 0 or
/// negative can only arise from corrupt data; it yields no blocks
/// rather than an unbounded list.
List<int> hourBlockStarts(DailySchedule day) {
  if (!day.isWorkingDay) return const [];
  final end = effectiveEndMinutes(day);
  final gross = end - day.startMinutes;
  if (gross <= 0 || gross > 24 * 60) return const [];
  // Only full hours become blocks: a block must fit entirely inside
  // the shift, so a trailing partial hour (e.g. 11:30–22:00) renders
  // no block for its last 30 minutes. Hour-aligned shifts — the
  // normal case — are unaffected and stay exactly end-exclusive.
  return [
    for (var s = day.startMinutes; s + 60 <= end; s += 60) s,
  ];
}

/// The subset of [day]'s blocks currently marked as break, as
/// extended start-minutes. Stale entries (outside the current
/// start–end span, e.g. after hours were removed) are ignored here;
/// saves prune them (see [removeLastHour] / [toggleBreakHour]).
Set<int> breakBlockStarts(DailySchedule day) {
  final blocks = hourBlockStarts(day).toSet();
  return day.breakHourStarts.where(blocks.contains).toSet();
}

/// Net work minutes for the Home summary.
///
/// - No block breaks: the legacy formula, unchanged —
///   gross − breakDurationMinutes (clamped), so old records keep
///   exactly the net they always had.
/// - Block breaks present: gross − 60 per break block. The legacy
///   minutes are NOT also subtracted (that would double-count).
/// - Day off: 0.
int blockNetMinutes(DailySchedule day) {
  if (!day.isWorkingDay) return 0;
  final gross = effectiveEndMinutes(day) - day.startMinutes;
  final breaks = breakBlockStarts(day);
  if (breaks.isEmpty) {
    return gross - day.breakDurationMinutes.clamp(0, gross);
  }
  return gross - breaks.length * 60;
}

/// Classification of one block for the summary and its colour.
///
/// - Break blocks are always [HourBlockState.onBreak].
/// - Past days: every work hour counts as worked; future days: every
///   work hour counts as upcoming (spec rule, no hour math).
/// - Today: the hour containing [now] is current, earlier extended
///   hours are worked, later ones upcoming. Extended starts make
///   overnight spill (e.g. the 01:00 block of a 22:00–02:00 shift)
///   correctly upcoming at 23:00, not "worked".
HourBlockState classifyBlock({
  required DateTime day,
  required DateTime now,
  required int blockStart,
  required bool isBreak,
}) {
  if (isBreak) return HourBlockState.onBreak;
  final dayKey = WeekCalendar.dateKey(day);
  final todayKey = WeekCalendar.dateKey(now);
  if (dayKey.compareTo(todayKey) < 0) return HourBlockState.worked;
  if (dayKey.compareTo(todayKey) > 0) return HourBlockState.upcoming;
  final nowMinutes = now.hour * 60 + now.minute;
  if (nowMinutes < blockStart) return HourBlockState.upcoming;
  if (nowMinutes < blockStart + 60) return HourBlockState.current;
  return HourBlockState.worked;
}

/// Worked vs remaining WORK hours for the Home summary. Break hours
/// count as neither, so worked + remaining always equals the number
/// of work blocks. The current hour counts as remaining (it is not
/// finished yet).
({int worked, int remaining}) summarizeBlocks({
  required DailySchedule day,
  required DateTime dayDate,
  required DateTime now,
}) {
  var worked = 0;
  var remaining = 0;
  final breaks = breakBlockStarts(day);
  for (final start in hourBlockStarts(day)) {
    final state = classifyBlock(
      day: dayDate,
      now: now,
      blockStart: start,
      isBreak: breaks.contains(start),
    );
    if (state == HourBlockState.worked) {
      worked++;
    } else if (state == HourBlockState.current ||
        state == HourBlockState.upcoming) {
      remaining++;
    }
  }
  return (worked: worked, remaining: remaining);
}

DailySchedule _copyDay(DailySchedule day,
        {int? endMinutes, List<int>? breakHourStarts}) =>
    DailySchedule(
      dateKey: day.dateKey,
      isWorkingDay: day.isWorkingDay,
      startMinutes: day.startMinutes,
      endMinutes: endMinutes ?? day.endMinutes,
      breakDurationMinutes: day.breakDurationMinutes,
      notes: day.notes,
      breakHourStarts: breakHourStarts ?? List.of(day.breakHourStarts),
    );

/// Toggle [blockStart] between work and break. The block stays in its
/// position, the day's end time is unchanged, and the legacy break
/// duration is untouched. Returns the day unchanged when
/// [blockStart] is not one of its blocks.
DailySchedule toggleBreakHour(DailySchedule day, int blockStart) {
  final blocks = hourBlockStarts(day).toSet();
  if (!blocks.contains(blockStart)) return day;
  final breaks = breakBlockStarts(day).toList();
  if (breaks.contains(blockStart)) {
    breaks.remove(blockStart);
  } else {
    breaks.add(blockStart);
  }
  breaks.sort();
  return _copyDay(day, breakHourStarts: breaks);
}

/// Append one work hour at the end (endMinutes + 60, wrapping past
/// midnight back into 0..1439 storage — the overnight convention
/// re-derives the same span). No-op when the day already spans a
/// full 24 hours.
DailySchedule addHour(DailySchedule day) {
  if (!day.isWorkingDay) return day;
  final end = effectiveEndMinutes(day);
  if (end - day.startMinutes >= 24 * 60) return day;
  final nextEnd = end + 60;
  return _copyDay(day, endMinutes: nextEnd % (24 * 60));
}

/// Remove the last hour (endMinutes − 60). Returns null when the day
/// would drop below one hour — the end never goes below (or onto)
/// the start. A break mark on the removed hour is pruned with it.
DailySchedule? removeLastHour(DailySchedule day) {
  if (!day.isWorkingDay) return null;
  final end = effectiveEndMinutes(day);
  if (end - day.startMinutes <= 60) return null;
  final removedStart = end - 60;
  final breaks = breakBlockStarts(day).toList()..remove(removedStart);
  return _copyDay(day,
      endMinutes: (end - 60) % (24 * 60), breakHourStarts: breaks);
}
