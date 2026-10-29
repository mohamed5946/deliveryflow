// v27.33 — Management dashboard logic (pure functions, no widgets).
//
// Every number on the dashboard derives from daily summary docs only
// (one small doc per driver per day), so a ~30-driver team costs the
// manager ~30 reads per day view, not thousands of raw orders.
//
// Honesty rules encoded here:
// - A driver WITHOUT a summary for the selected day is "not synced",
//   never silently shown as zero. Totals sum synced rows only.
// - A driver WITH a summary of 0 orders is synced and zero — a
//   different, visible state (zero-order alert, not sync alert).
// - The data model carries no in-progress / failed / pending order
//   state, so the dashboard never invents one: alerts cover only
//   zero orders and not-synced drivers.

import '../../core/cloud/adjustment_logic.dart';
import '../../core/cloud/cloud_types.dart';

/// yyyy-MM-dd for a calendar date (same format as [CloudDaySummary.dateKey]).
String managementDateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// One dashboard row: a driver plus their summary for the day, if any.
class DriverDayRow {
  const DriverDayRow({required this.account, this.summary});

  final CloudAccount account;
  final CloudDaySummary? summary;

  /// Synced = a summary doc exists for the day (even with 0 orders).
  bool get synced => summary != null;

  int get orders => summary?.ordersCount ?? 0;
  double get km => summary?.totalKm ?? 0;
  double get salary => summary?.salaryTotal ?? 0;
}

/// Build rows for every user: a user without a summary for the day
/// still gets a row, flagged unsynced — never dropped.
List<DriverDayRow> buildDriverRows(
  List<CloudAccount> users,
  List<CloudDaySummary> summaries,
) {
  final byUid = {for (final s in summaries) s.uid: s};
  return [
    for (final user in users)
      DriverDayRow(account: user, summary: byUid[user.uid]),
  ];
}

/// Glanceable totals for the selected day. Sums synced rows only.
class DashboardKpis {
  const DashboardKpis({
    required this.driversActive,
    required this.totalOrders,
    required this.totalKm,
    required this.salaryDue,
  });

  final int driversActive;
  final int totalOrders;
  final double totalKm;
  final double salaryDue;
}

DashboardKpis computeKpis(List<DriverDayRow> rows) {
  var orders = 0;
  var km = 0.0;
  var salary = 0.0;
  var active = 0;
  for (final row in rows) {
    if (!row.synced) continue;
    active++;
    orders += row.orders;
    km += row.km;
    salary += row.salary;
  }
  return DashboardKpis(
    driversActive: active,
    totalOrders: orders,
    totalKm: km,
    salaryDue: salary,
  );
}

enum ManagementSort { orders, salary, name }

/// Case-insensitive name search; empty query returns all rows.
List<DriverDayRow> filterDrivers(List<DriverDayRow> rows, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return rows;
  return [
    for (final row in rows)
      if (row.account.displayName.toLowerCase().contains(q)) row,
  ];
}

/// Sort: orders desc, salary desc, or name A-Z. Ties keep name order
/// so the list never shuffles between refreshes.
List<DriverDayRow> sortDrivers(List<DriverDayRow> rows, ManagementSort sort) {
  final sorted = [...rows];
  switch (sort) {
    case ManagementSort.orders:
      sorted.sort((a, b) {
        final c = b.orders.compareTo(a.orders);
        return c != 0
            ? c
            : a.account.displayName.compareTo(b.account.displayName);
      });
    case ManagementSort.salary:
      sorted.sort((a, b) {
        final c = b.salary.compareTo(a.salary);
        return c != 0
            ? c
            : a.account.displayName.compareTo(b.account.displayName);
      });
    case ManagementSort.name:
      sorted.sort(
        (a, b) => a.account.displayName.compareTo(b.account.displayName),
      );
  }
  return sorted;
}

/// What needs attention today. No invented states: only zero orders
/// (synced) and not synced.
class DashboardAlerts {
  const DashboardAlerts({
    required this.zeroOrders,
    required this.notSynced,
  });

  final List<DriverDayRow> zeroOrders;
  final List<DriverDayRow> notSynced;

  bool get isEmpty => zeroOrders.isEmpty && notSynced.isEmpty;
}

DashboardAlerts findAlerts(List<DriverDayRow> rows) {
  return DashboardAlerts(
    zeroOrders: [
      for (final row in rows)
        if (row.synced && row.orders == 0) row,
    ],
    notSynced: [for (final row in rows) if (!row.synced) row],
  );
}

/// Orders per day for a week, in [weekDateKeys] order (Sunday..Saturday).
List<int> weekOrdersPerDay(
  Map<String, List<CloudDaySummary>> weekSummaries,
  List<String> weekDateKeys,
) {
  return [
    for (final key in weekDateKeys)
      (weekSummaries[key] ?? []).fold<int>(
        0,
        (sum, s) => sum + s.ordersCount,
      ),
  ];
}

/// Per-driver week totals (orders, km, salary) from the same week data.
class DriverWeekTotals {
  const DriverWeekTotals({
    required this.orders,
    required this.km,
    required this.salary,
  });

  final int orders;
  final double km;
  final double salary;
}

Map<String, DriverWeekTotals> driverWeekTotals(
  Map<String, List<CloudDaySummary>> weekSummaries,
) {
  final orders = <String, int>{};
  final km = <String, double>{};
  final salary = <String, double>{};
  for (final day in weekSummaries.values) {
    for (final s in day) {
      orders[s.uid] = (orders[s.uid] ?? 0) + s.ordersCount;
      km[s.uid] = (km[s.uid] ?? 0) + s.totalKm;
      salary[s.uid] = (salary[s.uid] ?? 0) + s.salaryTotal;
    }
  }
  return {
    for (final uid in orders.keys)
      uid: DriverWeekTotals(
        orders: orders[uid]!,
        km: km[uid]!,
        salary: salary[uid]!,
      ),
  };
}

/// Apply a week's manager adjustments to per-driver week totals:
/// salary becomes base + bonuses − deductions for [weekKey].
/// Orders/km are untouched (adjustments are money-only).
Map<String, DriverWeekTotals> applyAdjustmentsToWeekTotals(
  Map<String, DriverWeekTotals> base,
  Map<String, List<CloudAdjustment>> adjustmentsByUid,
  String weekKey,
) {
  final out = <String, DriverWeekTotals>{};
  for (final entry in base.entries) {
    final signed = adjustmentsForWeek(
      adjustmentsByUid[entry.key] ?? const [],
      weekKey,
    ).fold<double>(0, (sum, a) => sum + a.signedAmount);
    out[entry.key] = DriverWeekTotals(
      orders: entry.value.orders,
      km: entry.value.km,
      salary: entry.value.salary + signed,
    );
  }
  return out;
}
int? lastSyncMillis(List<DriverDayRow> rows) {
  var latest = 0;
  for (final row in rows) {
    final t = row.summary?.updatedAtMillis ?? 0;
    if (t > latest) latest = t;
  }
  return latest == 0 ? null : latest;
}
