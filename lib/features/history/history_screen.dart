import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../core/tracking/delivery_tracking_service.dart';
import '../../theme/design_system.dart';
import '../../theme/page_transitions.dart';
import '../../theme/pressable.dart';
import 'day_orders_screen.dart';

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
              onAction: () => context.push(
                '/orders?date=${WeekCalendar.dateKey(DateTime.now())}',
              ),
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
                                  DeliveryLoadingBar(width: 160)))),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (r) {
                    final end = WeekCalendar.parseDateKey(
                        r.weekEndKey);
                    final range =
                        '${DateFormat.yMMMd(loc).format(start)} – ${DateFormat.yMMMd(loc).format(end)}';
                    return GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient:
                                  LiquidPalette.brandGradientLg,
                              borderRadius:
                                  BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: LiquidPalette.primaryBlue
                                      .withValues(alpha: 0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                                Icons.history_rounded,
                                color: Colors.white,
                                size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Pressable(
                              onTap: () =>
                                  _openWeek(context, start),
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
                                            FontWeight.w800)),
                              ),
                              const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                  color: LiquidPalette.primaryBlue),
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
                                  l10n.weekKmLabel,
                                  '${WeekCalendar.formatKm(r.totalKm)} ${l10n.kmUnit}'),
                              _mini(
                                  l10n.completeDays(
                                      r.recordedDaysCount),
                                  ''),
                            ],
                          ),
                        ],
                      ),
                      ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: Theme.of(context)
                                  .colorScheme
                                  .error,
                            ),
                            tooltip: l10n.delete,
                            onPressed: () =>
                                _confirmDeleteWeek(
                                    context, ref, startKey),
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
      SmoothPageRoute(
        builder: (_) => _WeekDetailSheet(weekStart: weekStart),
      ),
    );
  }

  Future<void> _confirmDeleteWeek(
      BuildContext context, WidgetRef ref, String startKey) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteWeekTitle),
        content: Text(l10n.deleteWeekBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor:
                  Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      // If the week being deleted contains the currently tracked order,
      // stop the background service first — otherwise it keeps recording
      // + notifying for deleted data (orphaned tracking).
      final svc = ref.read(deliveryTrackingServiceProvider);
      final trackedId = svc.trackingOrderId;
      if (svc.isTracking && trackedId != null) {
        final db = ref.read(databaseServiceProvider);
        final start = WeekCalendar.parseDateKey(startKey);
        var trackedInWeek = false;
        for (var i = 0; i < 7 && !trackedInWeek; i++) {
          final key =
              WeekCalendar.dateKey(WeekCalendar.addDays(start, i));
          final rec = db.orderRecord(key);
          if (rec != null &&
              rec.entries.any((e) => e.id == trackedId)) {
            trackedInWeek = true;
          }
        }
        if (trackedInWeek) await svc.cancelTracking();
      }
      await ref.read(databaseServiceProvider).deleteWeek(startKey);
      bumpDataVersion(ref);
    }
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

    return GlassScaffold(
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
                      accent: LiquidPalette.skyBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: l10n.totalRecordedHours,
                      value: WeekCalendar.formatHours(
                          r.totalRecordedHours),
                      icon: Icons.schedule_rounded,
                      accent: LiquidPalette.primaryBlue,
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
                  child: Pressable(
                    // Only days with orders are tappable.
                    onTap: (d.orders ?? 0) > 0
                        ? () => Navigator.of(context).push(
                              SmoothPageRoute(
                                builder: (_) => DayOrdersScreen(
                                  dateKey: d.dateKey,
                                ),
                              ),
                            )
                        : null,
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
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              d.orders == null
                                  ? l10n.unrecorded
                                  : '${l10n.ordersCount(d.orders!)} • ${WeekCalendar.formatHours(d.workMinutes / 60.0)}',
                              style: text.bodyMedium,
                            ),
                            if ((d.orders ?? 0) > 0) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
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
