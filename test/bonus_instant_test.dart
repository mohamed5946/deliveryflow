import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:deliveryflow/features/weekly_reports/past_weeks_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';

/// v27.17 proof tests for Mohamed's exact rule (2026-10-26):
/// «البونص ده لو عملت أوردر دلوقتي يتحسب وجيت شيلته بعد الأوردر
/// ميتحسبش للي بعده، حتي لو في نفس اليوم» — per-ORDER MOMENT, not
/// per calendar day. Each test below is one clause of that rule,
/// stated as the scenario Mohamed himself described.
int at(int d, int h, [int min = 0]) =>
    DateTime(2026, 10, d, h, min).millisecondsSinceEpoch;

void main() {
  late Directory tmp;
  late DatabaseService db;

  Future<void> order(int day, int hour,
      {double kmOut = 3, double kmBack = 2, double? manual}) async {
    final e = await db.addOrderEntry(
      dateKey: '2026-10-$day',
      timestampMillis: at(day, hour),
      createdAtMillis: at(day, hour),
      kmOut: kmOut,
      kmBack: kmBack,
    );
    await db.updateOrderEntry(
        dateKey: '2026-10-$day',
        entryId: e.id,
        status: 3,
        manualBonusEgp: manual);
  }

  Future<void> apply(void Function(UserSettings s) change) async {
    final s = db.settings;
    change(s);
    await db.saveSettings(s);
  }

  setUp(() async {
    await initializeDateFormatting('en');
    tmp = await Directory.systemTemp.createTemp('df_bonus_instant_');
    db = DatabaseService();
    await db.init(hivePath: tmp.path);
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('order at 10:00 with bonus on, deleted at 11:00, order at '
      '12:00 same day: first keeps bonus, second gets 0', () async {
    await order(26, 10);
    await order(26, 12);
    await apply((s) => s.applyFlatBonus(5, at(26, 9)));
    await apply((s) => s.applyFlatBonus(0, at(26, 11)));
    final r =
        db.buildWeeklyReport(WeekCalendar.parseDateKey('2026-10-25'));
    expect(r.totalFlatBonus, 5);
    expect(r.days[1].flatBonus, 5); // Monday Oct 26: 5 + 0
  });

  test('order before a 10:00 set gets 0, order after gets bonus, '
      'same day', () async {
    await order(26, 9);
    await order(26, 11);
    await apply((s) => s.applyFlatBonus(5, at(26, 10)));
    final r =
        db.buildWeeklyReport(WeekCalendar.parseDateKey('2026-10-25'));
    expect(r.totalFlatBonus, 5);
  });

  test('amount change mid-day splits orders by moment', () async {
    await order(26, 9);
    await order(26, 13);
    await apply((s) => s.applyFlatBonus(5, at(26, 8)));
    await apply((s) => s.applyFlatBonus(8, at(26, 12)));
    final r =
        db.buildWeeklyReport(WeekCalendar.parseDateKey('2026-10-25'));
    expect(r.totalFlatBonus, 13); // 5 + 8
  });

  test('distance toggle mid-day splits the same way', () async {
    await order(26, 10, kmOut: 8, kmBack: 7); // 15km
    await order(26, 12, kmOut: 8, kmBack: 7);
    await apply((s) => s.applyDistanceToggle(true, at(26, 9)));
    await apply((s) => s.applyDistanceToggle(false, at(26, 11)));
    final r =
        db.buildWeeklyReport(WeekCalendar.parseDateKey('2026-10-25'));
    expect(r.totalDistanceBonus, 10); // only the 10:00 order
  });

  test('distance tier change mid-day splits the same way', () async {
    await order(26, 10, kmOut: 8, kmBack: 7); // 15km, old tiers -> 10
    await order(26, 12, kmOut: 8, kmBack: 7); // 15km, new tiers -> 12
    await apply((s) => s.applyDistanceToggle(true, at(26, 9)));
    await apply((s) => s.applyDistanceTiers([
          const DistanceBonusTier(fromKm: 12, bonusEgp: 7),
          const DistanceBonusTier(fromKm: 15, bonusEgp: 12),
          const DistanceBonusTier(fromKm: 20, bonusEgp: 20),
        ], at(26, 11)));
    final r =
        db.buildWeeklyReport(WeekCalendar.parseDateKey('2026-10-25'));
    expect(r.totalDistanceBonus, 22); // 10 + 12
  });

  test('manual per-order bonus is unchanged and isolated', () async {
    await order(26, 10, manual: 25);
    await order(26, 12);
    await apply((s) => s.applyFlatBonus(5, at(26, 9)));
    await apply((s) => s.applyFlatBonus(0, at(26, 11)));
    final r =
        db.buildWeeklyReport(WeekCalendar.parseDateKey('2026-10-25'));
    // Manual survives the flat deletion untouched; flat splits.
    expect(r.totalManualBonus, 25);
    expect(r.totalFlatBonus, 5);
    expect(db.orderEntries('2026-10-26').map((e) => e.manualBonusEgp),
        [25, 0]);
  });

  test('salary totals agree across Home/Report/PDF for a mixed '
      'same-day scenario', () async {
    await order(26, 8, kmOut: 8, kmBack: 7); // before: nothing
    await order(26, 10, kmOut: 8, kmBack: 7, manual: 25); // both: 5+10
    await order(26, 12, kmOut: 8, kmBack: 7); // after deletes: nothing
    await apply((s) => s.applyFlatBonus(5, at(26, 9)));
    await apply((s) => s.applyDistanceToggle(true, at(26, 9)));
    await apply((s) => s.applyFlatBonus(0, at(26, 11)));
    await apply((s) => s.applyDistanceToggle(false, at(26, 11)));
    final r =
        db.buildWeeklyReport(WeekCalendar.parseDateKey('2026-10-25'));
    // Home card and Report card both read salaryTotal; PDF reads
    // the same WeeklyReport. 3×10 + 1×100 + 10 + 25 + 5 = 170.
    expect(r.salaryTotal(orderPrice: 10, dailyFixedPay: 100), 170);
    final pdf = PastWeeksReportBuilder(db).build(
        locale: 'en', orderPrice: 10, dailyFixedPay: 100);
    expect(pdf.weeks.single.totalEarnings, 170);
    expect(
        pdf.weeks.single.days.fold(0.0, (sum, d) => sum + d.earnings),
        170);
  });

  test('DST fall-back week does not break instant comparisons',
      () async {
    // Orders straddling the Oct 29 fall-back, split by a deletion
    // at midnight Oct 30: millis ordering, not calendar dates,
    // decides — no duplicated or skipped day.
    await order(29, 22);
    await order(30, 1);
    await apply((s) => s.applyFlatBonus(5, at(29, 21)));
    await apply((s) => s.applyFlatBonus(0, at(30, 0)));
    final r =
        db.buildWeeklyReport(WeekCalendar.parseDateKey('2026-10-25'));
    expect(r.days[4].flatBonus, 5); // Thu Oct 29 keeps it
    expect(r.days[5].flatBonus, 0); // Fri Oct 30 gets 0
    expect(r.totalFlatBonus, 5);
  });
}
