import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/date_time/week_calendar.dart';
import '../../core/money_format.dart';
import '../../l10n/gen/app_localizations.dart';
import 'past_weeks_report.dart';

/// v27.4: draws the "all past weeks" report as a clean RTL Arabic PDF.
///
/// Single responsibility: layout only. All numbers and labels arrive
/// ready-made in [PastWeeksReportData]; the salary math lives in
/// [PastWeeksReportBuilder]. The bundled Cairo font is embedded so
/// Arabic renders shaped and RTL — without it the PDF would show
/// disconnected, reversed glyphs.
class ReportsPdfBuilder {
  static const String _fontAsset = 'assets/fonts/Cairo.ttf';

  /// [singleWeek] (v27.5): the data holds exactly one week's
  /// section, whose own totals row closes the document — the
  /// grand-totals table would only repeat it, so it is skipped.
  Future<Uint8List> build(
      PastWeeksReportData data, AppLocalizations l10n,
      {bool singleWeek = false}) async {
    final fontData = await rootBundle.load(_fontAsset);
    final font = pw.Font.ttf(fontData);
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    final generatedLabel =
        DateFormat.yMMMd(l10n.localeName == 'ar' ? 'ar' : 'en')
            .format(data.generatedAt);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 32),
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          pw.Text(
            'DeliveryFlow — ${l10n.pdfReportTitle}',
            style: const pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${l10n.pdfGeneratedOn}: $generatedLabel',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          for (final week in data.weeks) ...[
            _weekTable(week, l10n),
            pw.SizedBox(height: 18),
          ],
          if (!singleWeek)
            _totalsTable(
              title: l10n.pdfGrandTotals,
              orders: data.totalOrders,
              km: data.totalKm,
              hours: data.totalHours,
              earnings: data.totalEarnings,
              l10n: l10n,
            ),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _weekTable(PdfWeekSection week, AppLocalizations l10n) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          week.rangeLabel,
          style: const pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue800,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.4),
            1: pw.FlexColumnWidth(1.3),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(1.1),
            4: pw.FlexColumnWidth(1.1),
            5: pw.FlexColumnWidth(1.5),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blue50),
              children: [
                _cell(l10n.pdfColDate, bold: true),
                _cell(l10n.pdfColStatus, bold: true),
                _cell(l10n.totalOrders, bold: true),
                _cell(l10n.kmUnit, bold: true),
                _cell(l10n.pdfColHours, bold: true),
                _cell('${l10n.pdfColEarnings} (${l10n.egpUnit})', bold: true),
              ],
            ),
            for (final d in week.days)
              pw.TableRow(
                children: [
                  _cell('${d.weekdayLabel} ${d.dateLabel}'),
                  _cell(d.isDayOff ? l10n.dayOff : l10n.workingDay),
                  _cell('${d.orders}'),
                  _cell(WeekCalendar.formatKm(d.km)),
                  _cell(WeekCalendar.formatHours(d.hours)),
                  _cell(formatMoney(d.earnings)),
                ],
              ),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _cell(l10n.pdfWeekTotals, bold: true),
                _cell(''),
                _cell('${week.totalOrders}', bold: true),
                _cell(WeekCalendar.formatKm(week.totalKm), bold: true),
                _cell(WeekCalendar.formatHours(week.totalHours), bold: true),
                _cell(formatMoney(week.totalEarnings), bold: true),
              ],
            ),
            // v27.5: the week's manual bonuses as their own line
            // (the amount is already inside the week totals above).
            if (week.manualBonusTotal > 0)
              pw.TableRow(
                children: [
                  _cell(l10n.manualBonusLabel, bold: true),
                  _cell(''),
                  _cell(''),
                  _cell(''),
                  _cell(''),
                  _cell(formatMoney(week.manualBonusTotal), bold: true),
                ],
              ),
            // v27.6: the week's flat per-order bonuses as their own
            // line (already inside the week totals above).
            if (week.flatBonusTotal > 0)
              pw.TableRow(
                children: [
                  _cell(l10n.flatOrdersBonusLabel, bold: true),
                  _cell(''),
                  _cell(''),
                  _cell(''),
                  _cell(''),
                  _cell(formatMoney(week.flatBonusTotal), bold: true),
                ],
              ),
          ],
        ),
      ],
    );
  }

  pw.Widget _totalsTable({
    required String title,
    required int orders,
    required double km,
    required double hours,
    required double earnings,
    required AppLocalizations l10n,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(1.3),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.1),
        4: pw.FlexColumnWidth(1.1),
        5: pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue50),
          children: [
            _cell(title, bold: true),
            _cell(''),
            _cell('$orders', bold: true),
            _cell(WeekCalendar.formatKm(km), bold: true),
            _cell(WeekCalendar.formatHours(hours), bold: true),
            _cell(formatMoney(earnings), bold: true),
          ],
        ),
      ],
    );
  }

  pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
