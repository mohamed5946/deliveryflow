import 'package:intl/intl.dart';

import '../../core/database/database_service.dart';
import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';

/// v27.4: data model + builder for the "all past weeks" PDF export.
///
/// Single responsibility: turn the stored records into plain,
/// presentation-ready rows (labels resolved, salary math done) so the
/// PDF builder only has to draw. Salary math REUSES the weekly
/// report's model — a week's earnings are exactly
/// `totalOrders × orderPrice + paidDaysCount × dailyFixedPay`, and a
/// day's earnings are its orders' pay plus the fixed pay when the day
/// was paid (≥ 1 counted order) — never re-derived differently.

class PdfDayRow {
  final String weekdayLabel;
  final String dateLabel;
  final bool isDayOff;
  final int orders;
  final double km;
  final double hours;
  final double earnings;

  const PdfDayRow({
    required this.weekdayLabel,
    required this.dateLabel,
    required this.isDayOff,
    required this.orders,
    required this.km,
    required this.hours,
    required this.earnings,
  });
}

class PdfWeekSection {
  final String rangeLabel;
  final List<PdfDayRow> days;
  final int totalOrders;
  final double totalKm;
  final double totalHours;
  final double totalEarnings;

  const PdfWeekSection({
    required this.rangeLabel,
    required this.days,
    required this.totalOrders,
    required this.totalKm,
    required this.totalHours,
    required this.totalEarnings,
  });
}

class PastWeeksReportData {
  final List<PdfWeekSection> weeks;
  final int totalOrders;
  final double totalKm;
  final double totalHours;
  final double totalEarnings;
  final DateTime generatedAt;

  const PastWeeksReportData({
    required this.weeks,
    required this.totalOrders,
    required this.totalKm,
    required this.totalHours,
    required this.totalEarnings,
    required this.generatedAt,
  });
}

class PastWeeksReportBuilder {
  PastWeeksReportBuilder(this._db);

  final DatabaseService _db;

  /// Hard bound for the backward week scan (2 years) — the export only
  /// includes weeks that actually hold recorded data.
  static const int maxWeeksBack = 104;

  PastWeeksReportData build({
    required String locale,
    required double orderPrice,
    required double dailyFixedPay,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final dateFmt = DateFormat.yMMMd(locale);
    final sections = <PdfWeekSection>[];
    var grandOrders = 0;
    var grandKm = 0.0;
    var grandHours = 0.0;
    var grandEarnings = 0.0;

    for (var i = 0; i < maxWeeksBack; i++) {
      final probe = WeekCalendar.addDays(today, -7 * i);
      final report = _db.buildWeeklyReport(probe);
      if (report.recordedDaysCount == 0) continue;

      final rows = <PdfDayRow>[
        for (final d in report.days)
          _dayRow(
            d,
            locale: locale,
            today: today,
            orderPrice: orderPrice,
            dailyFixedPay: dailyFixedPay,
          ),
      ];
      // The exact WeeklyReport salary model for the week.
      final weekEarnings = report.totalOrders * orderPrice +
          report.paidDaysCount * dailyFixedPay;
      final start = WeekCalendar.parseDateKey(report.weekStartKey);
      final end = WeekCalendar.parseDateKey(report.weekEndKey);
      sections.add(PdfWeekSection(
        rangeLabel: '${dateFmt.format(start)} – ${dateFmt.format(end)}',
        days: rows,
        totalOrders: report.totalOrders,
        totalKm: report.totalKm,
        totalHours: report.totalRecordedHours,
        totalEarnings: weekEarnings,
      ));
      grandOrders += report.totalOrders;
      grandKm += report.totalKm;
      grandHours += report.totalRecordedHours;
      grandEarnings += weekEarnings;
    }

    return PastWeeksReportData(
      weeks: sections,
      totalOrders: grandOrders,
      totalKm: grandKm,
      totalHours: grandHours,
      totalEarnings: grandEarnings,
      generatedAt: today,
    );
  }

  PdfDayRow _dayRow(
    DayBreakdown d, {
    required String locale,
    required DateTime today,
    required double orderPrice,
    required double dailyFixedPay,
  }) {
    final date = WeekCalendar.parseDateKey(d.dateKey);
    final status = dayStatusFor(
      orders: d.orders,
      isWorkingDay: d.isWorkingDay,
      date: date,
      today: today,
    );
    final orders = d.orders ?? 0;
    final paid = orders >= 1;
    return PdfDayRow(
      weekdayLabel: DateFormat.EEEE(locale).format(date),
      dateLabel: DateFormat.MMMd(locale).format(date),
      isDayOff: status == DayStatus.dayOff,
      orders: orders,
      km: d.kmTotal,
      hours: d.workMinutes / 60.0,
      earnings: orders * orderPrice + (paid ? dailyFixedPay : 0),
    );
  }
}
