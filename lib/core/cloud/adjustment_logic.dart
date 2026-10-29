// v27.33 — Manager adjustments (bonus / deduction) logic (pure).
//
// An adjustment is a WEEKLY additive layer on top of the existing
// salary formula — it never rewrites the base formula and never
// rewrites a day summary. Weekly total =
//   (orders × price + paid days + existing bonuses)
//   + manager bonuses − manager deductions
// for the adjustment's week. Day summaries keep the pure base
// formula so a day's pay stays auditable; every surface that shows
// a WEEK total composes base + adjustments at read time from this
// file, so totals can never drift from the adjustment docs.
import 'cloud_types.dart';

/// Weekly total for one week: base (sum of day-summary totals) plus
/// the signed adjustments belonging to that week.
double weeklyTotalWithAdjustments(
  double baseTotal,
  List<CloudAdjustment> adjustments,
) {
  var total = baseTotal;
  for (final a in adjustments) {
    total += a.signedAmount;
  }
  return total;
}

/// Adjustments of [all] belonging to [weekKey] (week-start dateKey).
List<CloudAdjustment> adjustmentsForWeek(
  List<CloudAdjustment> all,
  String weekKey,
) {
  return [for (final a in all) if (a.weekKey == weekKey) a];
}

/// Validation for the manager's add/edit form. Reason is MANDATORY
/// (a driver must always know why) and amount must be > 0.
/// Returns null when valid, else a human-readable error.
String? validateAdjustment({required double? amount, required String reason}) {
  if (amount == null || amount <= 0) {
    return 'Enter an amount greater than zero.';
  }
  if (reason.trim().isEmpty) {
    return 'Reason is required — the driver must know why.';
  }
  return null;
}
