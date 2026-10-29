// v27.33 — Management DASHBOARD (Phase 1 + dashboard expansion).
//
// MANAGER LOGIN FLOW (no shared password, no driver password reuse):
// The manager signs in with his OWN account (Email/Password or
// Google) exactly like a driver. This screen reads the signed-in
// account's user doc `role` field; only `manager` sees the
// dashboard. FIRST MANAGER BOOTSTRAP: after the manager creates his
// account and signs in once, the project owner sets that user's doc
// field `role` to `manager` manually in the Firestore console (Data
// tab); from the next login the dashboard is visible. After that,
// an existing manager promotes/demotes other users from the driver
// detail screen (manager-only, enforced by client + rules; a manager
// can never change his own role).
//
// Layout (fleet/dispatch-dashboard convention, DeliveryFlow's own
// glass language — no copied assets): KPI strip on top for the
// at-a-glance answer, the week trend chart in the middle, the
// searchable/sortable driver table at the bottom, and an alerts panel
// for what needs attention. One hero question per screen — "how did
// we do today / what needs attention?" — with drill-down one tap away.
//
// Guards (UI + backend + firestore.rules): this screen NEVER calls
// listUsers or any summary read unless the signed-in account's role
// is manager. A non-manager (or signed-out user) gets a denied state
// with no team data — never an empty list that could be mistaken for
// "no team".
//
// Data honesty: a driver WITHOUT a summary for the selected day is
// flagged "Not synced" — never silently shown as zero. KPI totals sum
// synced rows only. The data model carries no in-progress / failed /
// pending order state, so no such alert is ever invented.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/cloud/cloud_backend.dart';
import '../../core/cloud/cloud_providers.dart';
import '../../core/cloud/cloud_types.dart';
import '../../core/date_time/week_calendar.dart';
import '../../theme/design_system.dart';
import '../../theme/staggered_entrance.dart';
import 'block_user_flow.dart';
import 'management_dashboard_logic.dart';

class ManagementScreen extends ConsumerStatefulWidget {
  const ManagementScreen({super.key});

  @override
  ConsumerState<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends ConsumerState<ManagementScreen> {
  DateTime _day = DateTime.now();
  String _query = '';
  ManagementSort _sort = ManagementSort.orders;

  String get _dateKey => managementDateKey(_day);

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(cloudAccountProvider).account;
    return GlassScaffold(
      appBar: AppBar(title: const Text('Management')),
      body: SingleChildScrollView(
        padding: GlassTokens.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (account == null)
              const GlassCard(
                key: ValueKey('managementDenied'),
                child: Text(
                  'Sign in with a manager account to view the team.',
                ),
              )
            else if (!account.isManager)
              const GlassCard(
                key: ValueKey('managementDenied'),
                child: Text(
                  'Access denied: this section is for manager '
                  'accounts only.',
                ),
              )
            else if (account.mustChangePassword)
              GlassCard(
                key: const ValueKey('managementForcedChange'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'يجب تغيير كلمة المرور قبل استخدام التطبيق',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This account requires a password change '
                      'before any dashboard access.',
                    ),
                    const SizedBox(height: 12),
                    GlassButton(
                      label: 'Change password',
                      icon: Icons.lock_rounded,
                      onPressed: () => context.push('/cloud-account'),
                    ),
                  ],
                ),
              )
            else ...[
              _DaySelector(
                day: _day,
                onPrev: () => setState(
                  () => _day = _day.subtract(const Duration(days: 1)),
                ),
                onNext: () => setState(
                  () => _day = _day.add(const Duration(days: 1)),
                ),
                onToday: () => setState(() => _day = DateTime.now()),
              ),
              const SizedBox(height: 12),
              _DashboardBody(
                key: ValueKey(_dateKey),
                dateKey: _dateKey,
                day: _day,
                query: _query,
                sort: _sort,
                onQueryChanged: (v) => setState(() => _query = v),
                onSortChanged: (v) => setState(() => _sort = v),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.day,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime day;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('managementPrevDay'),
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: onPrev,
          ),
          Expanded(
            child: Text(
              managementDateKey(day),
              key: const ValueKey('managementDate'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton(
            onPressed: onToday,
            child: const Text('Today'),
          ),
          IconButton(
            key: const ValueKey('managementNextDay'),
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _DashboardData {
  const _DashboardData({
    required this.users,
    required this.daySummaries,
    required this.weekSummaries,
    required this.weekKeys,
    required this.adjustmentsByUid,
    required this.blocked,
  });

  /// Visible team only — blocked (blacklisted) drivers are filtered
  /// out in [_DashboardBody._load], so KPIs, alerts, the week chart
  /// and the driver list never count them.
  final List<CloudAccount> users;
  final List<CloudDaySummary> daySummaries;
  final Map<String, List<CloudDaySummary>> weekSummaries;
  final List<String> weekKeys;

  /// All adjustments per driver (manager read). Week totals add the
  /// signed adjustments for the displayed week so dashboard totals
  /// stay consistent with the weekly salary rule.
  final Map<String, List<CloudAdjustment>> adjustmentsByUid;

  /// Blocked drivers (v27.35 blacklist): shown only in the Blacklist
  /// section, never in the team list, KPIs, alerts, chart or payouts.
  final List<CloudAccount> blocked;
}

/// v27.35 shimmer skeleton for the Management dashboard's loading
/// state. It mirrors the real layout — freshness note, KPI rows,
/// week chart card, search bar, sort chips, driver rows (avatar
/// circle + text lines + salary) — with the same outer gaps, so
/// swapping to real content causes no layout jump. The shine runs
/// on its own (Shimmer.fromColors, no custom animation code).
/// Theme-aware: light base grey.shade300 / highlight grey.shade100,
/// dark base grey.shade800 / highlight grey.shade700.
/// Honest note: shimmer does not make loading faster — it only
/// feels faster.
class _ManagementSkeleton extends StatelessWidget {
  const _ManagementSkeleton();

  Widget _box({
    Key? key,
    required double height,
    double? width,
    BorderRadiusGeometry? radius,
  }) {
    return Container(
      key: key,
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius ?? BorderRadius.circular(GlassTokens.radiusM),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      key: const ValueKey('managementSkeleton'),
      baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
      highlightColor:
          isDark ? Colors.grey.shade700 : Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _box(
            key: const ValueKey('managementSkeletonFreshness'),
            height: 50,
          ),
          const SizedBox(height: 12),
          Column(
            key: const ValueKey('managementSkeletonKpis'),
            children: [
              Row(
                children: [
                  Expanded(child: _box(height: 72)),
                  const SizedBox(width: 12),
                  Expanded(child: _box(height: 72)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _box(height: 72)),
                  const SizedBox(width: 12),
                  Expanded(child: _box(height: 72)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _box(
            key: const ValueKey('managementSkeletonChart'),
            height: 180,
          ),
          const SizedBox(height: 12),
          _box(
            key: const ValueKey('managementSkeletonSearch'),
            height: 56,
            radius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Row(
            key: const ValueKey('managementSkeletonChips'),
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _box(
                  height: 32,
                  width: 76,
                  radius: BorderRadius.circular(16),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < 3; i++) ...[
            Container(
              key: ValueKey('managementSkeletonRow-$i'),
              padding: GlassTokens.cardPadding,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(GlassTokens.radiusM),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _box(height: 14),
                        const SizedBox(height: 6),
                        _box(height: 12, width: 140),
                        const SizedBox(height: 6),
                        _box(height: 12, width: 100),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _box(height: 14, width: 60),
                      const SizedBox(height: 6),
                      _box(height: 12, width: 48),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _DashboardBody extends ConsumerStatefulWidget {
  const _DashboardBody({
    super.key,
    required this.dateKey,
    required this.day,
    required this.query,
    required this.sort,
    required this.onQueryChanged,
    required this.onSortChanged,
  });

  final String dateKey;
  final DateTime day;
  final String query;
  final ManagementSort sort;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<ManagementSort> onSortChanged;

  @override
  ConsumerState<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends ConsumerState<_DashboardBody> {
  late Future<_DashboardData> _future;
  late DateTime _futureDay;
  late int _futureRefresh;

  @override
  void initState() {
    super.initState();
    _futureDay = widget.day;
    _futureRefresh = ref.read(managementRefreshProvider);
    _future = _load(ref.read(cloudBackendProvider), widget.day);
  }

  @override
  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(cloudBackendProvider);
    // v27.35 blacklist: rebuild (and refetch) after a block/unblock,
    // so the team list and the Blacklist section update at once.
    final refresh = ref.watch(managementRefreshProvider);
    // v27.35: memoize the load future per day + refresh signal.
    // Search/sort typing rebuilds this widget constantly, but the
    // team data is filtered client-side — refetching on every
    // keystroke would flash the loading state and drop the search
    // field's focus. Only a day change or an explicit refresh
    // (block/unblock) starts a new load.
    if (refresh != _futureRefresh || widget.day != _futureDay) {
      _futureRefresh = refresh;
      _futureDay = widget.day;
      _future = _load(backend, widget.day);
    }
    final dateKey = widget.dateKey;
    final query = widget.query;
    final sort = widget.sort;
    final onQueryChanged = widget.onQueryChanged;
    final onSortChanged = widget.onSortChanged;
    return FutureBuilder<_DashboardData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          // v27.35 shimmer: if loading, return the skeleton; else
          // return real content (below). No spinner anywhere here.
          return const _ManagementSkeleton();
        }
        if (snap.hasError) {
          return GlassCard(child: Text('Could not load team: ${snap.error}'));
        }
        final data = snap.data!;
        final rows = buildDriverRows(data.users, data.daySummaries);
        final kpis = computeKpis(rows);
        final alerts = findAlerts(rows);
        final weekTotals = applyAdjustmentsToWeekTotals(
          driverWeekTotals(data.weekSummaries),
          data.adjustmentsByUid,
          data.weekKeys.first,
        );
        final weekOrders = weekOrdersPerDay(data.weekSummaries, data.weekKeys);
        final visible = sortDrivers(filterDrivers(rows, query), sort);
        final lastSync = lastSyncMillis(rows);
        final scheme = Theme.of(context).colorScheme;

        return StaggeredScope(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredItem(index: 0, child: _FreshnessNote(lastSync: lastSync)),
              const SizedBox(height: 12),
              StaggeredItem(
                index: 1,
                child: _KpiRow(kpis: kpis, teamSize: data.users.length),
              ),
              const SizedBox(height: 12),
              if (!alerts.isEmpty) ...[
                StaggeredItem(index: 2, child: _AlertsCard(alerts: alerts)),
                const SizedBox(height: 12),
              ],
              StaggeredItem(
                index: 3,
                child: _WeekChartCard(weekOrders: weekOrders),
              ),
              const SizedBox(height: 12),
              StaggeredItem(
                index: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const ValueKey('managementSearch'),
                      decoration: const InputDecoration(
                        hintText: 'Search drivers by name',
                        prefixIcon: Icon(Icons.search_rounded),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: onQueryChanged,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _SortChip(
                          label: 'Orders',
                          selected: sort == ManagementSort.orders,
                          onSelected: () =>
                              onSortChanged(ManagementSort.orders),
                        ),
                        _SortChip(
                          label: 'Salary',
                          selected: sort == ManagementSort.salary,
                          onSelected: () =>
                              onSortChanged(ManagementSort.salary),
                        ),
                        _SortChip(
                          label: 'Name',
                          selected: sort == ManagementSort.name,
                          onSelected: () =>
                              onSortChanged(ManagementSort.name),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                const GlassCard(
                  child: Text('No drivers match this search.'),
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < visible.length; i++) ...[
                      StaggeredItem(
                        index: 5 + i,
                        child: _DriverCard(
                          row: visible[i],
                          week: weekTotals[visible[i].account.uid],
                          dateKey: dateKey,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              // v27.35 blacklist section: blocked drivers only, with
              // an Unblock action each. Their data is kept, so
              // unblocking restores them to the team list above.
              if (data.blocked.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Blacklist',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Blocked drivers cannot sign in and are not counted '
                  'in any total. Their data is kept — unblocking '
                  'restores them fully.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final blockedUser in data.blocked) ...[
                  BlockedDriverCard(
                    account: blockedUser,
                    blockedDateLabel: blockedUser.blockedAt > 0
                        ? managementDateKey(
                            DateTime.fromMillisecondsSinceEpoch(
                              blockedUser.blockedAt,
                            ),
                          )
                        : '',
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              // v27.35 payouts: one row per visible driver for the
              // displayed week (the week the chart shows). Blocked
              // drivers are excluded (data.users is already
              // filtered). Drivers without prefs are still listed
              // as "Not set" with their amount due, so the manager
              // can chase them. Tapping a row opens the payout
              // detail (day-by-day + adjustments) for that driver.
              if (data.users.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Payouts',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Week of ${data.weekKeys.first} — amounts include '
                  'manager bonuses and deductions.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final user in data.users) ...[
                  _PayoutRow(
                    account: user,
                    payout: payoutWeek(
                      summaries: data.weekSummaries.values
                          .expand((list) => list)
                          .where((s) => s.uid == user.uid),
                      adjustments:
                          data.adjustmentsByUid[user.uid] ?? const [],
                      weekKey: data.weekKeys.first,
                    ),
                    dateKey: dateKey,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              const SizedBox(height: 4),
              Text(
                'Sync status is per driver per day. A driver with no '
                'summary for this day has not synced yet — not zero orders.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_DashboardData> _load(CloudBackend backend, DateTime day) async {
    final allUsers = await backend.listUsers();
    // v27.35 blacklist: blocked drivers are out of the team — their
    // rows, KPIs, alerts, week-chart contributions and payout rows
    // must all exclude them. Their data is KEPT (summaries still
    // exist server-side), so the week summaries and adjustments are
    // filtered to visible uids too, not just the user list.
    final users = allUsers.where((u) => !u.blocked).toList();
    final blocked = allUsers.where((u) => u.blocked).toList();
    final visibleUids = users.map((u) => u.uid).toSet();
    final summaries = <CloudDaySummary>[];
    for (final user in users) {
      final s = await backend.fetchDaySummary(user.uid, widget.dateKey);
      if (s != null) summaries.add(s);
    }
    final weekDays = WeekCalendar.weekDays(day);
    final weekKeys = [for (final d in weekDays) managementDateKey(d)];
    final rawWeek = await backend.listSummariesForDays(weekKeys);
    final week = rawWeek.map(
      (key, list) => MapEntry(
        key,
        list.where((s) => visibleUids.contains(s.uid)).toList(),
      ),
    );
    final adjustmentsByUid = <String, List<CloudAdjustment>>{};
    for (final user in users) {
      adjustmentsByUid[user.uid] =
          await backend.listAdjustments(user.uid);
    }
    return _DashboardData(
      users: users,
      daySummaries: summaries,
      weekSummaries: week,
      weekKeys: weekKeys,
      adjustmentsByUid: adjustmentsByUid,
      blocked: blocked,
    );
  }
}

class _FreshnessNote extends StatelessWidget {
  const _FreshnessNote({required this.lastSync});

  final int? lastSync;

  @override
  Widget build(BuildContext context) {
    final text = lastSync == null
        ? 'No driver has synced for this day yet.'
        : () {
            final t =
                DateTime.fromMillisecondsSinceEpoch(lastSync!).toLocal();
            final hh = t.hour.toString().padLeft(2, '0');
            final mm = t.minute.toString().padLeft(2, '0');
            return 'Last sync: $hh:$mm';
          }();
    return GlassCard(
      key: const ValueKey('managementFreshness'),
      child: Row(
        children: [
          const Icon(Icons.sync_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.kpis, required this.teamSize});

  final DashboardKpis kpis;
  final int teamSize;

  @override
  Widget build(BuildContext context) {
    Widget tile(String key, String label, String value) {
      return Expanded(
        child: GlassCard(
          key: ValueKey(key),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            tile('managementKpiDrivers', 'Drivers active',
                '${kpis.driversActive} / $teamSize'),
            const SizedBox(width: 12),
            tile('managementKpiOrders', 'Orders today',
                '${kpis.totalOrders}'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            tile('managementKpiKm', 'Total km',
                '${kpis.totalKm.toStringAsFixed(1)} km'),
            const SizedBox(width: 12),
            tile('managementKpiSalary', 'Salary due',
                '${kpis.salaryDue.toStringAsFixed(0)} EGP'),
          ],
        ),
      ],
    );
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.alerts});

  final DashboardAlerts alerts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String names(List<DriverDayRow> rows) =>
        rows.map((r) => r.account.displayName).join(', ');
    return GlassCard(
      key: const ValueKey('managementAlerts'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: scheme.tertiary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Needs attention',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          if (alerts.notSynced.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Not synced: ${names(alerts.notSynced)}'),
          ],
          if (alerts.zeroOrders.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Zero orders today: ${names(alerts.zeroOrders)}'),
          ],
        ],
      ),
    );
  }
}

class _WeekChartCard extends StatelessWidget {
  const _WeekChartCard({required this.weekOrders});

  final List<int> weekOrders;

  @override
  Widget build(BuildContext context) {
    // Sunday..Saturday, Arabic initials (same convention as reports).
    const dayLetters = ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س'];
    final scheme = Theme.of(context).colorScheme;
    final weekTotal = weekOrders.fold<int>(0, (a, b) => a + b);
    return GlassCard(
      key: const ValueKey('managementWeekChart'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Orders this week',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Text('$weekTotal orders'),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: BarChart(
              BarChartData(
                barGroups: [
                  for (var i = 0; i < weekOrders.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: weekOrders[i].toDouble(),
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
                      getTitlesWidget: (v, _) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          dayLetters[v.toInt() % 7],
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _DriverCard extends ConsumerWidget {
  const _DriverCard({
    required this.row,
    required this.week,
    required this.dateKey,
  });

  final DriverDayRow row;
  final DriverWeekTotals? week;
  final String dateKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final initial = row.account.displayName.isEmpty
        ? '?'
        : row.account.displayName[0].toUpperCase();
    // v27.35 blacklist: swiping a driver row from the side reveals a
    // Block action. Swipe NEVER blocks on its own — tapping the
    // action opens the confirmation dialog, and only confirming
    // there blocks the driver. The action is manager-only by
    // construction: this whole screen is manager-only (drivers see
    // the denied state and never reach a row).
    return Slidable(
      key: ValueKey('managementUserSlidable-${row.account.uid}'),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            key: ValueKey(
              'managementBlockUserAction-${row.account.uid}',
            ),
            onPressed: (_) async {
              final ok = await confirmAndBlockUser(
                context: context,
                ref: ref,
                target: row.account,
              );
              if (ok) bumpManagementRefresh(ref);
            },
            backgroundColor: scheme.error,
            foregroundColor: Colors.white,
            icon: Icons.block_rounded,
            label: 'Block',
          ),
        ],
      ),
      child: GlassCard(
      key: ValueKey('managementUser-${row.account.uid}'),
      onTap: () => context.push(
        '/management/driver?uid=${row.account.uid}&date=$dateKey',
      ),
      child: Row(
        children: [
          // App's existing avatar pattern (order screens): a 40px
          // theme-tinted circle, not a foreign avatar widget.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  row.synced
                      ? '${row.orders} orders · ${row.km.toStringAsFixed(1)} km'
                      : 'No summary for this day',
                ),
                if (week != null)
                  Text(
                    'This week: ${week!.orders} orders · '
                    '${week!.salary.toStringAsFixed(0)} EGP',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${row.salary.toStringAsFixed(0)} EGP',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    row.synced
                        ? Icons.check_circle_rounded
                        : Icons.cloud_off_rounded,
                    size: 14,
                    color:
                        row.synced ? scheme.primary : scheme.tertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    row.synced ? 'Synced' : 'Not synced',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

/// v27.35 payouts — one row per driver for the displayed week.
/// The net amount due is never shown silently: when the week has
/// bonuses or deductions, their totals appear as their own lines
/// next to the net, so the payer sees them before paying.
/// Tapping opens the payout detail (day-by-day + adjustments).
class _PayoutRow extends StatelessWidget {
  const _PayoutRow({
    required this.account,
    required this.payout,
    required this.dateKey,
  });

  final CloudAccount account;
  final DriverPayoutWeek payout;
  final String dateKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showTransfer =
        (account.payoutMethod == CloudPayoutMethod.instapay ||
            account.payoutMethod == CloudPayoutMethod.vodafoneCash);
    return GlassCard(
      key: ValueKey('managementPayout-${account.uid}'),
      onTap: () => context.push(
        '/management/payout?uid=${account.uid}&date=$dateKey',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${payout.net.toStringAsFixed(0)} EGP',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            account.payoutMethod.label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (payout.totalBonus > 0)
            Text(
              '+${payout.totalBonus.toStringAsFixed(0)} EGP bonus',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          if (payout.deduction > 0)
            Text(
              '−${payout.deduction.toStringAsFixed(0)} EGP deduction',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          if (showTransfer && account.payoutNumber.isNotEmpty)
            Text(account.payoutNumber),
          if (showTransfer && account.payoutName.isNotEmpty)
            Text(
              account.payoutName,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
