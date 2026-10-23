import 'dart:io';
import 'dart:typed_data';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:deliveryflow/features/weekly_reports/past_weeks_report.dart';
import 'package:deliveryflow/features/weekly_reports/reports_pdf_builder.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';

/// v27.4: the all-past-weeks PDF export — the data builder must
/// reuse the WeeklyReport salary model exactly (orders × price +
/// paid days × fixed), newest week first, and the PDF must generate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late DatabaseService db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('df_pdf_');
    // The app initializes intl locales in main(); mirror it here —
    // the builder formats weekday/date labels with DateFormat.
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
    db = DatabaseService();
    await db.init(hivePath: tmp.path);

    final now = DateTime.now();
    final thisSunday = WeekCalendar.weekStart(now);
    // Current week, Sunday: 4 orders, 10 km, 7 h session (9→17, 1h break).
    final sunKey = WeekCalendar.dateKey(thisSunday);
    await db.upsertOrderRecord(dateKey: sunKey, completedOrders: 4);
    await db.addOrderEntry(
      dateKey: sunKey,
      timestampMillis: now.millisecondsSinceEpoch,
      kmOut: 6,
      kmBack: 4,
    );
    await db.saveManualSession(
      dateKey: sunKey,
      startMinutes: 9 * 60,
      endMinutes: 17 * 60,
      breakMinutes: 60,
    );
    // Last week: a paid day (3 orders) and a recorded 0-order day off.
    final lastSunday = WeekCalendar.addDays(thisSunday, -7);
    await db.upsertOrderRecord(
      dateKey: WeekCalendar.dateKey(WeekCalendar.addDays(lastSunday, 2)),
      completedOrders: 3,
    );
    await db.upsertOrderRecord(
      dateKey: WeekCalendar.dateKey(WeekCalendar.addDays(lastSunday, 3)),
      completedOrders: 0,
    );
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('builder: weeks newest-first with exact salary-model totals', () {
    final data = PastWeeksReportBuilder(db).build(
      locale: 'ar',
      orderPrice: 10,
      dailyFixedPay: 100,
    );
    expect(data.weeks.length, 2);

    final current = data.weeks[0];
    expect(current.totalOrders, 4);
    expect(current.totalKm, 10);
    expect(current.totalHours, 7);
    // 4 orders × 10 + 1 paid day × 100.
    expect(current.totalEarnings, 140);
    final sunday = current.days[0];
    expect(sunday.orders, 4);
    expect(sunday.isDayOff, isFalse);
    expect(sunday.earnings, 140);

    final last = data.weeks[1];
    expect(last.totalOrders, 3);
    // 3 orders × 10 + 1 paid day × 100.
    expect(last.totalEarnings, 130);
    // The recorded 0-order day is a day off and earns nothing.
    final offDay = last.days[3];
    expect(offDay.orders, 0);
    expect(offDay.isDayOff, isTrue);
    expect(offDay.earnings, 0);
    final paidDay = last.days[2];
    expect(paidDay.isDayOff, isFalse);
    expect(paidDay.earnings, 130);

    // Grand totals fold the weeks.
    expect(data.totalOrders, 7);
    expect(data.totalKm, 10);
    expect(data.totalHours, 7);
    expect(data.totalEarnings, 270);
  });

  test('pdf bytes generate without throwing', () async {
    final data = PastWeeksReportBuilder(db).build(
      locale: 'ar',
      orderPrice: 10,
      dailyFixedPay: 100,
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
    final Uint8List bytes = await ReportsPdfBuilder().build(data, l10n);
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
