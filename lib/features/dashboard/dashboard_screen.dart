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

/// Home dashboard: greeting, today + week stats, charts, quick actions,
/// and the Saturday "plan next week" prompt.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _saturdayPromptShown = false;
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
              padding: GlassTokens.screenPadding,
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
                  // Hero stat cards
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: l10n.weekOrders,
                          value: '${report.totalOrders}',
                          icon: Icons.shopping_bag_rounded,
                          accent: const Color(0xFF38E1FF),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          label: l10n.weekHours,
                          value: WeekCalendar.formatHours(
                              report.totalRecordedHours),
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
                          label: l10n.todayOrders,
                          value: todayOrder == null
                              ? l10n.unrecorded
                              : '${todayOrder.completedOrders}',
                          icon: Icons.today_rounded,
                          accent: const Color(0xFF4D7CFE),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          label: l10n.todayHours,
                          value: WeekCalendar.formatHours(
                              todayMinutes / 60.0),
                          icon: Icons.timer_rounded,
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
                          value: report.averageOrdersPerWorkingDay == null
                              ? '–'
                              : report.averageOrdersPerWorkingDay!
                                  .toStringAsFixed(1),
                          icon: Icons.trending_up_rounded,
                          accent: const Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          label: l10n.recordedDays,
                          value: '${report.recordedDaysCount}/7',
                          icon: Icons.check_circle_rounded,
                          accent: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 16),
                  // Charts
                  _chartCard(
                    context,
                    l10n.ordersChartTitle,
                    _ordersBarChart(report, scheme),
                  ),
                  const SizedBox(height: 12),
                  _chartCard(
                    context,
                    l10n.hoursChartTitle,
                    _hoursBarChart(report, scheme),
                  ),
                  const SizedBox(height: 16),
                ],
                // Quick actions
                Text(l10n.quickRecordOrders,
                    style: text.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _quickAction(context, Icons.add_shopping_cart_rounded,
                        l10n.quickRecordOrders,
                        () => context.push('/orders?date=$todayKey')),
                    _quickAction(context, Icons.timer_rounded,
                        l10n.quickRecordHours,
                        () => context.push('/hours?date=$todayKey')),
                    _quickAction(context, Icons.calendar_month_rounded,
                        l10n.quickViewSchedule, () => context.go('/schedule')),
                    _quickAction(context, Icons.bar_chart_rounded,
                        l10n.quickViewReport, () => context.go('/reports')),
                    _quickAction(context, Icons.history_rounded,
                        l10n.quickBrowseHistory, () => context.go('/history')),
                  ],
                ),
                const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              height: 10,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard(BuildContext context, String title, Widget chart) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(height: 180, child: chart),
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
    return _barChart(groups, scheme);
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
    return _barChart(groups, scheme);
  }

  Widget _barChart(List<BarChartGroupData> groups, ColorScheme scheme) {
    const dayLetters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return BarChart(
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
