import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:deliveryflow/features/weekly_reports/past_weeks_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';

/// v27.5: manual per-order bonus (بونص إضافي) — a plain EGP amount on
/// any detailed order. It flows into day + week totals, the shared
/// salary, and the PDF data, and it is NOT governed by the
/// distance-bonus toggles.
void main() {
  late Directory tmp;
  late DatabaseService db;
  late String sunKey;
  late String weekKey;
  late String firstEntryId;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('df_manualbonus_');
    await initializeDateFormatting('en');
    db = DatabaseService();
    await db.init(hivePath: tmp.path);

    final thisSunday = WeekCalendar.weekStart(DateTime.now());
    weekKey = WeekCalendar.dateKey(thisSunday);
    sunKey = weekKey;

    // Sunday: a 15 km completed order carrying a 25 EGP manual bonus,
    // and a 5 km completed order with none.
    final e1 = await db.addOrderEntry(
      dateKey: sunKey,
      timestampMillis: DateTime.now().millisecondsSinceEpoch,
      kmOut: 8,
      kmBack: 7,
    );
    firstEntryId = e1.id;
    await db.updateOrderEntry(
      dateKey: sunKey,
      entryId: e1.id,
      status: 3,
      manualBonusEgp: 25,
    );
    final e2 = await db.addOrderEntry(
      dateKey: sunKey,
      timestampMillis: DateTime.now().millisecondsSinceEpoch,
      kmOut: 3,
      kmBack: 2,
    );
    await db.updateOrderEntry(dateKey: sunKey, entryId: e2.id, status: 3);

    // v27.16: distance bonus is OFF by default — explicitly enable
    // it from this Sunday so the 15 km order's +10 still applies in
    // the expectations below (fresh-user zero-bonus behaviour is
    // covered in bonus_periods_test.dart).
    final settings = db.settings;
    settings.applyDistanceToggle(true, sunKey);
    await db.saveSettings(settings);
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('manual bonus flows into day + week totals and the salary', () {
    final entry = db.orderEntries(sunKey).first;
    expect(entry.manualBonusEgp, 25);

    final r = db.buildWeeklyReport(DateTime.now());
    expect(r.days[0].manualBonus, 25);
    expect(r.totalManualBonus, 25);
    // Distance bonus still applies alongside: 15 km -> +10.
    expect(r.totalDistanceBonus, 10);
    // 2 orders × 10 + 1 paid day × 100 + 10 distance + 25 manual.
    expect(r.salaryTotal(orderPrice: 10, dailyFixedPay: 100), 155);
  });

  test('PDF data carries the manual bonus in day + week figures', () {
    final data = PastWeeksReportBuilder(db).build(
      locale: 'en',
      orderPrice: 10,
      dailyFixedPay: 100,
    );
    final week = data.weeks.single;
    expect(week.manualBonusTotal, 25);
    expect(week.totalEarnings, 155);
    final sunday = week.days[0];
    expect(sunday.earnings, 155);
  });

  test('clearing the bonus (0) removes it everywhere', () async {
    await db.updateOrderEntry(
      dateKey: sunKey,
      entryId: firstEntryId,
      manualBonusEgp: 0,
    );
    final r = db.buildWeeklyReport(DateTime.now());
    expect(r.totalManualBonus, 0);
    // Only the distance bonus remains in the salary.
    expect(r.salaryTotal(orderPrice: 10, dailyFixedPay: 100), 130);
  });

  test('manual bonus counts even when the week\'s distance bonus is off',
      () async {
    final settings = db.settings
      ..distanceBonusWeekOverrides = {weekKey: false};
    await db.saveSettings(settings);
    final r = db.buildWeeklyReport(DateTime.now());
    expect(r.totalDistanceBonus, 0);
    expect(r.totalManualBonus, 25);
    // 2 orders × 10 + 1 paid day × 100 + 0 distance + 25 manual.
    expect(r.salaryTotal(orderPrice: 10, dailyFixedPay: 100), 145);

    final data = PastWeeksReportBuilder(db).build(
      locale: 'en',
      orderPrice: 10,
      dailyFixedPay: 100,
    );
    expect(data.weeks.single.totalEarnings, 145);
    expect(data.weeks.single.manualBonusTotal, 25);
  });
}
