import '../../core/database/models.dart';

/// Pure computations for the v27.22 glass dashboard (Insights tab).
///
/// Everything here is derived from real stored data — no demo numbers.
/// A day earns the daily fixed pay exactly when it has at least one
/// counted order, the same rule WeeklyReport.paidDaysCount uses.

/// A day with at least one counted order earns the daily fixed pay.
bool paidDayForOrders(int orders) => orders >= 1;

/// One day's earnings, using the single salary formula's per-day parts:
/// counted orders × order price + daily fixed pay (only on paid days) +
/// distance + manual + flat bonuses of that day.
double dayEarnings({
  required int orders,
  required double orderPrice,
  required double dailyFixedPay,
  required double distanceBonus,
  required double manualBonus,
  required double flatBonus,
}) =>
    orders * orderPrice +
    (paidDayForOrders(orders) ? dailyFixedPay : 0) +
    distanceBonus +
    manualBonus +
    flatBonus;

/// Earnings for one [DayBreakdown] of a weekly report.
double dayBreakdownEarnings(
  DayBreakdown day, {
  required double orderPrice,
  required double dailyFixedPay,
}) =>
    dayEarnings(
      orders: day.orders ?? 0,
      orderPrice: orderPrice,
      dailyFixedPay: dailyFixedPay,
      distanceBonus: day.distanceBonus,
      manualBonus: day.manualBonus,
      flatBonus: day.flatBonus,
    );

/// Most recent order entries first (newest completion/creation first),
/// capped at [limit]. Input order does not matter.
List<OrderEntry> recentOrders(List<OrderEntry> entries, {int limit = 8}) {
  final sorted = List<OrderEntry>.of(entries)
    ..sort((a, b) => b.timestampMillis.compareTo(a.timestampMillis));
  return sorted.take(limit).toList();
}

/// Chart ceiling: a little headroom above the largest bar, never zero
/// (so an all-zero week still draws an axis).
double chartCeiling(List<double> values) {
  var max = 0.0;
  for (final v in values) {
    if (v > max) max = v;
  }
  return max <= 0 ? 100 : max * 1.2;
}
