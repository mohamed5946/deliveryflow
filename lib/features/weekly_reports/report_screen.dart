import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';

/// Weekly report: totals, averages (recorded days only), best day,
/// previous-week comparison, charts, share-as-text and CSV export.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  DateTime _anchor = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale =
        ref.watch(settingsProvider.select((s) => s.languageCode));
    final loc = locale == 'ar' ? 'ar' : 'en';

    final reportAsync = ref.watch(weeklyReportProvider(_anchor));
    final prevAsync = ref.watch(
        weeklyReportProvider(WeekCalendar.addDays(_anchor, -7)));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reportTitle),
        actions: [
          IconButton(
            tooltip: l10n.previousWeek,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => setState(
                () => _anchor = WeekCalendar.addDays(_anchor, -7)),
          ),
          IconButton(
            tooltip: l10n.nextWeek,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => setState(
                () => _anchor = WeekCalendar.addDays(_anchor, 7)),
          ),
        ],
      ),
      body: reportAsync.when(
        loading: () => const GlassLoading(),
        error: (e, _) => Center(child: Text('$e')),
        data: (r) {
          final start = WeekCalendar.parseDateKey(r.weekStartKey);
          final end = WeekCalendar.parseDateKey(r.weekEndKey);
          final range =
              '${DateFormat.yMMMd(loc).format(start)} – ${DateFormat.yMMMd(loc).format(end)}';
          return ListView(
            padding: GlassTokens.screenPadding,
            children: [
              Text(range,
                  style: text.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              if (r.missingRecordDates.isNotEmpty)
                Text(
                  '${l10n.incompleteWeek} (${l10n.missingRecords}: ${r.missingRecordDates.length})',
                  style: text.bodySmall?.copyWith(
                      color: scheme.tertiary,
                      fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 12),
              // Totals
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: l10n.totalOrders,
                      value: '${r.totalOrders}',
                      icon: Icons.shopping_bag_rounded,
                      accent: const Color(0xFF38E1FF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: l10n.totalRecordedHours,
                      value: WeekCalendar.formatHours(
                          r.totalRecordedHours),
                      icon: Icons.schedule_rounded,
                      accent: const Color(0xFF8A6BFF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: l10n.totalPlannedHoursLabel,
                      value: WeekCalendar.formatHours(
                          r.totalPlannedHours),
                      icon: Icons.event_note_rounded,
                      accent: const Color(0xFF4D7CFE),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: l10n.ordersPerHour,
                      value: r.ordersPerWorkingHour == null
                          ? '–'
                          : r.ordersPerWorkingHour!
                              .toStringAsFixed(1),
                      icon: Icons.speed_rounded,
                      accent: const Color(0xFF22C55E),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: l10n.avgOrdersWorkingDay,
                      value: r.averageOrdersPerWorkingDay == null
                          ? '–'
                          : r.averageOrdersPerWorkingDay!
                              .toStringAsFixed(1),
                      icon: Icons.trending_up_rounded,
                      accent: const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: l10n.avgHoursWorkingDay,
                      value: r.averageHoursPerWorkingDay == null
                          ? '–'
                          : WeekCalendar.formatHours(
                              r.averageHoursPerWorkingDay!),
                      icon: Icons.timelapse_rounded,
                      accent: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Distance totals
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.route_rounded,
                            size: 20, color: Color(0xFF38E1FF)),
                        const SizedBox(width: 8),
                        Text(l10n.weekKmLabel,
                            style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800)),
                        const Spacer(),
                        Text(
                          '${WeekCalendar.formatKm(r.totalKm)} ${l10n.kmUnit}',
                          style: text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF38E1FF)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _kmStat(
                              context,
                              l10n.kmOutLabel,
                              WeekCalendar.formatKm(r.totalKmOut),
                              l10n),
                        ),
                        Expanded(
                          child: _kmStat(
                              context,
                              l10n.kmBackLabel,
                              WeekCalendar.formatKm(r.totalKmBack),
                              l10n),
                        ),
                        Expanded(
                          child: _kmStat(
                              context,
                              l10n.avgKmPerDay,
                              r.recordedDaysCount == 0
                                  ? '–'
                                  : WeekCalendar.formatKm(
                                      r.totalKm / r.recordedDaysCount),
                              l10n),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Weekly salary
              _salaryCard(context, ref, l10n, r, text, scheme),
              const SizedBox(height: 12),
              // Best day + comparison
              GlassCard(
                child: Column(
                  children: [
                    _kv(l10n.bestDay,
                        r.bestDayKey == null
                            ? '–'
                            : DateFormat.EEEE(loc).format(
                                WeekCalendar.parseDateKey(
                                    r.bestDayKey!)),
                        text),
                    const Divider(height: 16),
                    prevAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (p) => Column(
                        children: [
                          _kv(
                              '${l10n.totalOrders} (${l10n.vsLastWeek})',
                              _delta(r.totalOrders,
                                  p.totalOrders),
                              text),
                          _kv(
                              '${l10n.totalRecordedHours} (${l10n.vsLastWeek})',
                              _deltaHours(r.totalRecordedHours,
                                  p.totalRecordedHours),
                              text),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Daily breakdown chart
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.dailyBreakdown,
                        style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    SizedBox(
                        height: 180,
                        child: _ordersChart(r, scheme)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Daily rows
              for (final d in r.days) _dayRow(context, d, l10n, loc),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: l10n.shareSummary,
                      primary: false,
                      icon: Icons.share_rounded,
                      onPressed: () {
                        final db =
                            ref.read(databaseServiceProvider);
                        SharePlus.instance.share(ShareParams(
                            text: db.reportShareText(r,
                                dayLabel: (k) => DateFormat.EEEE(loc).format(
                                    WeekCalendar.parseDateKey(k)))));
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GlassButton(
                      label: l10n.exportCsv,
                      primary: false,
                      icon: Icons.download_rounded,
                      onPressed: () async {
                        final db =
                            ref.read(databaseServiceProvider);
                        final csv = db.exportCsv();
                        await SharePlus.instance.share(ShareParams(
                            text: csv, subject: 'deliveryflow.csv'));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(
                                  content:
                                      Text(l10n.csvExported)));
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  String _delta(int cur, int prev) {
    final d = cur - prev;
    final sign = d >= 0 ? '+' : '';
    return '$sign$d';
  }

  Widget _kmStat(BuildContext context, String label, String value,
      AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text('$value ${l10n.kmUnit}',
            style:
                text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            style: text.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6))),
      ],
    );
  }

  /// Weekly salary = (attended days × daily fixed) + (orders × order price).
  Widget _salaryCard(BuildContext context, WidgetRef ref,
      AppLocalizations l10n, WeeklyReport r, TextTheme text, ColorScheme scheme) {
    final settings = ref.watch(settingsProvider);
    final orderPrice = settings.orderPrice;
    final dailyFixed = settings.dailyFixedPay;

    if (orderPrice == null || dailyFixed == null) {
      return GlassCard(
        child: Row(
          children: [
            Icon(Icons.payments_outlined,
                color: scheme.primary.withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l10n.setSalaryHint,
                  style: text.bodyMedium?.copyWith(
                      color:
                          scheme.onSurface.withValues(alpha: 0.7))),
            ),
          ],
        ),
      );
    }

    final daysPay = r.recordedDaysCount * dailyFixed;
    final ordersPay = r.totalOrders * orderPrice;
    final total = daysPay + ordersPay;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_rounded,
                  size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(l10n.weeklySalary,
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                '${_fmtMoney(total)} ${l10n.egpUnit}',
                style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _salaryRow(
              text,
              scheme,
              '${l10n.attendanceDays} (${r.recordedDaysCount} × ${_fmtMoney(dailyFixed)})',
              '${_fmtMoney(daysPay)} ${l10n.egpUnit}'),
          const SizedBox(height: 6),
          _salaryRow(
              text,
              scheme,
              '${l10n.totalOrders} (${r.totalOrders} × ${_fmtMoney(orderPrice)})',
              '${_fmtMoney(ordersPay)} ${l10n.egpUnit}'),
        ],
      ),
    );
  }

  Widget _salaryRow(
      TextTheme text, ColorScheme scheme, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label,
              style: text.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.75))),
        ),
        Text(value,
            style:
                text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }

  /// Money formatting: no trailing .0, thousands separator for readability.
  String _fmtMoney(double v) {
    final s = v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
    final parts = s.split('.');
    final intPart = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
  }

  String _deltaHours(double cur, double prev) {
    final d = cur - prev;
    final sign = d >= 0 ? '+' : '';
    return '$sign${WeekCalendar.formatHours(d.abs())}';
  }

  Widget _kv(String k, String v, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: text.bodyMedium),
          Text(v,
              style: text.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _ordersChart(WeeklyReport r, ColorScheme scheme) {
    const dayLetters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return BarChart(
      BarChartData(
        barGroups: [
          for (var i = 0; i < r.days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: (r.days[i].orders ?? 0).toDouble(),
                  width: 16,
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(colors: [
                    scheme.primary,
                    scheme.primary.withValues(alpha: 0.55),
                  ]),
                ),
              ],
            ),
        ],
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(dayLetters[v.toInt() % 7],
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface
                            .withValues(alpha: 0.6))),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayRow(BuildContext context, DayBreakdown d,
      AppLocalizations l10n, String loc) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final date = WeekCalendar.parseDateKey(d.dateKey);
    final name = DateFormat.EEEE(loc).format(date);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700)),
                  Text(
                    d.orders == null
                        ? l10n.unrecorded
                        : l10n.ordersCount(d.orders!),
                    style: text.bodySmall?.copyWith(
                        color: d.orders == null
                            ? scheme.tertiary
                            : null),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(WeekCalendar.formatHours(d.workMinutes / 60.0),
                    style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700)),
                Text(
                    '${l10n.scheduledVsActual}: ${WeekCalendar.formatHours(d.plannedHours)}',
                    style: text.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
