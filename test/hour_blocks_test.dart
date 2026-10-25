import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/date_time/hour_blocks.dart';
import 'package:deliveryflow/core/date_time/time_format.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// v27.12 Home hour blocks: generation, break math, add/remove,
/// classification at a fixed clock, 12h/24h formatting, and the
/// old-record migration (legacy break duration preserved, never
/// zeroed, and still the net when no block break exists).
void main() {
  DailySchedule day({
    int start = 11 * 60,
    int end = 22 * 60,
    int breakMinutes = 0,
    List<int>? breaks,
    bool working = true,
  }) =>
      DailySchedule(
        dateKey: '2026-10-25',
        isWorkingDay: working,
        startMinutes: start,
        endMinutes: end,
        breakDurationMinutes: breakMinutes,
        breakHourStarts: breaks,
      );

  group('hour-block generation (end-exclusive)', () {
    test('8:00-11:00 => blocks 8, 9, 10 (no 11 block)', () {
      expect(hourBlockStarts(day(start: 8 * 60, end: 11 * 60)),
          [480, 540, 600]);
    });

    test('11:00-22:00 => 11 blocks 11..21 (no 22 block)', () {
      final blocks = hourBlockStarts(day());
      expect(blocks.length, 11);
      expect(blocks.first, 660);
      expect(blocks.last, 1260);
      expect(blocks, isNot(contains(1320)));
    });

    test('overnight 22:00-02:00 handled per existing convention', () {
      expect(hourBlockStarts(day(start: 22 * 60, end: 2 * 60)),
          [1320, 1380, 1440, 1500]);
      expect(effectiveEndMinutes(day(start: 22 * 60, end: 2 * 60)), 1560);
    });

    test('day off => no blocks', () {
      expect(hourBlockStarts(day(working: false)), isEmpty);
    });
  });

  group('break toggle math', () {
    test('each break block drops net by exactly 1 hour, end unchanged', () {
      final d = day();
      expect(blockNetMinutes(d), 660);
      final one = toggleBreakHour(d, 840); // 14:00
      expect(one.endMinutes, 22 * 60);
      expect(one.breakHourStarts, [840]);
      expect(blockNetMinutes(one), 600);
      final two = toggleBreakHour(one, 900);
      expect(blockNetMinutes(two), 540);
      // Toggling back restores the hour.
      expect(blockNetMinutes(toggleBreakHour(two, 840)), 600);
      expect(blockNetMinutes(toggleBreakHour(two, 900)), 600);
    });

    test('toggling a non-block hour is a no-op', () {
      final d = day();
      expect(identical(toggleBreakHour(d, 1320), d), isTrue);
    });

    test('legacy break duration is untouched by toggles', () {
      final d = day(breakMinutes: 30);
      final toggled = toggleBreakHour(d, 840);
      expect(toggled.breakDurationMinutes, 30);
    });
  });

  group('add/remove-last-hour math', () {
    test('add appends a work hour: end +60', () {
      final added = addHour(day());
      expect(added.endMinutes, 23 * 60);
      expect(hourBlockStarts(added).length, 12);
      expect(added.breakHourStarts, isEmpty);
    });

    test('add wraps past midnight via the overnight convention', () {
      final added = addHour(day(start: 22 * 60, end: 2 * 60));
      expect(added.endMinutes, 3 * 60);
      expect(hourBlockStarts(added), [1320, 1380, 1440, 1500, 1560]);
    });

    test('remove drops the last hour: end -60, never below start', () {
      final removed = removeLastHour(day())!;
      expect(removed.endMinutes, 21 * 60);
      expect(hourBlockStarts(removed).length, 10);
      // A single-hour day cannot lose its only hour.
      expect(removeLastHour(day(start: 8 * 60, end: 9 * 60)), isNull);
    });

    test('removing a break hour prunes its break mark', () {
      final d = toggleBreakHour(day(), 1260); // last block 21:00
      final removed = removeLastHour(d)!;
      expect(removed.breakHourStarts, isEmpty);
      expect(removed.endMinutes, 21 * 60);
    });
  });

  group('classification at a fixed clock', () {
    // Sunday 2026-10-25, now 13:30, shift 11:00-22:00, break at 14:00.
    final today = DateTime(2026, 10, 25);
    final now = DateTime(2026, 10, 25, 13, 30);
    final d = toggleBreakHour(day(), 840);

    test('today: past = worked, containing hour = current, later = upcoming',
        () {
      expect(
          classifyBlock(
              day: today, now: now, blockStart: 660, isBreak: false),
          HourBlockState.worked);
      expect(
          classifyBlock(
              day: today, now: now, blockStart: 720, isBreak: false),
          HourBlockState.worked);
      expect(
          classifyBlock(
              day: today, now: now, blockStart: 780, isBreak: false),
          HourBlockState.current);
      expect(
          classifyBlock(
              day: today, now: now, blockStart: 900, isBreak: false),
          HourBlockState.upcoming);
    });

    test('break blocks are onBreak regardless of the clock', () {
      expect(
          classifyBlock(
              day: today, now: now, blockStart: 840, isBreak: true),
          HourBlockState.onBreak);
    });

    test('summary: worked 2, remaining 8, break counts as neither', () {
      final s = summarizeBlocks(day: d, dayDate: today, now: now);
      expect(s.worked, 2);
      expect(s.remaining, 8);
      expect(s.worked + s.remaining, 10); // 11 blocks - 1 break
    });

    test('past days: all work hours worked; future days: all upcoming',
        () {
      final past = summarizeBlocks(
          day: d,
          dayDate: DateTime(2026, 10, 24),
          now: now);
      expect((past.worked, past.remaining), (10, 0));
      final future = summarizeBlocks(
          day: d,
          dayDate: DateTime(2026, 10, 26),
          now: now);
      expect((future.worked, future.remaining), (0, 10));
    });

    test('overnight spill at 23:00: next-day 01:00 block is upcoming',
        () {
      final night = day(start: 22 * 60, end: 2 * 60);
      expect(hourBlockStarts(night), [1320, 1380, 1440, 1500]);
      expect(
          classifyBlock(
              day: today,
              now: DateTime(2026, 10, 25, 23, 0),
              blockStart: 1500,
              isBreak: false),
          HourBlockState.upcoming);
      expect(
          classifyBlock(
              day: today,
              now: DateTime(2026, 10, 25, 23, 0),
              blockStart: 1380,
              isBreak: false),
          HourBlockState.current);
    });
  });

  group('12h vs 24h formatting', () {
    test('24h pads and wraps overnight starts', () {
      expect(formatMinutes(660, TimeFormatMode.h24), '11:00');
      expect(formatMinutes(0, TimeFormatMode.h24), '00:00');
      expect(formatMinutes(90, TimeFormatMode.h24), '01:30');
      expect(formatMinutes(1500, TimeFormatMode.h24), '01:00');
    });

    test('12h: midnight 12 AM, noon 12 PM, afternoon PM', () {
      expect(formatMinutes(660, TimeFormatMode.h12), '11:00 AM');
      expect(formatMinutes(0, TimeFormatMode.h12), '12:00 AM');
      expect(formatMinutes(720, TimeFormatMode.h12), '12:00 PM');
      expect(formatMinutes(780, TimeFormatMode.h12), '1:00 PM');
    });

    test('12h Arabic markers: ص morning, م evening', () {
      expect(formatMinutes(0, TimeFormatMode.h12, arabic: true), '12:00 ص');
      expect(formatMinutes(780, TimeFormatMode.h12, arabic: true), '1:00 م');
    });

    test('stored-mode mapping: 0 system, 1 24h, 2 12h, unknown system', () {
      expect(timeFormatModeFromStored(0), TimeFormatMode.system);
      expect(timeFormatModeFromStored(1), TimeFormatMode.h24);
      expect(timeFormatModeFromStored(2), TimeFormatMode.h12);
      expect(timeFormatModeFromStored(99), TimeFormatMode.system);
      expect(timeFormatModeFromStored(null), TimeFormatMode.system);
      expect(timeFormatModeToStored(TimeFormatMode.h24), 1);
    });
  });

  group('old-record migration through the save chokepoint', () {
    late Directory tmp;
    late DatabaseService db;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('df_hour_blocks_');
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
    });

    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('old record: no breakHourStarts, legacy break still the net',
        () async {
      final anchor = DateTime(2026, 10, 25);
      final start = WeekCalendar.weekStart(anchor);
      final days = WeekCalendar.weekDays(anchor)
          .map((d) => DailySchedule(
                dateKey: WeekCalendar.dateKey(d),
                startMinutes: 8 * 60,
                endMinutes: 17 * 60,
                breakDurationMinutes: 30,
              ))
          .toList();
      await db.saveSchedule(WorkSchedule(
        id: 'sch_${WeekCalendar.dateKey(start)}',
        weekStartKey: WeekCalendar.dateKey(start),
        weekEndKey: WeekCalendar.dateKey(WeekCalendar.weekDays(anchor).last),
        dailySchedules: days,
        createdAtMillis: 1,
        updatedAtMillis: 1,
      ));
      final back = db.scheduleForWeek(anchor)!;
      final sunday =
          back.dailySchedules.firstWhere((d) => d.dateKey == '2026-10-25');
      // Safe default for old records: empty break list, duration kept.
      expect(sunday.breakHourStarts, isEmpty);
      expect(sunday.breakDurationMinutes, 30);
      expect(blockNetMinutes(sunday), 9 * 60 - 30);
      // Toggle a break block and save through the chokepoint: the
      // break mark persists, the duration is never zeroed.
      final edited = toggleBreakHour(sunday, 12 * 60);
      await db.saveSchedule(WorkSchedule(
        id: back.id,
        weekStartKey: back.weekStartKey,
        weekEndKey: back.weekEndKey,
        dailySchedules: [
          for (final d in back.dailySchedules)
            if (d.dateKey == edited.dateKey) edited else d,
        ],
        createdAtMillis: back.createdAtMillis,
        updatedAtMillis: 2,
      ));
      final reloaded = db
          .scheduleForWeek(anchor)!
          .dailySchedules
          .firstWhere((d) => d.dateKey == '2026-10-25');
      expect(reloaded.breakHourStarts, [720]);
      expect(reloaded.breakDurationMinutes, 30);
      expect(blockNetMinutes(reloaded), 9 * 60 - 60);
    });
  });
}
