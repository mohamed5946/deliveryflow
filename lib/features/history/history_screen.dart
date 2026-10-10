import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';

/// Chronological list of past work weeks with drill-down into the
/// weekly report of any week.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale =
        ref.watch(settingsProvider.select((s) => s.languageCode));
    final loc = locale == 'ar' ? 'ar' : 'en';
    final weeksAsync = ref.watch(historyWeeksProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: weeksAsync.when(
        loading: () => const GlassLoading(),
        error: (e, _) => Center(child: Text('$e')),
        data: (weeks) {
          if (weeks.isEmpty) {
            return EmptyState(
              icon: Icons.history_rounded,
              title: l10n.emptyStateTitle,
              body: l10n.emptyStateBody,
              actionLabel: l10n.getStarted,
              onAction: () {},
            );
          }
          return ListView.builder(
            padding: GlassTokens.screenPadding,
            itemCount: weeks.length,
            itemBuilder: (ctx, i) {
              final startKey = weeks[i];
              final start = WeekCalendar.parseDateKey(startKey);
              final reportAsync = ref
                  .watch(weeklyReportProvider(start));
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: reportAsync.when(
                  loading: () => const GlassCard(
                      child: SizedBox(
                          height: 60,
                          child: Center(
                              child:
                                  CircularProgressIndicator()))),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (r) {
                    final end = WeekCalendar.parseDateKey(
                        r.weekEndKey);
                    final range =
                        '${DateFormat.yMMMd(loc).format(start)} – ${DateFormat.yMMMd(loc).format(end)}';
                    return GlassCard(
                      onTap: () => _openWeek(context, start),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(range,
                                    style: text.titleSmall?.copyWith(
                                        fontWeight:
                                            FontWeight.w700)),
                              ),
                              Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 16,
                            runSpacing: 4,
                            children: [
                              _mini(l10n.totalOrders,
                                  '${r.totalOrders}'),
                              _mini(
                                  l10n.totalRecordedHours,
                                  WeekCalendar.formatHours(
                                      r.totalRecordedHours)),
                              _mini(
                                  l10n.completeDays(
                                      r.recordedDaysCount),
                                  ''),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _mini(String label, String value) {
    return Text('$label: $value',
        style: const TextStyle(fontSize: 13));
  }

  void _openWeek(BuildContext context, DateTime weekStart) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _WeekDetailSheet(weekStart: weekStart),
      ),
    );
  }
}

/// Drill-down: daily breakdown of one historical week.
class _WeekDetailSheet extends ConsumerWidget {
  final DateTime weekStart;
  const _WeekDetailSheet({required this.weekStart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale =
        ref.watch(settingsProvider.select((s) => s.languageCode));
    final loc = locale == 'ar' ? 'ar' : 'en';
    final reportAsync = ref.watch(weeklyReportProvider(weekStart));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.openWeek)),
      body: reportAsync.when(
        loading: () => const GlassLoading(),
        error: (e, _) => Center(child: Text('$e')),
        data: (r) {
          final start = WeekCalendar.parseDateKey(r.weekStartKey);
          final end = WeekCalendar.parseDateKey(r.weekEndKey);
          return ListView(
            padding: GlassTokens.screenPadding,
            children: [
              Text(
                '${DateFormat.yMMMd(loc).format(start)} – ${DateFormat.yMMMd(loc).format(end)}',
                style: text.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
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
              Text(l10n.dailyBreakdown,
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final d in r.days)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat.EEEE(loc).format(
                              WeekCalendar.parseDateKey(
                                  d.dateKey)),
                          style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          d.orders == null
                              ? l10n.unrecorded
                              : '${l10n.ordersCount(d.orders!)} • ${WeekCalendar.formatHours(d.workMinutes / 60.0)}',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
