import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:deliveryflow/features/weekly_reports/past_weeks_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';

/// v27.6: the flat per-order bonus («بونص ثابت لكل أوردر») pays a
/// fixed amount on EVERY counted order — detailed completed AND
/// count-only, never pending — via UserSettings.flatOrderBonusEgp.
/// It flows through the shared WeeklyReport.salaryTotal (so the
/// report card, Home card and PDF agree) and into the PDF data per
/// day. 0 (the default) disables it cleanly, and it is independent of
/// the distance-bonus toggles and the manual bonuses.
void main() {
  late Directory tmp;
  late DatabaseService db;
  late String sunKey;
  late String monKey;

  setUp(() async {
    await initializeDateFormatting('en');
    tmp = await Directory.systemTemp.createTemp('df_flat_');
    db = DatabaseService();
    await db.init(hivePath: tmp.path);

    final start = WeekCalendar.weekStart(DateTime.now());
    sunKey = WeekCalendar.dateKey(start);
    monKey = WeekCalendar.dateKey(start.add(const Duration(days: 1)));

    // Sunday: 2 detailed completed orders (small km — no distance
    // bonus) + 1 count-only entry = 3 counted orders.
    for (var i = 0; i < 2; i++) {
      final e = await db.addOrderEntry(
        dateKey: sunKey,
        timestampMillis: DateTime.now().millisecondsSinceEpoch + i,
        kmOut: 3,
        kmBack: 2,
      );
      await db.updateOrderEntry(
          dateKey: sunKey, entryId: e.id, status: 3);
    }
    await db.addCountOnlyEntries(dateKey: sunKey, count: 1);

    // Monday: 1 PENDING detailed order — must NOT earn the bonus.
    await db.addOrderEntry(
      dateKey: monKey,
      timestampMillis: DateTime.now().millisecondsSinceEpoch,
      kmOut: 3,
      kmBack: 2,
    );
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  // v27.17: open the period at epoch 0, so it predates every seeded
  // order (this file tests counted-vs-pending and totals, not the
  // instant timing — that is bonus_periods_test/bonus_instant_test).
  Future<void> setFlat(double v) async {
    final s = db.settings;
    s.applyFlatBonus(v, 0);
    await db.saveSettings(s);
  }

  test('settings: defaults to 0 and round-trips (box + JSON)', () async {
    expect(db.settings.flatOrderBonusEgp, 0);

    await setFlat(7.5);
    expect(db.settings.flatOrderBonusEgp, 7.5);
    expect(db.settings.flatBonusAt(
        DateTime.now().millisecondsSinceEpoch), 7.5);

    final clone = UserSettings.fromJson(db.settings.toJson());
    expect(clone.flatOrderBonusEgp, 7.5);
    expect(clone.flatBonusAt(
        DateTime.now().millisecondsSinceEpoch), 7.5);
  });

  test('report: counted orders only, per-day and week totals',
      () async {
    await setFlat(10);
    final report = db.buildWeeklyReport(DateTime.now());

    expect(report.totalOrders, 3); // pending Monday order excluded
    expect(report.flatOrderBonusEgp, 10);
    expect(report.totalFlatBonus, 30);
    expect(report.days[0].flatBonus, 30); // Sunday: 3 counted × 10
    expect(report.days[1].flatBonus, 0); // Monday: pending only

    // Salary: 3×10 (orders) + 1×100 (one paid day) + 0 distance
    // + 0 manual + 30 flat.
    expect(report.paidDaysCount, 1);
    expect(
      report.salaryTotal(orderPrice: 10, dailyFixedPay: 100),
      160,
    );
  });

  test('report: independent of the distance-bonus toggle', () async {
    await setFlat(10);
    final s = db.settings;
    s.distanceBonusEnabled = false;
    await db.saveSettings(s);

    final report = db.buildWeeklyReport(DateTime.now());
    expect(report.distanceBonusEnabled, isFalse);
    expect(report.totalDistanceBonus, 0);
    expect(report.totalFlatBonus, 30);
    expect(
      report.salaryTotal(orderPrice: 10, dailyFixedPay: 100),
      160,
    );
  });

  test('report: 0 disables the flat bonus cleanly', () async {
    final report = db.buildWeeklyReport(DateTime.now());
    expect(report.totalFlatBonus, 0);
    expect(report.days[0].flatBonus, 0);
    expect(
      report.salaryTotal(orderPrice: 10, dailyFixedPay: 100),
      130, // 3×10 + 1×100, nothing else
    );
  });

  test('PDF data: week line and per-day earnings carry the bonus',
      () async {
    await setFlat(10);
    final data = PastWeeksReportBuilder(db)
        .build(locale: 'en', orderPrice: 10, dailyFixedPay: 100);

    final week = data.weeks.single;
    expect(week.flatBonusTotal, 30);
    expect(week.totalEarnings, 160);

    // Rows keep Sun→Sat order: [0] Sunday, [1] Monday.
    final sunday = week.days[0];
    expect(sunday.orders, 3);
    // 3 orders × 10 + paid day 100 + 30 flat.
    expect(sunday.earnings, 160);
    final monday = week.days[1];
    expect(monday.orders, 0);
    expect(monday.earnings, 0);
  });
}
