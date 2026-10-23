import 'package:intl/intl.dart';

import '../../core/database/database_service.dart';
import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';

/// v27.4: data model + builder for the "all past weeks" PDF export.
/// v27.5: the builder also lists the exportable weeks
/// ([availableWeeks]) and can scope the data to a single week
/// (`onlyWeekStartKey`).
///
/// Single responsibility: turn the stored records into plain,
/// presentation-ready rows (labels resolved, salary math done) so the
/// PDF builder only has to draw. Salary math REUSES the weekly
/// report's model — a week's earnings are exactly
/// [WeeklyReport.salaryTotal] (orders × price + paid days × fixed +
/// distance bonuses + manual bonuses + flat per-order bonuses), and
/// a day's earnings are its orders' pay plus the fixed pay when the
/// day was paid (≥ 1 counted order) plus that day's bonuses — never
/// re-derived differently.

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
  /// Sunday date key (yyyy-MM-dd) identifying this week — the scope
  /// key the export chooser passes back for a single-week export.
  final String weekStartKey;
  final String rangeLabel;
  final List<PdfDayRow> days;
  final int totalOrders;
  final double totalKm;
  final double totalHours;
  final double totalEarnings;

  /// v27.5: the week's Σ manual per-order bonuses — drawn as its own
  /// line in the week table (it is already inside [totalEarnings]).
  final double manualBonusTotal;

  /// v27.6: the week's Σ flat per-order bonuses — drawn as its own
  /// line in the week table (it is already inside [totalEarnings]).
  final double flatBonusTotal;

  const PdfWeekSection({
    required this.weekStartKey,
    required this.rangeLabel,
    required this.days,
    required this.totalOrders,
    required this.totalKm,
    required this.totalHours,
    required this.totalEarnings,
    this.manualBonusTotal = 0,
    this.flatBonusTotal = 0,
  });
}

/// One selectable entry in the PDF export scope chooser (v27.5).
class PdfWeekOption {
  final String weekStartKey;
  final String rangeLabel;

  const PdfWeekOption({
    required this.weekStartKey,
    required this.rangeLabel,
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

  /// Weeks that hold recorded data, newest first — the entries the
  /// export scope chooser lists under «كل الأسابيع» (v27.5).
  List<PdfWeekOption> availableWeeks({
    required String locale,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final dateFmt = DateFormat.yMMMd(locale);
    final options = <PdfWeekOption>[];
    for (var i = 0; i < maxWeeksBack; i++) {
      final probe = WeekCalendar.addDays(today, -7 * i);
      final report = _db.buildWeeklyReport(probe);
      if (report.recordedDaysCount == 0) continue;
      final start = WeekCalendar.parseDateKey(report.weekStartKey);
      final end = WeekCalendar.parseDateKey(report.weekEndKey);
      options.add(PdfWeekOption(
        weekStartKey: report.weekStartKey,
        rangeLabel: '${dateFmt.format(start)} – ${dateFmt.format(end)}',
      ));
    }
    return options;
  }

  /// Builds the export data. With [onlyWeekStartKey] null (default)
  /// every week with data is included; with a Sunday date key, only
  /// that week's section is included (v27.5 single-week export) and
  /// the totals fold that week alone.
  PastWeeksReportData build({
    required String locale,
    required double orderPrice,
    required double dailyFixedPay,
    DateTime? now,
    String? onlyWeekStartKey,
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
      if (onlyWeekStartKey != null &&
          report.weekStartKey != onlyWeekStartKey) {
        continue;
      }

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
      // The exact WeeklyReport salary model for the week (v27.5:
      // the shared salaryTotal — orders, fixed pay, both bonuses).
      final weekEarnings = report.salaryTotal(
        orderPrice: orderPrice,
        dailyFixedPay: dailyFixedPay,
      );
      final start = WeekCalendar.parseDateKey(report.weekStartKey);
      final end = WeekCalendar.parseDateKey(report.weekEndKey);
      sections.add(PdfWeekSection(
        weekStartKey: report.weekStartKey,
        rangeLabel: '${dateFmt.format(start)} – ${dateFmt.format(end)}',
        days: rows,
        totalOrders: report.totalOrders,
        totalKm: report.totalKm,
        totalHours: report.totalRecordedHours,
        totalEarnings: weekEarnings,
        manualBonusTotal: report.totalManualBonus,
        flatBonusTotal: report.totalFlatBonus,
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
      // v27.5: day earnings carry the day's distance + manual bonuses,
      // matching the in-app salary model exactly. v27.6 adds the
      // day's flat per-order bonuses the same way.
      earnings: orders * orderPrice +
          (paid ? dailyFixedPay : 0) +
          d.distanceBonus +
          d.manualBonus +
          d.flatBonus,
    );
  }
}
