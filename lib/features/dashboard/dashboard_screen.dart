import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';

/// Home dashboard (simplified): greeting, today's hero card, compact weekly
/// strip, tabbed chart, and a quick-actions row.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

enum _ChartTab { orders, hours }

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _saturdayPromptShown = false;
  _ChartTab _chartTab = _ChartTab.orders;
  late final DateTime _today = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final reportAsync = ref.watch(weeklyReportProvider(_today));

    final now = DateTime.now();
    final todayKey = WeekCalendar.dateKey(_today);
    final db = ref.watch(databaseServiceProvider);
    final todayOrder = db.orderRecord(todayKey);
    final todayMinutes = db.recordedMinutesForDate(todayKey);

    final hour = _today.hour;
    final greeting = hour < 12
        ? l10n.greetingMorning
        : hour < 18
            ? l10n.greetingAfternoon
            : l10n.greetingEvening;
    final name =
        settings.displayName.isEmpty ? '' : '، ${settings.displayName}';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          bumpDataVersion(ref);
        },
        child: reportAsync.when(
          loading: () => const GlassLoading(),
          error: (e, _) => Center(child: Text('$e')),
          data: (report) {
            final hasAnyData = report.recordedDaysCount > 0 ||
                db.scheduleForWeek(_today) != null;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _saturdayPrompt(context, ref, l10n),
                  // Greeting
                  Text('$greeting$name',
                      style: text.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat.yMMMMEEEEd(
                            settings.languageCode == 'ar' ? 'ar' : 'en')
                        .format(now),
                    style: text.bodyMedium?.copyWith(
                        color: text.bodyMedium?.color
                            ?.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 16),
                  if (!hasAnyData)
                    EmptyState(
                      icon: Icons.delivery_dining_rounded,
                      title: l10n.emptyStateTitle,
                      body: l10n.emptyStateBody,
                      actionLabel: l10n.emptyStateAction,
                      onAction: () =>
                          context.push('/orders?date=$todayKey'),
                    )
                  else ...[
                    // Hero: today at a glance
                    _todayHeroCard(
                      context,
                      l10n,
                      todayOrder == null
                          ? l10n.unrecorded
                          : '${todayOrder.completedOrders}',
                      WeekCalendar.formatHours(todayMinutes / 60.0),
                      () => context.push('/orders?date=$todayKey'),
                    ),
                    const SizedBox(height: 12),
                    // Compact weekly strip
                    _weekStrip(context, l10n, report),
                    const SizedBox(height: 12),
                    // Goal progress
                    if (settings.weeklyOrderGoal != null)
                      _goalCard(
                        context,
                        l10n.weeklyOrderGoalLabel,
                        report.totalOrders.toDouble(),
                        settings.weeklyOrderGoal!.toDouble(),
                        l10n,
                      ),
                    if (settings.weeklyWorkHoursGoal != null) ...[
                      const SizedBox(height: 12),
                      _goalCard(
                        context,
                        l10n.weeklyHoursGoalLabel,
                        report.totalRecordedHours,
                        settings.weeklyWorkHoursGoal!,
                        l10n,
                      ),
                    ],
                    if (settings.weeklyOrderGoal != null ||
                        settings.weeklyWorkHoursGoal != null)
                      const SizedBox(height: 12),
                    // Tabbed chart
                    _chartCard(context, l10n, report, scheme),
                    const SizedBox(height: 16),
                    // Quick actions
                    _quickActionsRow(context, l10n, todayKey),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Big tappable hero card: today's orders + hours.
  Widget _todayHeroCard(BuildContext context, AppLocalizations l10n,
      String ordersValue, String hoursValue, VoidCallback onTap) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      onTap: onTap,
      borderRadius: GlassTokens.radiusL,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.todayOrders,
                    style: text.bodyMedium?.copyWith(
                        color: text.bodyMedium?.color
                            ?.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(ordersValue,
                    style: text.displayMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                        height: 1.0)),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 64,
            color: scheme.onSurface.withValues(alpha: 0.12),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.todayHours,
                    style: text.bodyMedium?.copyWith(
                        color: text.bodyMedium?.color
                            ?.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(hoursValue,
                    style: text.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800, height: 1.0)),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_rounded,
              color: scheme.primary.withValues(alpha: 0.7)),
        ],
      ),
    );
  }

  /// One glass card with four compact weekly stats.
  Widget _weekStrip(
      BuildContext context, AppLocalizations l10n, WeeklyReport report) {
    return GlassCard(
      child: Row(
        children: [
          _miniStat(
              context,
              '${report.totalOrders}',
              l10n.weekOrders,
              Icons.shopping_bag_rounded,
              const Color(0xFF38E1FF)),
          _miniStat(
              context,
              WeekCalendar.formatHours(report.totalRecordedHours),
              l10n.weekHours,
              Icons.schedule_rounded,
              const Color(0xFF8A6BFF)),
          _miniStat(
              context,
              report.averageOrdersPerWorkingDay == null
                  ? '–'
                  : report.averageOrdersPerWorkingDay!.toStringAsFixed(1),
              l10n.avgOrdersWorkingDay,
              Icons.trending_up_rounded,
              const Color(0xFFF59E0B)),
          _miniStat(
              context,
              '${report.recordedDaysCount}/7',
              l10n.recordedDays,
              Icons.check_circle_rounded,
              const Color(0xFF10B981)),
        ],
      ),
    );
  }

  Widget _miniStat(BuildContext context, String value, String label,
      IconData icon, Color accent) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(height: 6),
          Text(value,
              style:
                  text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: text.bodySmall?.copyWith(
                  color:
                      text.bodySmall?.color?.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  /// Chart card with an orders/hours segmented toggle.
  Widget _chartCard(BuildContext context, AppLocalizations l10n,
      WeeklyReport report, ColorScheme scheme) {
    final text = Theme.of(context).textTheme;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  _chartTab == _ChartTab.orders
                      ? l10n.ordersChartTitle
                      : l10n.hoursChartTitle,
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              _segmentedControl(context, l10n),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _chartTab == _ChartTab.orders
                  ? _ordersBarChart(report, scheme)
                  : _hoursBarChart(report, scheme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentedControl(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    Widget seg(_ChartTab tab, String label) {
      final selected = _chartTab == tab;
      return GestureDetector(
        onTap: () => setState(() => _chartTab = tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? scheme.primary
                : Colors.transparent,
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? Colors.white
                      : scheme.onSurface.withValues(alpha: 0.65))),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        color: scheme.onSurface.withValues(alpha: 0.08),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(_ChartTab.orders, l10n.ordersTitle),
          seg(_ChartTab.hours, l10n.hoursTitle),
        ],
      ),
    );
  }

  /// Horizontal row of quick-action buttons.
  Widget _quickActionsRow(
      BuildContext context, AppLocalizations l10n, String todayKey) {
    final actions = [
      (Icons.add_shopping_cart_rounded, l10n.quickRecordOrders,
          () => context.push('/orders?date=$todayKey')),
      (Icons.timer_rounded, l10n.quickRecordHours,
          () => context.push('/hours?date=$todayKey')),
      (Icons.calendar_month_rounded, l10n.quickViewSchedule,
          () => context.go('/schedule')),
      (Icons.bar_chart_rounded, l10n.quickViewReport,
          () => context.go('/reports')),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            _quickAction(
                context, actions[i].$1, actions[i].$2, actions[i].$3),
            if (i < actions.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _saturdayPrompt(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    if (_saturdayPromptShown) return const SizedBox.shrink();
    final now = DateTime.now();
    if (now.weekday != DateTime.saturday) return const SizedBox.shrink();
    final db = ref.read(databaseServiceProvider);
    final nextStart = WeekCalendar.nextWeekStart(now);
    if (db.hasScheduleForWeek(nextStart)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.saturdayPromptTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(l10n.saturdayPromptBody),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: l10n.createSchedule,
                    icon: Icons.calendar_month_rounded,
                    onPressed: () {
                      setState(() => _saturdayPromptShown = true);
                      context.go('/schedule');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () =>
                      setState(() => _saturdayPromptShown = true),
                  child: Text(l10n.remindMeLater),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _goalCard(BuildContext context, String label, double current,
      double goal, AppLocalizations l10n) {
    final progress = goal <= 0 ? 0.0 : (current / goal).clamp(0.0, 1.0);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                  '${current.toStringAsFixed(goal % 1 == 0 ? 0 : 1)} / ${goal.toStringAsFixed(goal % 1 == 0 ? 0 : 1)}',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ordersBarChart(WeeklyReport report, ColorScheme scheme) {
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < report.days.length; i++) {
      final d = report.days[i];
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: (d.orders ?? 0).toDouble(),
              width: 16,
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(colors: [
                scheme.primary,
                scheme.primary.withValues(alpha: 0.55),
              ]),
            ),
          ],
        ),
      );
    }
    return _barChart(groups, scheme, key: const ValueKey('orders'));
  }

  Widget _hoursBarChart(WeeklyReport report, ColorScheme scheme) {
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < report.days.length; i++) {
      final d = report.days[i];
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: d.workMinutes / 60.0,
              width: 16,
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(colors: [
                scheme.secondary,
                scheme.secondary.withValues(alpha: 0.55),
              ]),
            ),
          ],
        ),
      );
    }
    return _barChart(groups, scheme, key: const ValueKey('hours'));
  }

  Widget _barChart(
      List<BarChartGroupData> groups, ColorScheme scheme,
      {required Key key}) {
    const dayLetters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return BarChart(
      key: key,
      BarChartData(
        barGroups: groups,
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
                child: Text(
                  dayLetters[v.toInt() % 7],
                  style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
            ),
          ),
        ),
      ),
      swapAnimationDuration: const Duration(milliseconds: 500),
      swapAnimationCurve: Curves.easeOut,
    );
  }

  Widget _quickAction(BuildContext context, IconData icon, String label,
      VoidCallback onTap) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
