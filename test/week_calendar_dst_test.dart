import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/date_time/schedule_normalizer.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// v27.11: WeekCalendar must do CALENDAR arithmetic (DateTime
/// constructor), never absolute 24h Duration arithmetic.
///
/// Why: Egypt's DST fall-back (Thu 2026-10-29 24:00 EEST, clocks back
/// to 23:00 EET) made `start.add(Duration(days: i))` generate the week
/// Sun 2026-10-25..Sat 2026-10-31 as [25, 26, 27, 28, 29, 29, 30] —
/// index 5 landed on Oct 29 23:00 (a duplicate Thursday) and Saturday
/// Oct 31 was never generated. Mohamed's stored week was born with
/// those drifted keys, and v27.10's normalizer could not see the
/// corruption because its canonical keys came from the same broken
/// generator (the suite ran in UTC, which has no DST, so it stayed
/// green). These tests lock the calendar behavior; they are only
/// discriminating when run in a DST-observing zone, so the suite is
/// run under TZ=Africa/Cairo as well as the default zone.
void main() {
  List<String> keysOf(DateTime anyDay) =>
      WeekCalendar.weekDays(anyDay).map(WeekCalendar.dateKey).toList();

  group('fall-back week (DST ends Thu 2026-10-29 24:00 EEST)', () {
    const expected = [
      '2026-10-25',
      '2026-10-26',
      '2026-10-27',
      '2026-10-28',
      '2026-10-29',
      '2026-10-30',
      '2026-10-31',
    ];

    test('weekDays yields exactly Sun 2026-10-25 .. Sat 2026-10-31', () {
      final days = WeekCalendar.weekDays(DateTime(2026, 10, 29));
      expect(days.map(WeekCalendar.dateKey).toList(), expected);
      // No duplicates, no skips, real local midnights, Sun..Sat order.
      expect(days.map(WeekCalendar.dateKey).toSet().length, 7);
      const weekdays = [
        DateTime.sunday,
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
        DateTime.friday,
        DateTime.saturday,
      ];
      for (var i = 0; i < 7; i++) {
        expect(days[i].hour, 0);
        expect(days[i].minute, 0);
        expect(days[i].weekday, weekdays[i]);
      }
    });

    test('every day of the week maps to the same 7 keys', () {
      for (var d = 25; d <= 31; d++) {
        expect(keysOf(DateTime(2026, 10, d)), expected, reason: 'day $d');
      }
    });

    test('weekStart / weekEnd / nextWeekStart across the transition', () {
      expect(WeekCalendar.weekStart(DateTime(2026, 10, 31)),
          DateTime(2026, 10, 25));
      expect(WeekCalendar.weekStart(DateTime(2026, 10, 29, 23, 30)),
          DateTime(2026, 10, 25));
      expect(WeekCalendar.weekEnd(DateTime(2026, 10, 29)),
          DateTime(2026, 10, 31));
      expect(WeekCalendar.weekEnd(DateTime(2026, 10, 25)),
          DateTime(2026, 10, 31));
      expect(WeekCalendar.nextWeekStart(DateTime(2026, 10, 29)),
          DateTime(2026, 11, 1));
    });

    test('addDays steps over the repeated hour by calendar dates', () {
      expect(WeekCalendar.addDays(DateTime(2026, 10, 29), 1),
          DateTime(2026, 10, 30));
      expect(WeekCalendar.addDays(DateTime(2026, 10, 29), 2),
          DateTime(2026, 10, 31));
      expect(WeekCalendar.addDays(DateTime(2026, 10, 25), 6),
          DateTime(2026, 10, 31));
      expect(WeekCalendar.addDays(DateTime(2026, 10, 31), -6),
          DateTime(2026, 10, 25));
      expect(WeekCalendar.addDays(DateTime(2026, 10, 30), -1),
          DateTime(2026, 10, 29));
    });

    test('daysBetween counts calendar days, not 24h blocks', () {
      // Oct 29 -> Oct 31 spans the 25-hour fall-back day: absolute
      // difference is 49h for the pair below, and 47h here — a
      // duration-based count would say 1 for this pair, not 2.
      expect(
          WeekCalendar.daysBetween(
              DateTime(2026, 10, 29), DateTime(2026, 10, 31)),
          2);
      expect(
          WeekCalendar.daysBetween(
              DateTime(2026, 10, 25), DateTime(2026, 10, 30)),
          5);
      expect(
          WeekCalendar.daysBetween(
              DateTime(2026, 10, 25), DateTime(2026, 10, 31)),
          6);
      expect(
          WeekCalendar.daysBetween(
              DateTime(2026, 10, 31), DateTime(2026, 10, 25)),
          -6);
    });
  });

  group('spring-forward week (DST starts Fri 2026-04-24 01:00 EEST)', () {
    const expected = [
      '2026-04-19',
      '2026-04-20',
      '2026-04-21',
      '2026-04-22',
      '2026-04-23',
      '2026-04-24',
      '2026-04-25',
    ];

    test('weekDays: 7 distinct consecutive dates, none skipped', () {
      final days = WeekCalendar.weekDays(DateTime(2026, 4, 24));
      expect(days.map(WeekCalendar.dateKey).toList(), expected);
      expect(days.map(WeekCalendar.dateKey).toSet().length, 7);
      // Every generated day must be the canonical START of its own
      // calendar date: re-deriving the date-only value from its fields
      // must give back the same instant. Duration-based generation
      // breaks this after a transition (Apr 25 comes out at 01:00
      // while its date-only start is 00:00). The assertion is
      // zone-independent: on 2026-04-24 itself, whose local midnight
      // does not exist in Africa/Cairo (clocks jump 00:00 -> 01:00),
      // both sides resolve to 01:00 EEST and stay equal — the DATE,
      // which is all a dateKey cares about, is exactly right.
      for (final d in days) {
        expect(d, WeekCalendar.dateOnly(d),
            reason:
                '${WeekCalendar.dateKey(d)} is not the start of its day');
      }
      expect(days.first.weekday, DateTime.sunday);
      expect(days.last.weekday, DateTime.saturday);
    });

    test('addDays / daysBetween across the 23-hour day', () {
      expect(WeekCalendar.addDays(DateTime(2026, 4, 24), 1),
          DateTime(2026, 4, 25));
      expect(WeekCalendar.addDays(DateTime(2026, 4, 23), 2),
          DateTime(2026, 4, 25));
      // Absolute difference Apr 23 00:00 EET -> Apr 25 00:00 EEST is
      // 47h; the calendar answer is 2 days.
      expect(
          WeekCalendar.daysBetween(
              DateTime(2026, 4, 23), DateTime(2026, 4, 25)),
          2);
      expect(WeekCalendar.weekStart(DateTime(2026, 4, 25)),
          DateTime(2026, 4, 19));
      expect(WeekCalendar.weekEnd(DateTime(2026, 4, 24)),
          DateTime(2026, 4, 25));
    });
  });

  group('month-boundary week (no month-end clamp)', () {
    const expected = [
      '2026-11-29',
      '2026-11-30',
      '2026-12-01',
      '2026-12-02',
      '2026-12-03',
      '2026-12-04',
      '2026-12-05',
    ];

    test('week Sun 2026-11-29 .. Sat 2026-12-05 generates in full', () {
      expect(keysOf(DateTime(2026, 12, 2)), expected);
      expect(keysOf(DateTime(2026, 11, 30)), expected);
      expect(WeekCalendar.weekStart(DateTime(2026, 12, 5)),
          DateTime(2026, 11, 29));
      expect(WeekCalendar.weekEnd(DateTime(2026, 11, 30)),
          DateTime(2026, 12, 5));
      expect(
          WeekCalendar.daysBetween(
              DateTime(2026, 11, 29), DateTime(2026, 12, 5)),
          6);
      // The normalizer's canonical view agrees (no clamp there either).
      expect(ScheduleNormalizer.canonicalKeys('2026-11-29'), expected);
    });
  });

  group('end-to-end: the DST-drifted stored week heals on read', () {
    const weekStartKey = '2026-10-25';
    const canonical = [
      '2026-10-25',
      '2026-10-26',
      '2026-10-27',
      '2026-10-28',
      '2026-10-29',
      '2026-10-30',
      '2026-10-31',
    ];

    DailySchedule day(
      String key, {
      bool on = true,
      int start = 9 * 60,
      int end = 17 * 60,
      int brk = 30,
    }) =>
        DailySchedule(
          dateKey: key,
          isWorkingDay: on,
          startMinutes: start,
          endMinutes: end,
          breakDurationMinutes: brk,
          notes: '',
        );

    /// Exactly what the broken generator stored for Mohamed: keys
    /// [25, 26, 27, 28, 29, 29, 30] with positionally-correct values.
    List<DailySchedule> driftedWeek() => [
          day('2026-10-25'),
          day('2026-10-26'),
          day('2026-10-27'),
          day('2026-10-28', start: 14 * 60, end: 17 * 60, brk: 60),
          day('2026-10-29', on: false), // his real Thursday: OFF
          day('2026-10-29', start: 14 * 60, end: 17 * 60, brk: 60), // Fri
          day('2026-10-30', start: 10 * 60, end: 13 * 60, brk: 45), // Sat
        ];

    late Directory tmp;
    late DatabaseService db;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('df_dst_heal_test_');
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
    });

    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('canonicalKeys are the true calendar week for 2026-10-25', () {
      expect(ScheduleNormalizer.canonicalKeys(weekStartKey), canonical);
    });

    test('scheduleForWeek returns the healed week', () async {
      // Seed AFTER init via direct box put, so only normalize-on-read
      // (not the startup heal) can repair what the caller sees.
      await Hive.box<WorkSchedule>('schedules').put(
        weekStartKey,
        WorkSchedule(
          id: 'sch_2026-10-25',
          weekStartKey: weekStartKey,
          weekEndKey: '2026-10-31',
          dailySchedules: driftedWeek(),
          createdAtMillis: 111,
          updatedAtMillis: 222,
        ),
      );

      final got = db.scheduleForWeek(DateTime(2026, 10, 29))!;
      expect(
          got.dailySchedules.map((d) => d.dateKey).toList(), canonical);

      final thu = got.dailySchedules[4];
      expect(thu.dateKey, '2026-10-29');
      expect(thu.isWorkingDay, isFalse); // Thursday stays his day OFF

      final fri = got.dailySchedules[5];
      expect(fri.dateKey, '2026-10-30');
      expect(fri.isWorkingDay, isTrue);
      expect(fri.startMinutes, 14 * 60);
      expect(fri.endMinutes, 17 * 60);
      expect(fri.breakDurationMinutes, 60);

      final sat = got.dailySchedules[6];
      expect(sat.dateKey, '2026-10-31');
      expect(sat.isWorkingDay, isTrue);
      expect(sat.startMinutes, 10 * 60);
      expect(sat.endMinutes, 13 * 60);
      expect(sat.breakDurationMinutes, 45);
    });
  });
}
