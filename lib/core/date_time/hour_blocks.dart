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
///
/// v27.19 TRUE DELETE: Delete and Break are finally different
/// stored changes. Break still records the hour in breakHourStarts.
/// Delete removes the hour from the day:
/// - Edge (first/last visible block): start/end shrink past it, so
///   the range itself no longer contains it; it is NOT recorded in
///   [DailySchedule.deletedHourStarts] (recording it too would
///   double-count the shrink in every total).
/// - Middle: the hour is recorded in deletedHourStarts and skipped
///   by [hourBlockStarts] — neighbours keep their exact times, no
///   hour ever shifts to fill the gap. A deleted hour is not a
///   block at all: it counts in no summary, no net total, and no
///   protection set, and the Assign picker offers it again (picking
///   it clears the deletion and restores it as a work block).
/// - Last remaining block: the day becomes a day off (start == end
///   would mean a 24h overnight shift under the end <= start
///   convention, so it is never used as "empty").
/// Stale deleted entries (outside the current span, e.g. after the
/// schedule screen moved start/end) are ignored by
/// [deletedBlockStarts] and pruned by [deleteHour]/[assignHour].
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

/// Full-hour starts of [day]'s span (extended minutes, see the file
/// doc), BEFORE deleted hours are removed. Empty for a day off. A
/// day whose gross span is 0 or negative can only arise from corrupt
/// data; it yields no blocks rather than an unbounded list.
List<int> spanBlockStarts(DailySchedule day) {
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

/// Deleted hours of [day] that still lie inside its span, as
/// extended start-minutes. Stale entries outside the span are
/// ignored here; saves prune them (see [deleteHour]/[assignHour]).
Set<int> deletedBlockStarts(DailySchedule day) {
  final span = spanBlockStarts(day).toSet();
  return day.deletedHourStarts.where(span.contains).toSet();
}

/// End-exclusive block starts for [day] (extended minutes): the
/// span's blocks MINUS deleted hours. A deleted hour is gone from
/// the day — it renders nowhere, counts in no summary, and is
/// offered again by the Assign picker. Empty for a day off.
List<int> hourBlockStarts(DailySchedule day) {
  final deleted = deletedBlockStarts(day);
  return [
    for (final s in spanBlockStarts(day))
      if (!deleted.contains(s)) s,
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
/// - Deleted hours are subtracted first: a deleted hour is no
///   longer part of the shift at all (v27.19).
/// - No block breaks: the legacy formula, unchanged —
///   gross − breakDurationMinutes (clamped), so old records keep
///   exactly the net they always had.
/// - Block breaks present: gross − 60 per break block. The legacy
///   minutes are NOT also subtracted (that would double-count).
/// - Day off: 0.
int blockNetMinutes(DailySchedule day) {
  if (!day.isWorkingDay) return 0;
  final gross = effectiveEndMinutes(day) - day.startMinutes;
  final deleted = deletedBlockStarts(day).length;
  final breaks = breakBlockStarts(day);
  if (breaks.isEmpty) {
    return (gross - deleted * 60 - day.breakDurationMinutes.clamp(0, gross))
        .clamp(0, gross);
  }
  return (gross - deleted * 60 - breaks.length * 60).clamp(0, gross);
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
        {int? startMinutes,
        int? endMinutes,
        bool? isWorkingDay,
        List<int>? breakHourStarts,
        List<int>? deletedHourStarts}) =>
    DailySchedule(
      dateKey: day.dateKey,
      isWorkingDay: isWorkingDay ?? day.isWorkingDay,
      startMinutes: startMinutes ?? day.startMinutes,
      endMinutes: endMinutes ?? day.endMinutes,
      breakDurationMinutes: day.breakDurationMinutes,
      notes: day.notes,
      breakHourStarts: breakHourStarts ?? List.of(day.breakHourStarts),
      deletedHourStarts:
          deletedHourStarts ?? List.of(day.deletedHourStarts),
    );

/// [day] with break and deleted marks pruned to its current span
/// and visible blocks (used after a range shrink, where marks on
/// hours that left the span must not linger in storage).
DailySchedule _pruneMarksToSpan(DailySchedule day) {
  final breaks = breakBlockStarts(day).toList()..sort();
  final deleted = deletedBlockStarts(day).toList()..sort();
  return _copyDay(day,
      breakHourStarts: breaks, deletedHourStarts: deleted);
}

/// Wall-clock hour (0..23) of an extended block start.
int _wallHour(int extendedStart) => (extendedStart % (24 * 60)) ~/ 60;

/// v27.13 Assign picker: the wall-clock hours of [day] that are NOT
/// already a block, so picking one can never duplicate a block.
///
/// - No day / day off: all 24 hours are available (picking one
///   creates a one-hour shift, see [assignHour]).
/// - Working day: every block's wall hour is excluded — work blocks
///   AND break blocks alike. A break hour is already a block in the
///   shift, so it is not "available" as a new block; restoring it is
///   the swipe-restore path, not Assign. A protected (order-bearing)
///   hour is a work block, so it is excluded here by the same rule.
/// - v27.19: a DELETED hour is not a block, so it IS offered again
///   (hourBlockStarts already excludes it). Picking it restores it
///   as a work block and clears the deletion (see [assignHour]).
/// - Partial hours: only full-hour blocks exclude their wall hour, so
///   a trailing partial hour's wall hour stays available (picking it
///   extends the end past it, see [assignHour]).
List<int> availableHoursForAssign(DailySchedule? day) {
  if (day == null || !day.isWorkingDay) {
    return [for (var h = 0; h < 24; h++) h];
  }
  final taken = {for (final s in hourBlockStarts(day)) _wallHour(s)};
  return [
    for (var h = 0; h < 24; h++)
      if (!taken.contains(h)) h
  ];
}

/// v27.13 Assign: add [hour] (wall-clock 0..23) as a NEW WORK block.
///
/// The model stays start/end + breakHourStarts; no second
/// representation is introduced:
/// - Inside-range pick: unreachable from the picker (the hour would
///   already be a block) — guarded to a no-op — except a trailing
///   partial hour, whose wall hour is available: the end extends to
///   the end of that hour and it becomes a work block, no breaks.
/// - Outside, after the end: end extends to hour+60 and every
///   intermediate full hour between the old end and the picked hour
///   becomes a break, so the header stays coherent (e.g. 8–11 +
///   14:00 => ends 15:00, work 8,9,10,14, break 11,12,13).
/// - Outside, before the start: symmetric — start moves back to the
///   hour, intermediate hours between it and the old start become
///   breaks, and old break marks are carried over by wall hour (the
///   new start re-anchors block positions, so a wall-hour carry is
///   the only mapping that survives a non-hour-aligned old start).
/// - No day / day off: a one-hour working shift at that hour
///   (isWorkingDay flips to true for a day off).
/// - Overnight: the candidate extended start nearest the shift
///   interval wins (e.g. a 22:00–02:00 shift picking 03:00 extends
///   to 04:00, not backwards to 03:00 the previous morning), and
///   stored start/end wrap mod 1440 per the overnight convention.
/// Returns [day] unchanged for an already-blocked hour, an invalid
/// hour, or a day that already spans 24 hours.
DailySchedule assignHour(DailySchedule? day, int hour, String dateKey) {
  if (hour < 0 || hour > 23) {
    throw ArgumentError.value(hour, 'hour', 'must be 0..23');
  }
  if (day == null || !day.isWorkingDay) {
    return DailySchedule(
      dateKey: day?.dateKey ?? dateKey,
      isWorkingDay: true,
      startMinutes: hour * 60,
      endMinutes: (hour + 1) * 60 % (24 * 60),
      breakDurationMinutes: 0,
    );
  }
  final start = day.startMinutes;
  final end = effectiveEndMinutes(day);
  if (end - start >= 24 * 60) return day;
  if ({for (final s in hourBlockStarts(day)) _wallHour(s)}.contains(hour)) {
    return day;
  }
  // Nearest extended start for this wall hour to the shift interval.
  var best = hour * 60;
  var bestDist = 1 << 30;
  for (var k = -1; k <= 2; k++) {
    final c = hour * 60 + k * 24 * 60;
    final dist = c < start ? start - c : (c >= end ? c - end : 0);
    if (dist < bestDist) {
      bestDist = dist;
      best = c;
    }
  }
  if (best >= start && best < end) {
    // v27.19: a deleted hour inside the span is NOT a block, so the
    // picker offers it — picking it restores it as a work block by
    // clearing the deletion (and any stray break mark), with the
    // range untouched. Anything else inside that is not a deleted
    // hour would already be a block (the wall-hour guard above), so
    // it is a no-op — except a trailing partial hour, which fits
    // only once the end moves past it.
    if (deletedBlockStarts(day).contains(best)) {
      final deleted = deletedBlockStarts(day).toList()..remove(best);
      final breaks = breakBlockStarts(day).toList()..remove(best);
      return _copyDay(day,
          breakHourStarts: breaks, deletedHourStarts: deleted);
    }
    if (best + 60 <= end) return day;
    return _pruneMarksToSpan(
        _copyDay(day, endMinutes: (best + 60) % (24 * 60)));
  }
  if (best < start) {
    final newEnd = end;
    final newBlocks = [
      for (var s = best; s + 60 <= newEnd; s += 60) s,
    ];
    final oldBreakWalls = {
      for (final b in breakBlockStarts(day)) _wallHour(b),
    };
    // v27.19: intermediate hours that are deleted stay deleted —
    // they must not be resurrected as breaks by the extension.
    final deletedWalls = {
      for (final d in deletedBlockStarts(day)) _wallHour(d),
    };
    final breaks = {
      for (final s in newBlocks)
        if ((oldBreakWalls.contains(_wallHour(s)) ||
                (s >= best + 60 && s < start)) &&
            !deletedWalls.contains(_wallHour(s)))
          s,
    }.toList()
      ..sort();
    return _pruneMarksToSpan(_copyDay(day,
        startMinutes: best % (24 * 60),
        endMinutes: newEnd % (24 * 60),
        breakHourStarts: breaks));
  }
  // best >= end: extend the end, intermediate blocks become breaks
  // (except deleted ones, which stay deleted — see above).
  final newEnd = best + 60;
  final deletedWalls = {
    for (final d in deletedBlockStarts(day)) _wallHour(d),
  };
  final breaks = {
    ...breakBlockStarts(day),
    for (var s = start; s + 60 <= newEnd; s += 60)
      if (s >= end && s < best && !deletedWalls.contains(_wallHour(s))) s,
  }.toList()
    ..sort();
  return _pruneMarksToSpan(
      _copyDay(day, endMinutes: newEnd % (24 * 60), breakHourStarts: breaks));
}

/// v27.19 TRUE DELETE: remove [blockStart] from [day] completely.
///
/// This is NOT [toggleBreakHour]: the hour stops being a block at
/// all — it renders nowhere, counts in no summary or net total, and
/// is offered again by the Assign picker.
///
/// - Not a visible block (already deleted, or never a block):
///   unchanged.
/// - Only visible block: the day becomes a day off (break and
///   deleted marks cleared; start/end kept so the schedule screen
///   still shows the old times if the day is re-enabled there).
/// - First visible block: start moves past it.
/// - Last visible block: end moves back to it (dropping a trailing
///   partial hour with it, if the span had one).
/// - Middle block: recorded in deletedHourStarts; every other block
///   keeps its exact time — nothing shifts to fill the gap.
/// A break mark on the deleted hour is always removed with it:
/// deleting a break block removes it, it never restores it.
/// The caller (dashboard) owns the Yes/No confirmation and the
/// order-protection gate; this function is pure.
DailySchedule deleteHour(DailySchedule day, int blockStart) {
  if (!day.isWorkingDay) return day;
  final visible = hourBlockStarts(day);
  if (!visible.contains(blockStart)) return day;
  final breaks = breakBlockStarts(day).toList()..remove(blockStart);
  if (visible.length == 1) {
    return _copyDay(day,
        isWorkingDay: false, breakHourStarts: [], deletedHourStarts: []);
  }
  if (blockStart == visible.first) {
    return _pruneMarksToSpan(_copyDay(day,
        startMinutes: (blockStart + 60) % (24 * 60),
        breakHourStarts: breaks));
  }
  if (blockStart == visible.last) {
    return _pruneMarksToSpan(_copyDay(day,
        endMinutes: blockStart % (24 * 60), breakHourStarts: breaks));
  }
  final deleted = {...deletedBlockStarts(day), blockStart}.toList()..sort();
  return _copyDay(day,
      breakHourStarts: breaks, deletedHourStarts: deleted);
}

/// v27.13 protection grouping (pure): the extended block starts of
/// [day] that contain at least one REAL order entry.
///
/// Matching is by wall-clock hour: an entry's local timestamp hour
/// against a block's wall hour (block start % 1440 / 60), so
/// overnight blocks (e.g. 1500 = 01:00 next day) match 01:00 orders.
/// countOnly entries are EXCLUDED — they carry no real timestamp
/// (born at local noon) and must never protect an hour.
Set<int> protectedBlockStarts({
  required DailySchedule day,
  required Iterable<OrderEntry> entries,
}) {
  final byWallHour = <int, int>{};
  for (final s in hourBlockStarts(day)) {
    byWallHour[_wallHour(s)] = s;
  }
  final protected = <int>{};
  for (final e in entries) {
    if (e.countOnly) continue;
    final hour = DateTime.fromMillisecondsSinceEpoch(e.timestampMillis).hour;
    final block = byWallHour[hour];
    if (block != null) protected.add(block);
  }
  return protected;
}

/// Toggle [blockStart] between work and break. The block stays in its
/// position, the day's end time is unchanged, and the legacy break
/// duration is untouched. Returns the day unchanged when
/// [blockStart] is not one of its blocks — a deleted hour is not a
/// block, so it can never be toggled (Assign restores it instead).
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
/// the start. A break mark on the removed hour is pruned with it,
/// as is a deleted mark that falls outside the shrunken span.
DailySchedule? removeLastHour(DailySchedule day) {
  if (!day.isWorkingDay) return null;
  final end = effectiveEndMinutes(day);
  if (end - day.startMinutes <= 60) return null;
  final removedStart = end - 60;
  final breaks = breakBlockStarts(day).toList()..remove(removedStart);
  return _pruneMarksToSpan(_copyDay(day,
      endMinutes: (end - 60) % (24 * 60), breakHourStarts: breaks));
}
