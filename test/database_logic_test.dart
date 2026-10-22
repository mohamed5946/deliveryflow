import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Integration-style tests of the real Hive-backed DatabaseService using a
/// temporary directory. Covers order totals/averages, zero vs missing days,
/// manual hours incl. overnight, duplicate prevention and report math.
void main() {
  late Directory tmp;
  late DatabaseService db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('df_test_');
    db = DatabaseService();
    await db.init(hivePath: tmp.path);
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  group('DailyOrderRecord upsert', () {
    test('insert then update keeps a single record per date', () async {
      await db.upsertOrderRecord(dateKey: '2026-10-12', completedOrders: 10);
      await db.upsertOrderRecord(dateKey: '2026-10-12', completedOrders: 14);
      final rec = db.orderRecord('2026-10-12')!;
      expect(rec.completedOrders, 14);
      expect(db.recordCounts()['orderRecords'], 1);
    });

    test('zero is a valid recorded value', () async {
      await db.upsertOrderRecord(dateKey: '2026-10-12', completedOrders: 0);
      expect(db.orderRecord('2026-10-12')!.completedOrders, 0);
    });

    test('negative orders are rejected', () async {
      expect(
        () => db.upsertOrderRecord(dateKey: '2026-10-12', completedOrders: -1),
        throwsArgumentError,
      );
    });
  });

  group('WorkSchedule', () {
    test('one schedule per week-start (upsert, no duplicates)', () async {
      Future<void> save() => db.saveSchedule(WorkSchedule(
            id: 's1',
            weekStartKey: '2026-10-11',
            weekEndKey: '2026-10-17',
            dailySchedules: [
              DailySchedule(dateKey: '2026-10-12', isWorkingDay: true)
            ],
            createdAtMillis: 1,
            updatedAtMillis: 2,
          ));
      await save();
      await save();
      expect(db.recordCounts()['schedules'], 1);
      expect(db.scheduleForWeek(DateTime(2026, 10, 14))!.weekStartKey,
          '2026-10-11');
    });

    test('DailySchedule.netPlannedMinutes incl. overnight', () {
      final day = DailySchedule(
        dateKey: '2026-10-12',
        startMinutes: 22 * 60,
        endMinutes: 6 * 60,
        breakDurationMinutes: 30,
      );
      expect(day.netPlannedMinutes, 450);
      final off = DailySchedule(dateKey: '2026-10-13', isWorkingDay: false);
      expect(off.netPlannedMinutes, 0);
    });
  });

  group('WorkSession', () {
    test('manual session net minutes incl. overnight', () async {
      final s = await db.saveManualSession(
        dateKey: '2026-10-12',
        startMinutes: 22 * 60,
        endMinutes: 2 * 60,
        breakMinutes: 30,
      );
      expect(s.netMinutes, 210); // 4h - 30m
      expect(db.recordedMinutesForDate('2026-10-12'), 210);
    });

    test('invalid manual durations are rejected', () async {
      expect(
        () => db.saveManualSession(
          dateKey: '2026-10-12',
          startMinutes: 9 * 60,
          endMinutes: 9 * 60,
          breakMinutes: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => db.saveManualSession(
          dateKey: '2026-10-12',
          startMinutes: 9 * 60,
          endMinutes: 10 * 60,
          breakMinutes: 999,
        ),
        throwsArgumentError,
      );
    });

    test('active session prevents a second overlapping session', () async {
      await db.startSession('2026-10-12');
      expect(db.activeSession(), isNotNull);
      expect(() => db.startSession('2026-10-12'), throwsStateError);
    });

    test('timer session net excludes breaks', () async {
      final s = await db.startSession('2026-10-12');
      final now = DateTime.now().millisecondsSinceEpoch;
      // Simulate: started 3h ago, one 30m break.
      s.startMillis = now - 3 * 3600 * 1000;
      s.breaks.add(BreakInterval(
        startMillis: now - 2 * 3600 * 1000,
        endMillis: now - 2 * 3600 * 1000 + 30 * 60 * 1000,
      ));
      s.endMillis = now;
      s.status = 2;
      await db.saveSession(s);
      // 180 - 30 = 150 minutes (allow 1 min rounding tolerance)
      expect(db.recordedMinutesForDate('2026-10-12'),
          inInclusiveRange(149, 151));
    });
  });

  group('WeeklyReport math', () {
    test('totals, averages over recorded working days only', () async {
      // Week of Sun 2026-10-11. Record Mon(10 orders, 8h) & Tue(20, 4h);
      // Wed unrecorded; Thu recorded as 0 orders.
      await db.upsertOrderRecord(
          dateKey: '2026-10-12', completedOrders: 10);
      await db.saveManualSession(
          dateKey: '2026-10-12',
          startMinutes: 9 * 60,
          endMinutes: 17 * 60,
          breakMinutes: 0);
      await db.upsertOrderRecord(
          dateKey: '2026-10-13', completedOrders: 20);
      await db.saveManualSession(
          dateKey: '2026-10-13',
          startMinutes: 9 * 60,
          endMinutes: 13 * 60,
          breakMinutes: 0);
      await db.upsertOrderRecord(
          dateKey: '2026-10-15', completedOrders: 0);

      final r = db.buildWeeklyReport(DateTime(2026, 10, 14));
      expect(r.totalOrders, 30);
      expect(r.totalRecordedHours, 12.0);
      // Averages over recorded working days with data: Mon, Tue, Thu
      expect(r.averageOrdersPerWorkingDay, closeTo(10.0, 0.001));
      expect(r.averageHoursPerWorkingDay, closeTo(4.0, 0.001));
      expect(r.ordersPerWorkingHour, closeTo(2.5, 0.001));
      expect(r.bestDayKey, '2026-10-13');
      // Wed/Sun/Fri/Sat unrecorded
      expect(r.missingRecordDates,
          containsAll(['2026-10-11', '2026-10-14', '2026-10-16', '2026-10-17']));
      expect(r.recordedDaysCount, 3);
    });

    test('unrecorded days are never treated as zero', () async {
      await db.upsertOrderRecord(
          dateKey: '2026-10-12', completedOrders: 12);
      final r = db.buildWeeklyReport(DateTime(2026, 10, 14));
      expect(r.totalOrders, 12);
      // Only one recorded working day with orders.
      expect(r.averageOrdersPerWorkingDay, 12.0);
    });

    test('empty week yields nulls, not fabricated values', () async {
      final r = db.buildWeeklyReport(DateTime(2026, 10, 14));
      expect(r.totalOrders, 0);
      expect(r.totalRecordedHours, 0.0);
      expect(r.averageOrdersPerWorkingDay, isNull);
      expect(r.ordersPerWorkingHour, isNull);
      expect(r.bestDayKey, isNull);
      expect(r.missingRecordDates.length, 7);
    });

    test('CSV export contains recorded rows', () async {
      await db.upsertOrderRecord(
          dateKey: '2026-10-12', completedOrders: 7, notes: 'ok');
      final csv = db.exportCsv();
      expect(csv, contains('2026-10-12'));
      expect(csv, contains('7'));
      expect(csv.split('\n').first,
          'date,orders,work_minutes,km_out,km_back,notes');
    });

    test('order entries: add/update/delete sync count and km', () async {
      const key = '2026-10-13';
      final e1 = await db.addOrderEntry(
        dateKey: key,
        timestampMillis:
            DateTime(2026, 10, 13, 19, 30).millisecondsSinceEpoch,
        kmOut: 12.5,
        kmBack: 8.0,
      );
      await db.addOrderEntry(
        dateKey: key,
        timestampMillis:
            DateTime(2026, 10, 13, 21, 15).millisecondsSinceEpoch,
        kmOut: 5,
        kmBack: 5.5,
      );
      var rec = db.orderRecord(key)!;
      // v27 count-on-start: pending entries do not count yet — only
      // the km aggregates include them.
      expect(rec.completedOrders, 0);
      expect(rec.totalKmOut, 17.5);
      expect(rec.totalKmBack, 13.5);
      expect(rec.totalKm, 31.0);

      await db.updateOrderEntry(
        dateKey: key,
        entryId: e1.id,
        kmOut: 10,
      );
      rec = db.orderRecord(key)!;
      expect(rec.totalKmOut, 15.0);
      expect(rec.completedOrders, 0);

      // Delivery starts for e1 (بدأ التوصيل) -> it counts now.
      await db.updateOrderEntry(dateKey: key, entryId: e1.id, status: 1);
      rec = db.orderRecord(key)!;
      expect(rec.completedOrders, 1);

      await db.deleteOrderEntry(dateKey: key, entryId: e1.id);
      rec = db.orderRecord(key)!;
      // The deleted entry was counted; the remaining one is pending.
      expect(rec.completedOrders, 0);
      expect(rec.entries.length, 1);
      expect(rec.totalKm, 10.5);

      expect(() => db.addOrderEntry(
            dateKey: key,
            timestampMillis: 0,
            kmOut: -1,
          ),
          throwsArgumentError);
    });

    test('GPS tracking fields and route points persist', () async {
      const key = '2026-10-14';
      final e = await db.addOrderEntry(
        dateKey: key,
        timestampMillis:
            DateTime(2026, 10, 14, 10).millisecondsSinceEpoch,
      );
      final pickup = DateTime(2026, 10, 14, 10, 5).millisecondsSinceEpoch;
      final delivered =
          DateTime(2026, 10, 14, 10, 40).millisecondsSinceEpoch;
      await db.updateOrderEntry(
        dateKey: key,
        entryId: e.id,
        status: 3,
        pickupTimeMillis: pickup,
        deliveredTimeMillis: delivered,
        martArrivedTimeMillis:
            DateTime(2026, 10, 14, 11, 10).millisecondsSinceEpoch,
        gpsKmOut: 7.25,
        gpsKmBack: 6.8,
        outgoingDurationSec: 2100,
        returnDurationSec: 1800,
        routeOutLat: [30.05, 30.06, 30.07],
        routeOutLng: [31.24, 31.25, 31.26],
        routeBackLat: [30.07, 30.06, 30.05],
        routeBackLng: [31.26, 31.25, 31.24],
      );
      final rec = db.orderRecord(key)!;
      final re = rec.entries.firstWhere((x) => x.id == e.id);
      expect(re.status, 3);
      expect(re.isCompleted, true);
      expect(re.pickupTimeMillis, pickup);
      expect(re.deliveredTimeMillis, delivered);
      expect(re.gpsKmOut, 7.25);
      expect(re.gpsKmBack, 6.8);
      expect(re.effectiveKmOut, 7.25);
      expect(re.effectiveKmBack, 6.8);
      expect(re.effectiveKmTotal, 14.05);
      expect(re.outgoingDurationSec, 2100);
      expect(re.returnDurationSec, 1800);
      expect(re.hasRoute, true);
      expect(re.routePointCount, 6);
      expect(re.routeOutLat, [30.05, 30.06, 30.07]);
      // JSON round-trip keeps route data.
      final rej = OrderEntry.fromJson(re.toJson());
      expect(rej.routeOutLat, [30.05, 30.06, 30.07]);
      expect(rej.gpsKmOut, 7.25);
    });

    test('weekly report includes km totals', () async {
      await db.addOrderEntry(
        dateKey: '2026-10-12',
        timestampMillis:
            DateTime(2026, 10, 12, 20).millisecondsSinceEpoch,
        kmOut: 10,
        kmBack: 10,
      );
      final r = db.buildWeeklyReport(DateTime(2026, 10, 14));
      expect(r.totalKmOut, 10);
      expect(r.totalKmBack, 10);
      expect(r.totalKm, 20);
    });

    test('backup/restore round-trip preserves order entries', () async {
      await db.addOrderEntry(
        dateKey: '2026-10-14',
        timestampMillis:
            DateTime(2026, 10, 14, 18).millisecondsSinceEpoch,
        kmOut: 7.5,
        kmBack: 6.5,
        notes: 'test entry',
      );
      final json = db.backupJson();
      await db.clearAll();
      await db.restoreFromJson(json);
      final rec = db.orderRecord('2026-10-14')!;
      expect(rec.entries.length, 1);
      expect(rec.entries.first.kmOut, 7.5);
      expect(rec.entries.first.kmBack, 6.5);
      expect(rec.entries.first.notes, 'test entry');
    });

    test('backup/restore round-trip preserves records', () async {
      await db.upsertOrderRecord(
          dateKey: '2026-10-12', completedOrders: 9);
      await db.saveManualSession(
          dateKey: '2026-10-12',
          startMinutes: 9 * 60,
          endMinutes: 17 * 60,
          breakMinutes: 30);
      final json = db.backupJson();
      await db.clearAll();
      expect(db.orderRecord('2026-10-12'), isNull);
      await db.restoreFromJson(json);
      expect(db.orderRecord('2026-10-12')!.completedOrders, 9);
      expect(db.recordedMinutesForDate('2026-10-12'), 450);
    });
  });

  group('UserSettings', () {
    test('theme/language/reminder changes persist', () async {
      final s = db.settings;
      s.themeMode = 2;
      s.languageCode = 'en';
      s.dailyReminderHour = 20;
      s.dailyReminderMinute = 30;
      await db.saveSettings(s);
      final re = db.settings;
      expect(re.themeMode, 2);
      expect(re.languageCode, 'en');
      expect(re.dailyReminderHour, 20);
      expect(re.dailyReminderMinute, 30);
    });

    test('salary settings (order price + daily fixed) persist', () async {
      final s = db.settings;
      s.orderPrice = 15.5;
      s.dailyFixedPay = 100;
      s.themePreset = 3;
      await db.saveSettings(s);
      final re = db.settings;
      expect(re.orderPrice, 15.5);
      expect(re.dailyFixedPay, 100);
      expect(re.themePreset, 3);
    });

    test('v25: autoNavMode persists; v27: default is Google Maps (1)',
        () async {
      // v27: new installs start in Google Maps (middleman) mode.
      expect(db.settings.autoNavMode, 1);
      final s = db.settings;
      s.autoNavMode = 0;
      await db.saveSettings(s);
      expect(db.settings.autoNavMode, 0);
      // JSON round-trip keeps the value.
      final rt = UserSettings.fromJson(db.settings.toJson());
      expect(rt.autoNavMode, 0);
    });
  });

  group('v18: edit/delete recomputation', () {
    test('edited km becomes manual (يدوي badge) and takes effect',
        () async {
      const key = '2026-10-15';
      final e = await db.addOrderEntry(
        dateKey: key,
        timestampMillis:
            DateTime(2026, 10, 15, 12).millisecondsSinceEpoch,
        kmOut: 5,
        kmBack: 4,
      );
      // Simulate a GPS-tracked completed order.
      await db.updateOrderEntry(
        dateKey: key,
        entryId: e.id,
        status: 3,
        gpsKmOut: 5,
        gpsKmBack: 4,
      );
      var rec = db.orderRecord(key)!;
      var entry = rec.entries.firstWhere((x) => x.id == e.id);
      expect(entry.hasManualKm, isFalse);
      expect(entry.effectiveKmTotal, 9);

      // Edit km like the order-details "تعديل" sheet does: new numbers
      // + zeroed GPS km.
      await db.updateOrderEntry(
        dateKey: key,
        entryId: e.id,
        kmOut: 6.5,
        kmBack: 4,
        gpsKmOut: 0,
        gpsKmBack: 0,
        notes: 'edited',
        phone: '01001234567',
      );
      rec = db.orderRecord(key)!;
      entry = rec.entries.firstWhere((x) => x.id == e.id);
      expect(entry.isManualOut, isTrue);
      expect(entry.hasManualKm, isTrue);
      expect(entry.effectiveKmTotal, 10.5);
      expect(entry.notes, 'edited');
      expect(entry.phone, '01001234567');
      // Day aggregates follow the edited numbers.
      expect(rec.totalKmOut, 6.5);
    });

    test('deleting an order recomputes weekly totals', () async {
      const day1 = '2026-10-12'; // Monday
      const day2 = '2026-10-13'; // Tuesday
      final e1 = await db.addOrderEntry(
        dateKey: day1,
        timestampMillis:
            DateTime(2026, 10, 12, 19).millisecondsSinceEpoch,
        kmOut: 10,
        kmBack: 9,
      );
      final e2 = await db.addOrderEntry(
        dateKey: day2,
        timestampMillis:
            DateTime(2026, 10, 13, 19).millisecondsSinceEpoch,
        kmOut: 7,
        kmBack: 6,
      );
      // v27: entries count only once delivery starts.
      await db.updateOrderEntry(dateKey: day1, entryId: e1.id, status: 1);
      await db.updateOrderEntry(dateKey: day2, entryId: e2.id, status: 1);
      var report = db.buildWeeklyReport(DateTime(2026, 10, 14));
      expect(report.totalOrders, 2);

      await db.deleteOrderEntry(dateKey: day1, entryId: e1.id);
      report = db.buildWeeklyReport(DateTime(2026, 10, 14));
      expect(report.totalOrders, 1);
      // The deleted day keeps its record shell with zero orders.
      final rec = db.orderRecord(day1)!;
      expect(rec.completedOrders, 0);
      expect(rec.totalKm, 0);
      // Deleting a missing entry is a safe no-op.
      await db.deleteOrderEntry(dateKey: day1, entryId: 'nope');
      expect(db.orderRecord(day1)!.completedOrders, 0);
    });
  });

  group('v26 auto work-hours (planned hours count when orders logged)', () {
    // Week of Sun 2026-10-11. Planned net minutes:
    // Mon 600 (9-19, no break), Tue 420 (9-17, 60 break), Wed 480,
    // Thu OFF, Fri 480, Sat 240, Sun 480.
    Future<void> saveWeekSchedule() => db.saveSchedule(WorkSchedule(
          id: 'w1',
          weekStartKey: '2026-10-11',
          weekEndKey: '2026-10-17',
          dailySchedules: [
            DailySchedule(
                dateKey: '2026-10-11',
                startMinutes: 9 * 60,
                endMinutes: 17 * 60,
                breakDurationMinutes: 0),
            DailySchedule(
                dateKey: '2026-10-12',
                startMinutes: 9 * 60,
                endMinutes: 19 * 60,
                breakDurationMinutes: 0),
            DailySchedule(
                dateKey: '2026-10-13',
                startMinutes: 9 * 60,
                endMinutes: 17 * 60,
                breakDurationMinutes: 60),
            DailySchedule(
                dateKey: '2026-10-14',
                startMinutes: 9 * 60,
                endMinutes: 17 * 60,
                breakDurationMinutes: 0),
            DailySchedule(
                dateKey: '2026-10-15',
                isWorkingDay: false,
                startMinutes: 9 * 60,
                endMinutes: 17 * 60,
                breakDurationMinutes: 0),
            DailySchedule(
                dateKey: '2026-10-16',
                startMinutes: 9 * 60,
                endMinutes: 17 * 60,
                breakDurationMinutes: 0),
            DailySchedule(
                dateKey: '2026-10-17',
                startMinutes: 9 * 60,
                endMinutes: 13 * 60,
                breakDurationMinutes: 0),
          ],
          createdAtMillis: 1,
          updatedAtMillis: 2,
        ));

    DayBreakdown dayOf(WeeklyReport r, String key) =>
        r.days.firstWhere((d) => d.dateKey == key);

    test('orders >= 1 with no session credits the planned minutes',
        () async {
      await saveWeekSchedule();
      // Bulk count entry (v26 Change 5 path): bare count, no details.
      await db.upsertOrderRecord(dateKey: '2026-10-12', completedOrders: 15);
      final r = db.buildWeeklyReport(DateTime(2026, 10, 14));
      expect(dayOf(r, '2026-10-12').workMinutes, 600);
      expect(dayOf(r, '2026-10-12').orders, 15);
      expect(r.totalOrders, 15);
      expect(r.totalRecordedHours, 10.0);
      expect(db.effectiveMinutesForDate('2026-10-12'), 600);
    });

    test('recorded zero orders earn no auto-credit', () async {
      await saveWeekSchedule();
      await db.upsertOrderRecord(dateKey: '2026-10-13', completedOrders: 0);
      final r = db.buildWeeklyReport(DateTime(2026, 10, 14));
      expect(dayOf(r, '2026-10-13').workMinutes, 0);
      expect(r.totalRecordedHours, 0.0);
    });

    test('unrecorded orders earn no auto-credit', () async {
      await saveWeekSchedule();
      final r = db.buildWeeklyReport(DateTime(2026, 10, 14));
      expect(dayOf(r, '2026-10-14').workMinutes, 0);
      expect(r.missingRecordDates, contains('2026-10-14'));
    });

    test('a recorded session always wins over the auto value', () async {
      await saveWeekSchedule();
      await db.upsertOrderRecord(dateKey: '2026-10-16', completedOrders: 5);
      await db.saveManualSession(
        dateKey: '2026-10-16',
        startMinutes: 9 * 60,
        endMinutes: 11 * 60,
        breakMinutes: 0,
      );
      final r = db.buildWeeklyReport(DateTime(2026, 10, 14));
      expect(dayOf(r, '2026-10-16').workMinutes, 120);
      expect(db.effectiveMinutesForDate('2026-10-16'), 120);
    });

    test('a day off earns no auto-credit even with orders', () async {
      await saveWeekSchedule();
      await db.upsertOrderRecord(dateKey: '2026-10-15', completedOrders: 8);
      final r = db.buildWeeklyReport(DateTime(2026, 10, 14));
      expect(dayOf(r, '2026-10-15').workMinutes, 0);
      expect(r.totalOrders, 8); // orders still count, hours do not
      expect(r.totalRecordedHours, 0.0);
    });

    test('no schedule for the week means no auto-credit', () async {
      await db.upsertOrderRecord(dateKey: '2026-10-12', completedOrders: 9);
      final r = db.buildWeeklyReport(DateTime(2026, 10, 14));
      expect(dayOf(r, '2026-10-12').workMinutes, 0);
    });

    test('pure rule: effectiveWorkMinutes branches', () {
      final sched = DailySchedule(
          dateKey: '2026-10-12',
          startMinutes: 9 * 60,
          endMinutes: 17 * 60,
          breakDurationMinutes: 30);
      expect(
          effectiveWorkMinutes(
              recordedMinutes: 0, orders: 3, schedule: sched),
          450);
      expect(
          effectiveWorkMinutes(
              recordedMinutes: 90, orders: 3, schedule: sched),
          90);
      expect(
          effectiveWorkMinutes(
              recordedMinutes: 0, orders: 0, schedule: sched),
          0);
      expect(
          effectiveWorkMinutes(
              recordedMinutes: 0, orders: null, schedule: sched),
          0);
      expect(
          effectiveWorkMinutes(
              recordedMinutes: 0, orders: 3, schedule: null),
          0);
      final off = DailySchedule(dateKey: '2026-10-12', isWorkingDay: false);
      expect(
          effectiveWorkMinutes(
              recordedMinutes: 0, orders: 3, schedule: off),
          0);
    });

    test('shiftEndReminderEnabled defaults off and round-trips', () {
      expect(UserSettings().shiftEndReminderEnabled, isFalse);
      final s = UserSettings()..shiftEndReminderEnabled = true;
      final back = UserSettings.fromJson(s.toJson());
      expect(back.shiftEndReminderEnabled, isTrue);
    });
  });

  group('v27: count-on-start, paid days, day labels', () {
    test('an order counts only when delivery starts (بدأ التوصيل)',
        () async {
      const key = '2026-10-16';
      final e1 = await db.addOrderEntry(
        dateKey: key,
        timestampMillis: DateTime(2026, 10, 16, 10).millisecondsSinceEpoch,
      );
      // Created pending -> NOT counted.
      expect(db.orderRecord(key)!.completedOrders, 0);

      // Delivery starts -> counted exactly once.
      await db.updateOrderEntry(
          dateKey: key, entryId: e1.id, status: 1, pickupTimeMillis: 42);
      expect(db.orderRecord(key)!.completedOrders, 1);

      // Later lifecycle steps / re-entering start never double-count.
      await db.updateOrderEntry(dateKey: key, entryId: e1.id, status: 1);
      await db.updateOrderEntry(dateKey: key, entryId: e1.id, status: 2);
      await db.updateOrderEntry(dateKey: key, entryId: e1.id, status: 3);
      expect(db.orderRecord(key)!.completedOrders, 1);

      // A second still-pending entry changes nothing.
      final e2 = await db.addOrderEntry(
        dateKey: key,
        timestampMillis: DateTime(2026, 10, 16, 12).millisecondsSinceEpoch,
      );
      expect(db.orderRecord(key)!.completedOrders, 1);

      // Deleting the pending entry: no change. Deleting the counted
      // entry: -1.
      await db.deleteOrderEntry(dateKey: key, entryId: e2.id);
      expect(db.orderRecord(key)!.completedOrders, 1);
      await db.deleteOrderEntry(dateKey: key, entryId: e1.id);
      expect(db.orderRecord(key)!.completedOrders, 0);
    });

    test('bulk count stays immediate and composes with counted entries',
        () async {
      const key = '2026-10-17';
      await db.upsertOrderRecord(dateKey: key, completedOrders: 15);
      final e = await db.addOrderEntry(
        dateKey: key,
        timestampMillis: DateTime(2026, 10, 17, 9).millisecondsSinceEpoch,
      );
      // Pending detail entry must not inflate the bulk total.
      expect(db.orderRecord(key)!.completedOrders, 15);
      await db.updateOrderEntry(dateKey: key, entryId: e.id, status: 1);
      expect(db.orderRecord(key)!.completedOrders, 16);
      await db.deleteOrderEntry(dateKey: key, entryId: e.id);
      expect(db.orderRecord(key)!.completedOrders, 15);
    });

    test('migration formula: recomputedCountedOrders preserves bulk base',
        () {
      DailyOrderRecord rec(int total, List<int> statuses) =>
          DailyOrderRecord(
            id: 'x',
            dateKey: '2026-10-12',
            completedOrders: total,
            createdAtMillis: 0,
            updatedAtMillis: 0,
            entries: [
              for (var i = 0; i < statuses.length; i++)
                OrderEntry(
                  id: 'e$i',
                  dateKey: '2026-10-12',
                  timestampMillis: 0,
                  status: statuses[i],
                ),
            ],
          );
      // Old total counted all 3 entries; bulk base 12 survives, only
      // the 2 started entries count.
      expect(recomputedCountedOrders(rec(15, [0, 1, 3])), 14);
      // Nothing started -> only the (zero) bulk base remains.
      expect(recomputedCountedOrders(rec(2, [0, 0])), 0);
      // Inconsistent legacy data (total < entries): base clamps to 0.
      expect(recomputedCountedOrders(rec(1, [1, 2, 3])), 3);
      // Pure bulk record (no entries) is untouched.
      expect(recomputedCountedOrders(rec(7, [])), 7);
      expect(recomputedCountedOrders(rec(0, [0])), 0);
    });

    test('salary paid days: only days with >= 1 counted order', () async {
      // Week of Sun 2026-10-11.
      await db.upsertOrderRecord(dateKey: '2026-10-12', completedOrders: 0);
      await db.upsertOrderRecord(dateKey: '2026-10-13', completedOrders: 4);
      await db.saveManualSession(
        dateKey: '2026-10-14',
        startMinutes: 9 * 60,
        endMinutes: 17 * 60,
        breakMinutes: 0,
      );
      final report = db.buildWeeklyReport(DateTime(2026, 10, 14));
      // recordedDaysCount semantics unchanged: all three days have data.
      expect(report.recordedDaysCount, 3);
      // Only the 4-order day earns the daily fixed pay: the 0-order
      // record does not, and the session-only day does not.
      expect(report.paidDaysCount, 1);
      expect(report.totalOrders, 4);
    });

    test('dayStatusFor derivation', () {
      final today = DateTime(2026, 10, 22);
      // Orders worked -> work day, whatever the schedule says.
      expect(
          dayStatusFor(
              orders: 2,
              isWorkingDay: false,
              date: today,
              today: today),
          DayStatus.workDay);
      // No orders today / in the past -> day off.
      expect(
          dayStatusFor(
              orders: 0, isWorkingDay: true, date: today, today: today),
          DayStatus.dayOff);
      expect(
          dayStatusFor(
              orders: null,
              isWorkingDay: true,
              date: DateTime(2026, 10, 20),
              today: today),
          DayStatus.dayOff);
      // Future: scheduled working day gets no label yet; scheduled off
      // shows day off.
      expect(
          dayStatusFor(
              orders: null,
              isWorkingDay: true,
              date: DateTime(2026, 10, 25),
              today: today),
          DayStatus.none);
      expect(
          dayStatusFor(
              orders: null,
              isWorkingDay: false,
              date: DateTime(2026, 10, 25),
              today: today),
          DayStatus.dayOff);
    });

    test('scheduleDayChipFor derivation (v27.3)', () {
      final today = DateTime(2026, 10, 22); // a Thursday
      ScheduleDayChip chip({
        required int orders,
        required bool working,
        bool started = false,
        required DateTime date,
      }) =>
          scheduleDayChipFor(
            countedOrders: orders,
            isWorkingDay: working,
            workStartedToday: started,
            date: date,
            today: today,
          );

      // Past day with orders -> completed, even on a planned day off.
      expect(
          chip(orders: 3, working: true, date: DateTime(2026, 10, 20)),
          ScheduleDayChip.completed);
      expect(
          chip(orders: 1, working: false, date: DateTime(2026, 10, 20)),
          ScheduleDayChip.completed);
      // Past day with no orders -> day off (worked plan or not).
      expect(
          chip(orders: 0, working: true, date: DateTime(2026, 10, 20)),
          ScheduleDayChip.dayOff);
      expect(
          chip(orders: 0, working: false, date: DateTime(2026, 10, 20)),
          ScheduleDayChip.dayOff);
      // Future: planned day off -> day off; planned work day -> not
      // started.
      expect(
          chip(orders: 0, working: false, date: DateTime(2026, 10, 25)),
          ScheduleDayChip.dayOff);
      expect(
          chip(orders: 0, working: true, date: DateTime(2026, 10, 25)),
          ScheduleDayChip.notStarted);
      // Today: the day is not over — a scheduled work day with no
      // orders yet is "not started", NOT a day off; once work has
      // started it is in progress; a plan-marked off day shows day off.
      expect(chip(orders: 0, working: true, date: today),
          ScheduleDayChip.notStarted);
      expect(
          chip(orders: 0, working: true, started: true, date: today),
          ScheduleDayChip.inProgress);
      expect(chip(orders: 0, working: false, date: today),
          ScheduleDayChip.dayOff);
      // Today with counted orders -> completed.
      expect(chip(orders: 2, working: true, date: today),
          ScheduleDayChip.completed);
    });

    test('day label flips back to day-off when the last order is deleted',
        () async {
      const key = '2026-10-13';
      final e = await db.addOrderEntry(
        dateKey: key,
        timestampMillis: DateTime(2026, 10, 13, 11).millisecondsSinceEpoch,
      );
      await db.updateOrderEntry(dateKey: key, entryId: e.id, status: 1);
      DayStatus statusOf(WeeklyReport r) {
        final d = r.days.firstWhere((x) => x.dateKey == key);
        return dayStatusFor(
          orders: d.orders,
          isWorkingDay: d.isWorkingDay,
          date: DateTime(2026, 10, 13),
          today: DateTime(2026, 10, 14),
        );
      }

      expect(statusOf(db.buildWeeklyReport(DateTime(2026, 10, 14))),
          DayStatus.workDay);
      await db.deleteOrderEntry(dateKey: key, entryId: e.id);
      expect(statusOf(db.buildWeeklyReport(DateTime(2026, 10, 14))),
          DayStatus.dayOff);
    });

    test('v27.1: bulk add materializes N born-completed count-only '
        'entries; deleting one drops the total by one', () async {
      const key = '2026-10-18';
      final created = await db.addCountOnlyEntries(dateKey: key, count: 5);
      expect(created.length, 5);
      var rec = db.orderRecord(key)!;
      expect(rec.completedOrders, 5);
      expect(rec.entries.length, 5);
      expect(
          rec.entries
              .every((e) => e.countOnly && e.status == 3 && e.kmTotal == 0),
          isTrue);

      // Reports see the 5 as real orders: totals + salary paid day.
      final report = db.buildWeeklyReport(DateTime(2026, 10, 18));
      expect(report.totalOrders, 5);
      expect(report.paidDaysCount, 1);

      // Editing a count-only entry must never double-count it.
      await db.updateOrderEntry(
          dateKey: key, entryId: created.first.id, notes: 'x');
      expect(db.orderRecord(key)!.completedOrders, 5);

      // Delete one -> N-1 everywhere.
      await db.deleteOrderEntry(dateKey: key, entryId: created.first.id);
      rec = db.orderRecord(key)!;
      expect(rec.completedOrders, 4);
      expect(rec.entries.length, 4);
      expect(db.buildWeeklyReport(DateTime(2026, 10, 18)).totalOrders, 4);
    });

    test('v27.1: count-only entries compose with tracked entries',
        () async {
      const key = '2026-10-19';
      await db.addCountOnlyEntries(dateKey: key, count: 3);
      final e = await db.addOrderEntry(
        dateKey: key,
        timestampMillis: DateTime(2026, 10, 19, 9).millisecondsSinceEpoch,
      );
      // Pending tracked entry does not add on top of the bulk 3.
      expect(db.orderRecord(key)!.completedOrders, 3);
      await db.updateOrderEntry(dateKey: key, entryId: e.id, status: 1);
      expect(db.orderRecord(key)!.completedOrders, 4);
      await db.deleteOrderEntry(dateKey: key, entryId: e.id);
      expect(db.orderRecord(key)!.completedOrders, 3);
    });

    test('v27.1: schema-11 migration converts a legacy bare bulk count '
        'into deletable count-only entries, total unchanged', () async {
      // Legacy v27 state: bulk 5 stored as a bare number, no entries.
      await db.upsertOrderRecord(dateKey: '2026-10-20', completedOrders: 5);
      // Mixed legacy record: total 7 with only 1 counted entry (1
      // started + 1 pending) -> the undetailed remainder is 6.
      final started = await db.addOrderEntry(
        dateKey: '2026-10-21',
        timestampMillis: DateTime(2026, 10, 21, 9).millisecondsSinceEpoch,
      );
      await db.addOrderEntry(
        dateKey: '2026-10-21',
        timestampMillis: DateTime(2026, 10, 21, 10).millisecondsSinceEpoch,
      );
      await db.updateOrderEntry(
          dateKey: '2026-10-21', entryId: started.id, status: 1);
      await db.upsertOrderRecord(dateKey: '2026-10-21', completedOrders: 7);
      // Rewind the schema stamp to v27's and reopen: migration runs.
      await Hive.box('meta').put('schemaVersion', 10);
      await Hive.close();
      final db2 = DatabaseService();
      await db2.init(hivePath: tmp.path);

      final bare = db2.orderRecord('2026-10-20')!;
      expect(bare.completedOrders, 5);
      expect(bare.entries.length, 5);
      expect(bare.entries.every((e) => e.countOnly && e.status == 3),
          isTrue);

      final mixed = db2.orderRecord('2026-10-21')!;
      expect(mixed.completedOrders, 7);
      expect(mixed.entries.length, 8); // 2 originals + 6 converted
      expect(mixed.entries.where((e) => e.countOnly).length, 6);
      // Counted entries (started + converted) now back the whole total.
      expect(mixed.entries.where((e) => e.status >= 1).length, 7);
    });

    test('v27.1: daySummaryTallies never shows a bulk-only day as 0/0',
        () {
      DailyOrderRecord rec(int total, List<int> statuses) =>
          DailyOrderRecord(
            id: 'x',
            dateKey: '2026-10-12',
            completedOrders: total,
            createdAtMillis: 0,
            updatedAtMillis: 0,
            entries: [
              for (var i = 0; i < statuses.length; i++)
                OrderEntry(
                  id: 'e$i',
                  dateKey: '2026-10-12',
                  timestampMillis: 0,
                  status: statuses[i],
                ),
            ],
          );
      // The field bug: 5 bulk orders, zero entries -> was 0/0.
      var t = daySummaryTallies(rec(5, []));
      expect(t.completed, 5);
      expect(t.total, 5);
      expect(t.inProgress, 0);
      expect(t.pending, 0);
      // Pure-entry day is unchanged.
      t = daySummaryTallies(rec(1, [3, 1, 0]));
      expect(t.completed, 1);
      expect(t.inProgress, 1);
      expect(t.pending, 1);
      expect(t.total, 3);
      // Mixed: total 6 = 1 completed entry + 5 undetailed.
      t = daySummaryTallies(rec(6, [3, 0]));
      expect(t.completed, 6);
      expect(t.pending, 1);
      expect(t.total, 7);
      // Nothing recorded.
      t = daySummaryTallies(null);
      expect(t.completed, 0);
      expect(t.total, 0);
      // Pure conversion helper: no remainder -> no entries.
      expect(countOnlyEntriesForLegacyRemainder(rec(2, [3, 3])), isEmpty);
      expect(
          countOnlyEntriesForLegacyRemainder(rec(4, [3])).length, 3);
    });

    test('upgrade migration: old in-app default switches to Google Maps '
        'once; a later manual choice persists', () async {
      // Simulate a pre-v27 install: settings carry the old default (0 =
      // in-app) and the schema stamp is still 9.
      final s = db.settings;
      s.autoNavMode = 0;
      await db.saveSettings(s);
      await Hive.box('meta').put('schemaVersion', 9);
      await Hive.close();

      // First v27 launch: migrated to Google Maps (1).
      final db2 = DatabaseService();
      await db2.init(hivePath: tmp.path);
      expect(db2.settings.autoNavMode, 1);

      // He then picks in-app manually — the migration must never
      // re-run and override him.
      final s2 = db2.settings;
      s2.autoNavMode = 0;
      await db2.saveSettings(s2);
      await Hive.close();
      final db3 = DatabaseService();
      await db3.init(hivePath: tmp.path);
      expect(db3.settings.autoNavMode, 0);
    });
  });
}
