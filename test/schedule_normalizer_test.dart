import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/date_time/schedule_normalizer.dart';
import 'package:deliveryflow/core/logging/app_log_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// v27.10: stored-week normalization. The week under test is
/// Sun 2026-10-25 .. Sat 2026-10-31.
void main() {
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
    String notes = '',
  }) =>
      DailySchedule(
        dateKey: key,
        isWorkingDay: on,
        startMinutes: start,
        endMinutes: end,
        breakDurationMinutes: brk,
        notes: notes,
      );

  /// Mohamed's actual stored week: positionally correct, but from the
  /// second Thursday on the dateKeys lag one day behind the values —
  /// [Sun, Mon, Tue, Wed, Thu(OFF), "Thu"(ON 14:00-17:00/60 — really
  /// Friday), "Fri"(ON 10:00-13:00/45 — really Saturday)].
  List<DailySchedule> fieldCase() => [
        day('2026-10-25'),
        day('2026-10-26'),
        day('2026-10-27'),
        day('2026-10-28', start: 14 * 60, end: 17 * 60, brk: 60),
        day('2026-10-29', on: false), // his real Thursday: OFF
        day('2026-10-29', start: 14 * 60, end: 17 * 60, brk: 60), // Friday
        day('2026-10-30', start: 10 * 60, end: 13 * 60, brk: 45), // Saturday
      ];

  group('ScheduleNormalizer.normalizeWeek', () {
    test('field case: 7 drifted keys are relabeled positionally', () {
      final r = ScheduleNormalizer.normalizeWeek(
        weekStartKey: weekStartKey,
        stored: fieldCase(),
        defaultBreakMinutes: 30,
      );
      expect(r.changed, isTrue);
      expect(r.strategy, ScheduleFixStrategy.relabel);
      expect(r.relabeledCount, 2);
      expect(r.days.map((d) => d.dateKey).toList(), canonical);

      // Thursday keeps the FIRST Thursday entry: his real day off.
      final thu = r.days[4];
      expect(thu.dateKey, '2026-10-29');
      expect(thu.isWorkingDay, isFalse);

      // Friday receives the second "Thursday" entry's values.
      final fri = r.days[5];
      expect(fri.dateKey, '2026-10-30');
      expect(fri.isWorkingDay, isTrue);
      expect(fri.startMinutes, 14 * 60);
      expect(fri.endMinutes, 17 * 60);
      expect(fri.breakDurationMinutes, 60);

      // Saturday receives the entry that was mislabeled as Friday.
      final sat = r.days[6];
      expect(sat.dateKey, '2026-10-31');
      expect(sat.isWorkingDay, isTrue);
      expect(sat.startMinutes, 10 * 60);
      expect(sat.endMinutes, 13 * 60);
      expect(sat.breakDurationMinutes, 45);

      // Untouched head of the week keeps its values.
      expect(r.days[3].startMinutes, 14 * 60);
      expect(r.days[3].breakDurationMinutes, 60);
      expect(r.days[0].dateKey, '2026-10-25');
    });

    test('fallback: 8 entries merge by key, first occurrence wins', () {
      final stored = [
        day('2026-10-25'),
        day('2026-10-26'),
        day('2026-10-27'),
        day('2026-10-28'),
        day('2026-10-29', on: false), // first Thursday wins
        day('2026-10-29', start: 14 * 60, end: 17 * 60, brk: 60),
        day('2026-10-30'),
        day('2026-10-31', start: 10 * 60, end: 13 * 60, brk: 45),
      ];
      final r = ScheduleNormalizer.normalizeWeek(
        weekStartKey: weekStartKey,
        stored: stored,
        defaultBreakMinutes: 30,
      );
      expect(r.changed, isTrue);
      expect(r.strategy, ScheduleFixStrategy.merge);
      expect(r.duplicatesDropped, 1);
      expect(r.filledCount, 0);
      expect(r.outOfWeekDropped, 0);
      expect(r.days.map((d) => d.dateKey).toList(), canonical);
      expect(r.days[4].isWorkingDay, isFalse); // Thursday = first entry
      expect(r.days[6].startMinutes, 10 * 60); // Saturday kept its values
    });

    test('fallback: out-of-week entries dropped, gaps default-filled', () {
      final stored = [
        day('2026-10-25'),
        day('2026-10-26'),
        day('2026-10-27'),
        day('2026-10-28'),
        day('2026-10-29'),
        day('2026-10-30'),
        day('2026-11-05'), // next week — out of this week
        day('2026-10-24'), // previous week — out of this week
      ];
      final r = ScheduleNormalizer.normalizeWeek(
        weekStartKey: weekStartKey,
        stored: stored,
        defaultBreakMinutes: 45,
      );
      expect(r.strategy, ScheduleFixStrategy.merge);
      expect(r.outOfWeekDropped, 2);
      expect(r.filledCount, 1);
      expect(r.days.map((d) => d.dateKey).toList(), canonical);
      final sat = r.days[6];
      expect(sat.dateKey, '2026-10-31');
      expect(sat.isWorkingDay, isTrue); // constructor defaults
      expect(sat.startMinutes, 9 * 60);
      expect(sat.endMinutes, 17 * 60);
      expect(sat.breakDurationMinutes, 45); // settings default break
    });

    test('already-canonical list is returned unchanged', () {
      final stored = [
        for (var i = 0; i < 7; i++)
          day(canonical[i], start: 8 * 60 + i, notes: 'n$i'),
      ];
      final r = ScheduleNormalizer.normalizeWeek(
        weekStartKey: weekStartKey,
        stored: stored,
        defaultBreakMinutes: 30,
      );
      expect(r.changed, isFalse);
      expect(r.strategy, ScheduleFixStrategy.none);
      expect(r.days.length, 7);
      for (var i = 0; i < 7; i++) {
        expect(r.days[i].dateKey, stored[i].dateKey);
        expect(r.days[i].startMinutes, stored[i].startMinutes);
        expect(r.days[i].notes, stored[i].notes);
      }
    });

    test('empty stored list yields 7 defaults', () {
      final r = ScheduleNormalizer.normalizeWeek(
        weekStartKey: weekStartKey,
        stored: const [],
        defaultBreakMinutes: 40,
      );
      expect(r.changed, isTrue);
      expect(r.strategy, ScheduleFixStrategy.merge);
      expect(r.filledCount, 7);
      expect(r.days.map((d) => d.dateKey).toList(), canonical);
      for (final d in r.days) {
        expect(d.isWorkingDay, isTrue);
        expect(d.startMinutes, 9 * 60);
        expect(d.endMinutes, 17 * 60);
        expect(d.breakDurationMinutes, 40);
      }
    });
  });

  group('saveSchedule write chokepoint + scheduleForWeek read guarantee', () {
    late Directory tmp;
    late DatabaseService db;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('df_chokepoint_test_');
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
    });

    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('saveSchedule stores the canonical positional list', () async {
      await db.saveSchedule(WorkSchedule(
        id: 'sch_2026-10-25',
        weekStartKey: weekStartKey,
        weekEndKey: '2026-10-31',
        dailySchedules: fieldCase(),
        createdAtMillis: 111,
        updatedAtMillis: 222,
      ));
      // Read the RAW box: what is stored must already be canonical.
      final raw = Hive.box<WorkSchedule>('schedules').get(weekStartKey)!;
      expect(raw.dailySchedules.map((d) => d.dateKey).toList(), canonical);
      expect(raw.dailySchedules[4].isWorkingDay, isFalse); // Thu stays OFF
      expect(raw.dailySchedules[5].startMinutes, 14 * 60); // Fri values
      expect(raw.dailySchedules[5].breakDurationMinutes, 60);
      expect(raw.dailySchedules[6].startMinutes, 10 * 60); // Sat values
      expect(raw.dailySchedules[6].breakDurationMinutes, 45);
      // Metadata passes through untouched.
      expect(raw.createdAtMillis, 111);
      expect(raw.updatedAtMillis, 222);
    });

    test('scheduleForWeek never returns a non-canonical list, even when '
        'the box was seeded bypassing saveSchedule', () async {
      // Direct box put: no init-time heal runs after this within the
      // session, so only normalize-on-read can protect the caller.
      await Hive.box<WorkSchedule>('schedules').put(
        weekStartKey,
        WorkSchedule(
          id: 'sch_2026-10-25',
          weekStartKey: weekStartKey,
          weekEndKey: '2026-10-31',
          dailySchedules: fieldCase(),
          createdAtMillis: 111,
          updatedAtMillis: 222,
        ),
      );
      final got = db.scheduleForWeek(DateTime(2026, 10, 29))!;
      expect(got.dailySchedules.map((d) => d.dateKey).toList(), canonical);
      expect(got.dailySchedules[4].isWorkingDay, isFalse);
      expect(got.dailySchedules[5].startMinutes, 14 * 60);
      expect(got.dailySchedules[6].dateKey, '2026-10-31');
      // The read must NOT mutate the stored object (copy semantics).
      final raw = Hive.box<WorkSchedule>('schedules').get(weekStartKey)!;
      expect(raw.dailySchedules.length, 7);
      expect(raw.dailySchedules[5].dateKey, '2026-10-29');
      expect(raw.dailySchedules[6].dateKey, '2026-10-30');
    });

    test('already-canonical week: save + heal are no-ops', () async {
      final canonicalDays = [
        for (var i = 0; i < 7; i++)
          day(canonical[i], start: 8 * 60 + i * 10, notes: 'n$i'),
      ];
      await db.saveSchedule(WorkSchedule(
        id: 'sch_2026-10-25',
        weekStartKey: weekStartKey,
        weekEndKey: '2026-10-31',
        dailySchedules: canonicalDays,
        createdAtMillis: 111,
        updatedAtMillis: 222,
      ));
      final raw = Hive.box<WorkSchedule>('schedules').get(weekStartKey)!;
      expect(raw.updatedAtMillis, 222); // not rewritten by save-normalize
      expect(raw.dailySchedules.map((d) => d.dateKey).toList(), canonical);
      for (var i = 0; i < 7; i++) {
        expect(raw.dailySchedules[i].startMinutes, 8 * 60 + i * 10);
        expect(raw.dailySchedules[i].notes, 'n$i');
      }
      await Hive.close();

      // Reopen: the startup heal must leave the canonical week alone.
      final db2 = DatabaseService();
      await db2.init(hivePath: tmp.path);
      final again = Hive.box<WorkSchedule>('schedules').get(weekStartKey)!;
      expect(again.updatedAtMillis, 222);
      expect(again.dailySchedules.map((d) => d.dateKey).toList(), canonical);
    });
  });

  group('startup repair (DatabaseService.init)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('df_heal_test_');
    });

    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('corrupted week healed in the box; orders record untouched',
        () async {
      // Phase 1: seed a corrupted week + an orders record, then close.
      final seed = DatabaseService();
      await seed.init(hivePath: tmp.path);
      await seed.upsertOrderRecord(
          dateKey: '2026-10-29', completedOrders: 7, notes: 'keep me');
      final before = seed.orderRecord('2026-10-29')!;
      final orderSnapshot = {
        'id': before.id,
        'dateKey': before.dateKey,
        'completedOrders': before.completedOrders,
        'notes': before.notes,
        'isConfirmed': before.isConfirmed,
        'createdAtMillis': before.createdAtMillis,
        'updatedAtMillis': before.updatedAtMillis,
        'entries': before.entries.length,
      };
      // Seed the corruption with a DIRECT box put, bypassing
      // saveSchedule: saveSchedule is the v27.10 write chokepoint and
      // would normalize this list away. Corruption in the wild predates
      // the chokepoint (older builds / direct restores) — exactly what
      // the startup heal exists for.
      await Hive.box<WorkSchedule>('schedules').put(
        weekStartKey,
        WorkSchedule(
          id: 'sch_2026-10-25',
          weekStartKey: weekStartKey,
          weekEndKey: '2026-10-31',
          dailySchedules: fieldCase(),
          createdAtMillis: 111,
          updatedAtMillis: 222,
        ),
      );
      await Hive.close();

      // Phase 2: reopening runs the heal inside init().
      final log = AppLogService();
      await log.init(hivePath: tmp.path);
      final db = DatabaseService(log: log);
      await db.init(hivePath: tmp.path);

      // The BOX itself is healed (not just the getter's view of it).
      final healed = Hive.box<WorkSchedule>('schedules').get(weekStartKey)!;
      expect(healed.id, 'sch_2026-10-25');
      expect(healed.createdAtMillis, 111); // preserved
      expect(healed.updatedAtMillis, greaterThan(222)); // bumped
      expect(healed.dailySchedules.map((d) => d.dateKey).toList(), canonical);
      expect(healed.dailySchedules[4].isWorkingDay, isFalse); // Thu OFF
      expect(healed.dailySchedules[5].startMinutes, 14 * 60); // Fri values
      expect(healed.dailySchedules[5].breakDurationMinutes, 60);
      expect(healed.dailySchedules[6].startMinutes, 10 * 60); // Sat values
      expect(healed.dailySchedules[6].breakDurationMinutes, 45);
      final healedStamp = healed.updatedAtMillis;

      // The orders record is byte-for-byte the same record.
      final after = db.orderRecord('2026-10-29')!;
      expect(after.id, orderSnapshot['id']);
      expect(after.dateKey, orderSnapshot['dateKey']);
      expect(after.completedOrders, orderSnapshot['completedOrders']);
      expect(after.notes, orderSnapshot['notes']);
      expect(after.isConfirmed, orderSnapshot['isConfirmed']);
      expect(after.createdAtMillis, orderSnapshot['createdAtMillis']);
      expect(after.updatedAtMillis, orderSnapshot['updatedAtMillis']);
      expect(after.entries.length, orderSnapshot['entries']);
      expect(db.recordCounts()['schedules'], 1);

      // The repair was written to the diagnostics log (fire-and-forget
      // writes: poll briefly for the flush).
      var scheduleEntries = log.entries(category: AppLogCategory.schedule);
      for (var i = 0; i < 20 && scheduleEntries.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        scheduleEntries = log.entries(category: AppLogCategory.schedule);
      }
      expect(scheduleEntries, isNotEmpty);
      expect(scheduleEntries.first.message, contains('2026-10-25'));
      expect(scheduleEntries.first.detail, contains('7 stored days'));

      // Phase 3: idempotent — a second reopen changes nothing.
      await Hive.close();
      final db3 = DatabaseService();
      await db3.init(hivePath: tmp.path);
      final again = Hive.box<WorkSchedule>('schedules').get(weekStartKey)!;
      expect(again.updatedAtMillis, healedStamp);
      expect(again.dailySchedules.map((d) => d.dateKey).toList(), canonical);
    });
  });
}
