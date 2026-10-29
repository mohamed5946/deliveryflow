import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/cloud/adjustment_logic.dart';
import '../../core/cloud/cloud_providers.dart';
import '../../core/cloud/cloud_types.dart';
import '../../core/database/models.dart';
import '../../core/date_time/day_rollover.dart';
import '../../core/date_time/week_calendar.dart';
import '../../core/logging/app_log_service.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';
import '../../theme/staggered_entrance.dart';
import '../../theme/top_snack_bar.dart';
import '../../theme/page_transitions.dart';
import 'past_weeks_report.dart';
import 'reports_pdf_builder.dart';
import 'weekly_heatmap_screen.dart';

/// Weekly report: totals, averages (recorded days only), best day,
/// previous-week comparison, charts, share-as-text and CSV export.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  DateTime _anchor = DateTime.now();
  late final DayRolloverWatcher _rollover;

  @override
  void initState() {
    super.initState();
    _rollover = DayRolloverWatcher(onDayChanged: _handleDayChanged);
    _rollover.start();
  }

  @override
  void dispose() {
    _rollover.dispose();
    super.dispose();
  }

  /// v26 midnight rollover: when the displayed week was the current one,
  /// shift the anchor by the same delta so the new week shows in place;
  /// the "اليوم" summary card also re-reads the fresh date on rebuild.
  void _handleDayChanged(DateTime previous, DateTime current) {
    if (!mounted) return;
    setState(() {
      if (WeekCalendar.isSameWeek(_anchor, previous)) {
        _anchor = WeekCalendar.addDays(
            _anchor, WeekCalendar.daysBetween(previous, current));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(settingsProvider.select((s) => s.languageCode));
    final loc = locale == 'ar' ? 'ar' : 'en';

    final reportAsync = ref.watch(weeklyReportProvider(_anchor));
    final prevAsync =
        ref.watch(weeklyReportProvider(WeekCalendar.addDays(_anchor, -7)));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reportTitle),
        actions: [
          IconButton(
            tooltip: l10n.weeklyHeatmap,
            icon: const Icon(Icons.local_fire_department_outlined),
            onPressed: () => Navigator.of(context).push(
              SmoothPageRoute(
                builder: (_) => const WeeklyHeatmapScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.previousWeek,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () =>
                setState(() => _anchor = WeekCalendar.addDays(_anchor, -7)),
          ),
          IconButton(
            tooltip: l10n.nextWeek,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () =>
                setState(() => _anchor = WeekCalendar.addDays(_anchor, 7)),
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
          // v27.31: section cards stagger in on every entry, tab
          // switches included (TabReplayScope bumps the generation).
          return TabReplayScope(
            tabIndex: 2,
            child: StaggeredScope(
              child: ListView(
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
                          color: scheme.tertiary, fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 12),
                  // Day summary (mockup's "ملخص اليوم") — current week only.
                  if (WeekCalendar.isSameWeek(_anchor, DateTime.now()))
                    StaggeredItem(
                        index: 0,
                        child: _daySummaryCard(context, ref, l10n, text)),
                  if (WeekCalendar.isSameWeek(_anchor, DateTime.now()))
                    const SizedBox(height: 12),
                  // Totals
                  StaggeredItem(
                    index: 1,
                    child: Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: l10n.totalOrders,
                            value: '${r.totalOrders}',
                            icon: Icons.shopping_bag_rounded,
                            accent: LiquidPalette.skyBlue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatTile(
                            label: l10n.totalRecordedHours,
                            value:
                                WeekCalendar.formatHours(r.totalRecordedHours),
                            icon: Icons.schedule_rounded,
                            accent: LiquidPalette.primaryBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  StaggeredItem(
                    index: 2,
                    child: Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: l10n.totalPlannedHoursLabel,
                            value:
                                WeekCalendar.formatHours(r.totalPlannedHours),
                            icon: Icons.event_note_rounded,
                            accent: LiquidPalette.primaryBlue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatTile(
                            label: l10n.ordersPerHour,
                            value: r.ordersPerWorkingHour == null
                                ? '–'
                                : r.ordersPerWorkingHour!.toStringAsFixed(1),
                            icon: Icons.speed_rounded,
                            accent: LiquidPalette.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  StaggeredItem(
                    index: 3,
                    child: Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: l10n.avgOrdersWorkingDay,
                            value: r.averageOrdersPerWorkingDay == null
                                ? '–'
                                : r.averageOrdersPerWorkingDay!
                                    .toStringAsFixed(1),
                            icon: Icons.trending_up_rounded,
                            accent: LiquidPalette.warning,
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
                            accent: LiquidPalette.accentViolet,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Distance totals
                  StaggeredItem(
                    index: 4,
                    child: GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.route_rounded,
                                  size: 20, color: LiquidPalette.skyBlue),
                              const SizedBox(width: 8),
                              Text(l10n.weekKmLabel,
                                  style: text.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800)),
                              const Spacer(),
                              Text(
                                '${WeekCalendar.formatKm(r.totalKm)} ${l10n.kmUnit}',
                                style: text.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: LiquidPalette.skyBlue),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _kmStat(context, l10n.kmOutLabel,
                                    WeekCalendar.formatKm(r.totalKmOut), l10n),
                              ),
                              Expanded(
                                child: _kmStat(context, l10n.kmBackLabel,
                                    WeekCalendar.formatKm(r.totalKmBack), l10n),
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
                  ),
                  const SizedBox(height: 12),
                  // Weekly salary
                  StaggeredItem(
                      index: 5,
                      child: _salaryCard(context, ref, l10n, r, text, scheme)),
                  const SizedBox(height: 12),
                  // v27.33: manager adjustments for this week (driver
                  // visibility — nothing silent: every bonus and every
                  // deduction appears here with its reason, date, and
                  // manager stamp, plus the adjusted week total).
                  _ManagerAdjustmentsCard(report: r),
                  // v27.5: this week's distance-bonus on/off (per-week
                  // override of the global default).
                  StaggeredItem(
                      index: 6,
                      child: _distanceBonusWeekCard(
                          context, ref, l10n, r, text, scheme)),
                  const SizedBox(height: 12),
                  // Best day + comparison
                  StaggeredItem(
                    index: 7,
                    child: GlassCard(
                      child: Column(
                        children: [
                          _kv(
                              l10n.bestDay,
                              r.bestDayKey == null
                                  ? '–'
                                  : DateFormat.EEEE(loc).format(
                                      WeekCalendar.parseDateKey(r.bestDayKey!)),
                              text),
                          const Divider(height: 16),
                          prevAsync.when(
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                            data: (p) => Column(
                              children: [
                                _kv('${l10n.totalOrders} (${l10n.vsLastWeek})',
                                    _delta(r.totalOrders, p.totalOrders), text),
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
                  ),
                  const SizedBox(height: 12),
                  // Daily breakdown chart
                  StaggeredItem(
                    index: 8,
                    child: GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.dailyBreakdown,
                              style: text.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          RepaintBoundary(
                            child: SizedBox(
                                height: 180, child: _ordersChart(r, scheme)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Daily rows
                  for (var i = 0; i < r.days.length; i++)
                    StaggeredItem(
                        index: 9 + i,
                        child: _dayRow(context, r.days[i], l10n, loc)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: GlassButton(
                          label: l10n.shareSummary,
                          primary: false,
                          icon: Icons.share_rounded,
                          onPressed: () {
                            final db = ref.read(databaseServiceProvider);
                            SharePlus.instance.share(ShareParams(
                                text: db.reportShareText(r,
                                    dayLabel: (k) => DateFormat.EEEE(loc)
                                        .format(
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
                            final db = ref.read(databaseServiceProvider);
                            final csv = db.exportCsv();
                            await SharePlus.instance.share(ShareParams(
                                text: csv, subject: 'deliveryflow.csv'));
                            if (context.mounted) {
                              showTopSnackBar(context, l10n.csvExported);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // v27.4: one-tap PDF of the recorded weeks (organized,
                  // per-day tables + week/grand totals), shared as a file.
                  // v27.5: the button first asks the scope — all weeks,
                  // or one picked week exported on its own.
                  GlassButton(
                    label: l10n.exportPdfAllWeeks,
                    primary: false,
                    icon: Icons.picture_as_pdf_rounded,
                    onPressed: _choosePdfScope,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// v27.5: the export button first asks the scope — every recorded
  /// week (the v27.4 behavior), or one picked week exported on its
  /// own. Weeks are listed newest first by their date range.
  Future<void> _choosePdfScope() async {
    final l10n = AppLocalizations.of(context);
    final db = ref.read(databaseServiceProvider);
    final settings = ref.read(settingsProvider);
    final weeks = PastWeeksReportBuilder(db).availableWeeks(
      locale: settings.languageCode == 'ar' ? 'ar' : 'en',
    );
    if (weeks.isEmpty) {
      if (mounted) showTopSnackBar(context, l10n.pdfNoWeeks);
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
              ),
              child: StaggeredScope(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text(l10n.pdfExportScopeTitle,
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    StaggeredItem(
                      index: 0,
                      child: _pdfScopeRow(
                        sheetContext,
                        icon: Icons.picture_as_pdf_rounded,
                        title: l10n.pdfAllWeeksOption,
                        onTap: () => Navigator.of(sheetContext).pop('all'),
                      ),
                    ),
                    for (var i = 0; i < weeks.length; i++) ...[
                      const Divider(height: 8),
                      StaggeredItem(
                        index: 1 + i,
                        child: _pdfScopeRow(
                          sheetContext,
                          icon: Icons.date_range_rounded,
                          title: weeks[i].rangeLabel,
                          onTap: () => Navigator.of(sheetContext)
                              .pop(weeks[i].weekStartKey),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    await _exportPdf(onlyWeekStartKey: choice == 'all' ? null : choice);
  }

  Widget _pdfScopeRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: scheme.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style:
                      text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  /// v27.4: builds the past-weeks PDF and hands it to the share
  /// sheet. v27.5: [onlyWeekStartKey] scopes the export to that one
  /// week (null = all weeks). Per the standing logs rule the outcome
  /// — scope included — is recorded in the diagnostics log (reports
  /// category); a failure shows the v25-style dialog with the
  /// selectable technical reason.
  Future<void> _exportPdf({String? onlyWeekStartKey}) async {
    final l10n = AppLocalizations.of(context);
    final db = ref.read(databaseServiceProvider);
    final settings = ref.read(settingsProvider);
    final log = ref.read(appLogServiceProvider);
    final scope = onlyWeekStartKey ?? 'all';
    try {
      final data = PastWeeksReportBuilder(db).build(
        locale: settings.languageCode == 'ar' ? 'ar' : 'en',
        orderPrice: settings.orderPrice ?? 0,
        dailyFixedPay: settings.dailyFixedPay ?? 0,
        onlyWeekStartKey: onlyWeekStartKey,
      );
      if (data.weeks.isEmpty) {
        if (mounted) showTopSnackBar(context, l10n.pdfNoWeeks);
        return;
      }
      final bytes = await ReportsPdfBuilder()
          .build(data, l10n, singleWeek: onlyWeekStartKey != null);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/deliveryflow_weeks_report.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: l10n.pdfReportTitle,
      ));
      log.info(
        AppLogCategory.reports,
        'PDF weeks report generated: scope=$scope, '
        '${data.weeks.length} week(s), ${bytes.length} bytes',
      );
    } catch (e) {
      log.error(
        AppLogCategory.reports,
        'PDF weeks report generation FAILED (scope=$scope)',
        error: e,
      );
      if (!mounted) return;
      await _showPdfFailed(e);
    }
  }

  /// v27.4: PDF failure dialog — explanation plus the raw technical
  /// reason in selectable text (the v25 failure-dialog pattern).
  Future<void> _showPdfFailed(Object error) async {
    final l10n = AppLocalizations.of(context);
    final reason = formatLogError(error);
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final text = Theme.of(ctx).textTheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: scheme.error, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.pdfFailedTitle)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.technicalReason,
                style: text.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  reason,
                  style: text.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.ok),
            ),
          ],
        );
      },
    );
  }

  String _delta(int cur, int prev) {
    final d = cur - prev;
    final sign = d >= 0 ? '+' : '';
    return '$sign$d';
  }

  /// "ملخص اليوم" — mirrors the mockup: progress ring, hours + km
  /// cards, per-status breakdown, full-report CTA.
  Widget _daySummaryCard(BuildContext context, WidgetRef ref,
      AppLocalizations l10n, TextTheme text) {
    final db = ref.watch(databaseServiceProvider);
    final now = DateTime.now();
    final todayKey = WeekCalendar.dateKey(now);
    final rec = db.orderRecord(todayKey);
    // v27.1: tallies include the undetailed remainder, so a day whose
    // orders were bulk-logged (no counted entries) no longer shows 0/0.
    final tallies = daySummaryTallies(rec);
    final completed = tallies.completed;
    final inProgress = tallies.inProgress;
    final pending = tallies.pending;
    final total = tallies.total;
    // v26: effective minutes — auto-credited planned hours included.
    final minutes = db.effectiveMinutesForDate(todayKey);
    final km = rec?.totalKm ?? 0;
    final loc =
        ref.watch(settingsProvider.select((s) => s.languageCode)) == 'ar'
            ? 'ar'
            : 'en';

    Widget breakdownRow(String label, int count, Color color, IconData icon) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
                child: Text(label,
                    style: text.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600))),
            Text('$count',
                style: text.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      );
    }

    return GlassCard(
      borderRadius: GlassTokens.radiusL,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.daySummary,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(DateFormat.yMMMMEEEEd(loc).format(now),
              style: text.bodySmall?.copyWith(
                  color: text.bodySmall?.color?.withValues(alpha: 0.6))),
          const SizedBox(height: 14),
          Center(
            child: ProgressRing(
              progress: total == 0 ? 0 : completed / total,
              size: 128,
              centerTop: '$completed / $total',
              centerBottom: l10n.completedOrdersLabel,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _miniInfoCard(
                    context,
                    l10n.weekHours,
                    WeekCalendar.formatHoursMinutes(minutes),
                    Icons.schedule_rounded,
                    LiquidPalette.primaryBlue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniInfoCard(
                    context,
                    l10n.totalDistances,
                    '${WeekCalendar.formatKm(km)} ${l10n.kmUnit}',
                    Icons.route_rounded,
                    LiquidPalette.skyBlue),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l10n.ordersBreakdown,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          breakdownRow(l10n.statusCompleted, completed, LiquidPalette.success,
              Icons.check_circle_rounded),
          breakdownRow(l10n.statusInProgress, inProgress,
              LiquidPalette.primaryBlue, Icons.delivery_dining_rounded),
          breakdownRow(l10n.statusPending, pending, Colors.grey,
              Icons.hourglass_empty_rounded),
          const SizedBox(height: 10),
          GlassButton(
            label: l10n.viewFullReport,
            icon: Icons.bar_chart_rounded,
            onPressed: () => context.push('/orders?date=$todayKey'),
          ),
        ],
      ),
    );
  }

  Widget _miniInfoCard(BuildContext context, String label, String value,
      IconData icon, Color accent) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlassTokens.radiusM),
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.6),
        border: Border.all(
          color: accent.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style:
                        text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(label,
                    style: text.bodySmall?.copyWith(
                        color: text.bodySmall?.color?.withValues(alpha: 0.6),
                        fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kmStat(
      BuildContext context, String label, String value, AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text('$value ${l10n.kmUnit}',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            style: text.bodySmall
                ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6))),
      ],
    );
  }

  /// Weekly salary = (attended days × daily fixed) + (orders × order
  /// price) + distance bonuses + manual bonuses + flat per-order
  /// bonuses (v27.5: the shared [WeeklyReport.salaryTotal]; v27.6
  /// added the flat bonus to it).
  Widget _salaryCard(BuildContext context, WidgetRef ref, AppLocalizations l10n,
      WeeklyReport r, TextTheme text, ColorScheme scheme) {
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
                      color: scheme.onSurface.withValues(alpha: 0.7))),
            ),
          ],
        ),
      );
    }

    // v27: daily fixed pay counts only days with >= 1 counted order.
    // v27.5: the total is the ONE shared salary formula (orders +
    // fixed + distance bonuses + manual bonuses; v27.6: + flat
    // per-order bonuses).
    final daysPay = r.paidDaysCount * dailyFixed;
    final ordersPay = r.totalOrders * orderPrice;
    final total =
        r.salaryTotal(orderPrice: orderPrice, dailyFixedPay: dailyFixed);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(l10n.weeklySalary,
                  style:
                      text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                '${_fmtMoney(total)} ${l10n.egpUnit}',
                style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _salaryRow(
              text,
              scheme,
              '${l10n.attendanceDays} (${r.paidDaysCount} × ${_fmtMoney(dailyFixed)})',
              '${_fmtMoney(daysPay)} ${l10n.egpUnit}'),
          const SizedBox(height: 6),
          _salaryRow(
              text,
              scheme,
              '${l10n.totalOrders} (${r.totalOrders} × ${_fmtMoney(orderPrice)})',
              '${_fmtMoney(ordersPay)} ${l10n.egpUnit}'),
          const SizedBox(height: 6),
          _salaryRow(text, scheme, l10n.distanceBonusLabel,
              '${_fmtMoney(r.totalDistanceBonus)} ${l10n.egpUnit}'),
          const SizedBox(height: 6),
          _salaryRow(text, scheme, l10n.manualBonusLabel,
              '${_fmtMoney(r.totalManualBonus)} ${l10n.egpUnit}'),
          // v27.6: flat per-order bonus line, only when it pays.
          if (r.totalFlatBonus > 0) ...[
            const SizedBox(height: 6),
            _salaryRow(text, scheme, l10n.flatOrdersBonusLabel,
                '${_fmtMoney(r.totalFlatBonus)} ${l10n.egpUnit}'),
          ],
        ],
      ),
    );
  }

  /// v27.5: per-week distance-bonus switch — overrides the global
  /// default for the DISPLAYED week only; every other week keeps
  /// resolving its own override ?? global, so toggling one week never
  /// rewrites another week's earnings. The switch reflects the
  /// report's own resolved flag, so what it shows is what was paid.
  Widget _distanceBonusWeekCard(
      BuildContext context,
      WidgetRef ref,
      AppLocalizations l10n,
      WeeklyReport r,
      TextTheme text,
      ColorScheme scheme) {
    // v27.16: the switch is only live for weeks inside an active
    // distance period. For a week outside every period it is
    // disabled (not a dead button — flipping it could never change
    // any salary, because a per-week override must never resurrect
    // a bonus for a week the bonus was never active in). To turn
    // the bonus on for a week, enable it in Profile first.
    final hasPeriod =
        ref.watch(settingsProvider).hasDistancePeriodInWeek(r.weekStartKey);
    return GlassCard(
      child: Row(
        children: [
          Icon(Icons.route_rounded, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l10n.distanceBonusWeekLabel,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Switch(
            value: r.distanceBonusEnabled,
            onChanged: hasPeriod
                ? (v) => _setWeekDistanceBonus(r.weekStartKey, v)
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _setWeekDistanceBonus(String weekStartKey, bool value) async {
    final log = ref.read(appLogServiceProvider);
    await ref.read(settingsProvider.notifier).update((s) {
      final overrides = Map<String, bool>.from(s.distanceBonusWeekOverrides);
      // v27.16: within a period-covered week, the override is a pure
      // exception — ON means "back to the period default" (so the
      // override is cleared, never frozen), OFF stores false for
      // that week only. The override can never extend the bonus to
      // a day outside a period: the per-day resolver ANDs it with
      // period coverage.
      if (value) {
        overrides.remove(weekStartKey);
      } else {
        overrides[weekStartKey] = false;
      }
      return s..distanceBonusWeekOverrides = overrides;
    });
    log.info(
      AppLogCategory.settings,
      'Distance bonus for week $weekStartKey -> ${value ? 'ON' : 'OFF'} '
      '(per-week override, within its active period only)',
    );
    bumpDataVersion(ref);
  }

  Widget _salaryRow(
      TextTheme text, ColorScheme scheme, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label,
              style: text.bodyMedium
                  ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.75))),
        ),
        Text(value,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
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
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _ordersChart(WeeklyReport r, ColorScheme scheme) {
    // Sunday..Saturday, Arabic initials (RTL).
    const dayLetters = ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س'];
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
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: LiquidPalette.brandGradient,
                  ),
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
                        color: scheme.onSurface.withValues(alpha: 0.6))),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// v27: derived work/off status chip for a report day row. The
  /// status is computed live from the day's counted orders, so it
  /// flips by itself when orders are added or deleted.
  Widget _dayStatusChip(
      BuildContext context, DayBreakdown d, AppLocalizations l10n) {
    final status = dayStatusFor(
      orders: d.orders,
      isWorkingDay: d.isWorkingDay,
      date: WeekCalendar.parseDateKey(d.dateKey),
      today: DateTime.now(),
    );
    if (status == DayStatus.none) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final isWork = status == DayStatus.workDay;
    final color = isWork ? scheme.primary : scheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isWork ? Icons.work_rounded : Icons.beach_access_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isWork ? l10n.workingDay : l10n.dayOff,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _dayRow(
      BuildContext context, DayBreakdown d, AppLocalizations l10n, String loc) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final date = WeekCalendar.parseDateKey(d.dateKey);
    final name = DateFormat.EEEE(loc).format(date);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      _dayStatusChip(context, d, l10n),
                    ],
                  ),
                  Text(
                    d.orders == null
                        ? l10n.unrecorded
                        : l10n.ordersCount(d.orders!),
                    style: text.bodySmall?.copyWith(
                        color: d.orders == null ? scheme.tertiary : null),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(WeekCalendar.formatHours(d.workMinutes / 60.0),
                    style:
                        text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
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

/// v27.33 — Driver visibility for manager adjustments (weekly view).
///
/// Nothing silent: when the signed-in driver has manager adjustments
/// for this week, each one appears as its own labeled line — a bonus
/// line "+amount — بونس من المدير: {reason}" and a deduction line
/// "−amount — خصم من المدير: {reason}" — each with its date and
/// manager stamp, followed by the adjusted week total (base formula
/// + bonuses − deductions). Renders nothing when signed out or when
/// the week has no adjustments, so the base salary card is untouched.
class _ManagerAdjustmentsCard extends ConsumerWidget {
  const _ManagerAdjustmentsCard({required this.report});

  final WeeklyReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(cloudAccountProvider).account;
    if (account == null) return const SizedBox.shrink();
    final backend = ref.watch(cloudBackendProvider);
    final settings = ref.watch(settingsProvider);
    final orderPrice = settings.orderPrice;
    final dailyFixed = settings.dailyFixedPay;
    if (orderPrice == null || dailyFixed == null) {
      return const SizedBox.shrink();
    }
    final base = report.salaryTotal(
      orderPrice: orderPrice,
      dailyFixedPay: dailyFixed,
    );
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<CloudAdjustment>>(
      future: backend.listAdjustments(account.uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting ||
            snap.hasError) {
          return const SizedBox.shrink();
        }
        final week = adjustmentsForWeek(
          snap.data ?? const <CloudAdjustment>[],
          report.weekStartKey,
        );
        if (week.isEmpty) return const SizedBox.shrink();
        final adjusted = weeklyTotalWithAdjustments(base, week);
        return Column(
          children: [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.admin_panel_settings_rounded,
                          size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تعديلات المدير لهذا الأسبوع',
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final a in week) ...[
                    Row(
                      children: [
                        Icon(
                          a.isBonus
                              ? Icons.add_circle_rounded
                              : Icons.remove_circle_rounded,
                          size: 18,
                          color: a.isBonus
                              ? scheme.primary
                              : scheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${a.isBonus ? '+' : '−'}${a.amount.toStringAsFixed(0)} EGP — '
                                '${a.isBonus ? 'بونس من المدير' : 'خصم من المدير'}: ${a.reason}',
                                style: text.bodyMedium,
                              ),
                              Text(
                                '${DateFormat('d/M/yyyy').format(DateTime.fromMillisecondsSinceEpoch(a.createdAtMillis).toLocal())} · من المدير',
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'إجمالي الأسبوع بعد تعديلات المدير',
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${adjusted.toStringAsFixed(adjusted.truncateToDouble() == adjusted ? 0 : 2)} EGP',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}
