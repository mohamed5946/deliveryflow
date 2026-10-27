import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/database_service.dart';
import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';
import '../../core/money_format.dart';
import '../../core/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/page_transitions.dart';
import '../../theme/pressable.dart';
import '../daily_orders/order_detail_screen.dart';
import '../history/day_orders_screen.dart';
import 'glass_dashboard_stats.dart';

/// v27.22 Insights tab — a dark glass dashboard in the spirit of the
/// video's web dashboard (deep dark surface, soft blue glows, glass stat
/// cards, a weekly bar chart, recent orders).
///
/// Intentional dark surface: like the video, this screen is dark even
/// when the app theme is light — it is a dashboard surface, not a
/// theme change. All numbers come from the real database/providers;
/// nothing here is made-up or seeded data. Home (DashboardScreen) is
/// untouched; this is a separate tab.
class GlassDashboardScreen extends ConsumerWidget {
  const GlassDashboardScreen({super.key});

  static const _bgTop = Color(0xFF0B1220);
  static const _bgBottom = Color(0xFF060913);
  static const _glowBlue = Color(0xFF2563EB);
  static const _glowCyan = Color(0xFF38BDF8);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final today = WeekCalendar.dateOnly(DateTime.now());
    final todayKey = WeekCalendar.dateKey(today);
    final reportAsync = ref.watch(weeklyReportProvider(today));
    final db = ref.watch(databaseServiceProvider);
    final lang = settings.languageCode == 'ar' ? 'ar' : 'en';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgTop, _bgBottom],
        ),
      ),
      child: Stack(
        children: [
          // Soft blue glows, plain gradients — no BackdropFilter here,
          // so the background costs nothing on scroll.
          Positioned(
            top: -90,
            right: -70,
            child: _glow(_glowBlue.withValues(alpha: 0.35), 260),
          ),
          Positioned(
            top: 260,
            left: -90,
            child: _glow(_glowCyan.withValues(alpha: 0.22), 220),
          ),
          reportAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
            error: (e, _) => Center(
              child: Text('$e', style: const TextStyle(color: Colors.white)),
            ),
            data: (report) => _body(context, ref, l10n, report, db,
                settings, today, todayKey, lang),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      );

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    WeeklyReport report,
    DatabaseService db,
    UserSettings settings,
    DateTime today,
    String todayKey,
    String lang,
  ) {
    final price = settings.orderPrice;
    final fixed = settings.dailyFixedPay;
    final configured = price != null && fixed != null;
    DayBreakdown? todayDay;
    for (final d in report.days) {
      if (d.dateKey == todayKey) todayDay = d;
    }
    final todayOrders = todayDay?.orders ?? 0;
    final todayKm = todayDay?.kmTotal ?? 0;
    final todayEarn = todayDay == null
        ? 0.0
        : dayBreakdownEarnings(
            todayDay,
            orderPrice: price ?? 0,
            dailyFixedPay: fixed ?? 0,
          );
    final weekSalary = configured
        ? report.salaryTotal(orderPrice: price, dailyFixedPay: fixed)
        : null;

    // Chart: one bar per week day, in report order (Sunday-first).
    final chartValues = [
      for (final d in report.days)
        dayBreakdownEarnings(
          d,
          orderPrice: price ?? 0,
          dailyFixedPay: fixed ?? 0,
        ),
    ];
    final chartKeys = [for (final d in report.days) d.dateKey];

    // Recent orders: entries from the last 14 days, newest first.
    final allEntries = <OrderEntry>[];
    for (var i = 0; i < 14; i++) {
      final key =
          WeekCalendar.dateKey(WeekCalendar.addDays(today, -i));
      final record = db.orderRecord(key);
      if (record != null) allEntries.addAll(record.entries);
    }
    final recent = recentOrders(allEntries);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.navInsights,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${DateFormat('d MMMM', lang).format(WeekCalendar.parseDateKey(report.weekStartKey))}'
            ' – '
            '${DateFormat('d MMMM', lang).format(WeekCalendar.parseDateKey(report.weekEndKey))}',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  context,
                  icon: Icons.shopping_bag_rounded,
                  label: l10n.insightsTodayOrders,
                  value: '$todayOrders',
                  onTap: () => _openDay(context, todayKey),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  context,
                  icon: Icons.payments_rounded,
                  label: l10n.insightsTodayEarnings,
                  value: configured
                      ? '${formatMoney(todayEarn)} ${l10n.egpUnit}'
                      : '–',
                  onTap: () => context.go('/reports'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  context,
                  icon: Icons.route_rounded,
                  label: l10n.insightsTodayDistance,
                  value:
                      '${todayKm.toStringAsFixed(1)} ${l10n.insightsKm}',
                  onTap: () => context.go('/reports'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  context,
                  icon: Icons.account_balance_wallet_rounded,
                  label: l10n.insightsWeekSalary,
                  value: weekSalary == null
                      ? '–'
                      : '${formatMoney(weekSalary)} ${l10n.egpUnit}',
                  onTap: () => context.go('/reports'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _glassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.insightsEarningsChart,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 170,
                  child: BarChart(
                    BarChartData(
                      maxY: chartCeiling(chartValues),
                      barGroups: [
                        for (var i = 0; i < chartValues.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: chartValues[i],
                                width: 18,
                                borderRadius: BorderRadius.circular(6),
                                gradient: const LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [_glowBlue, _glowCyan],
                                ),
                              ),
                            ],
                          ),
                      ],
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        touchCallback: (event, response) {
                          if (event is FlTapUpEvent &&
                              response?.spot != null) {
                            final idx =
                                response!.spot!.touchedBarGroupIndex;
                            if (idx >= 0 && idx < chartKeys.length) {
                              _openDay(context, chartKeys[idx]);
                            }
                          }
                        },
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, _) {
                              final idx = v.toInt();
                              if (idx < 0 || idx >= chartKeys.length) {
                                return const SizedBox.shrink();
                              }
                              final day = WeekCalendar.parseDateKey(
                                chartKeys[idx],
                              );
                              final letter = DateFormat('EEEE', lang)
                                  .format(day)
                                  .substring(0, 1);
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  letter,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.insightsRecentOrders,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            Text(
              l10n.insightsNoRecentOrders,
              style: const TextStyle(color: Colors.white60),
            ),
          for (final entry in recent)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              // Rows are plain dark containers — no per-row blur, so
              // the list scrolls without re-rasterizing blur surfaces.
              child: Pressable(
                onTap: () => Navigator.of(context).push(
                  SmoothPageRoute(
                    builder: (_) => OrderDetailScreen(
                      dateKey: entry.dateKey,
                      entryId: entry.id,
                    ),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_shipping_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('EEEE d MMMM', lang).format(
                                WeekCalendar.parseDateKey(entry.dateKey),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            if (entry.notes.isNotEmpty)
                              Text(
                                entry.notes,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${(entry.kmOut + entry.kmBack).toStringAsFixed(1)} ${l10n.insightsKm}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openDay(BuildContext context, String dateKey) {
    Navigator.of(context).push(
      SmoothPageRoute(builder: (_) => DayOrdersScreen(dateKey: dateKey)),
    );
  }

  /// One dark glass stat card. The blur is cached behind a
  /// RepaintBoundary (v27.21 performance law) and sigma stays at the
  /// existing glass value — press gives the mobile equivalent of the
  /// video's hover lift (a press dip, not a hover).
  Widget _statCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Pressable(
      onTap: onTap,
      child: _glassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _glowCyan, size: 22),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 12.5),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
