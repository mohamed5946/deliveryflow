// v27.35 — Firestore retention (details-only, totals forever).
//
// The user chose: DELETE detail docs after 3 weeks, KEEP weekly salary
// totals forever. This file is pure logic (no Firebase imports), so it
// is unit-testable without a backend:
//
// DETAIL docs (TTL-deleted, free tier — no Cloud Functions / Blaze):
//   users/{uid}/orders/{dateKey}    — raw day record
//   users/{uid}/summaries/{dateKey} — one day-summary doc per day
//   users/{uid}/adjustments/{id}    — manager bonus / deduction
// Each detail doc carries an `expireAt` Timestamp. Firestore's TTL
// policy (enabled by the project owner in the console — see the
// release report) deletes the doc after that instant. TTL deletion
// is NOT instant: it can lag up to ~24h after expireAt.
//
// PERMANENT docs (never expire, no TTL policy on their collection):
//   users/{uid}/weekRollups/{weekKey} — one rollup per driver per week
// The rollup FOLDS adjustments into its stored total, so the week
// total stays correct after the detail docs (and adjustment docs)
// are gone. No total is ever computed from docs TTL will delete.
//
// IDENTITY docs are NEVER retention targets and are never written
// by anything in this file: users/{uid} profiles, usernames / phones
// / emailUsernames lookups, settings. Retention applies to work data
// only.
//
// ORDERING (the safety invariant): a week's rollup is written FIRST,
// and only then is expireAt stamped on that week's detail docs.
// Backfill (CloudSyncService.backfillWeekRollups) follows this order
// per week, so TTL can never delete details for a week that has no
// rollup. The write-path hooks in FirebaseCloudBackend keep the same
// invariant in effect: a freshly written detail doc's expireAt is in
// the future (its date + 21 days) for current data, and the rollup
// refresh runs in the same write — long before TTL can act (TTL lags
// up to ~24h, the refresh completes in the same second).
//
// Calendar rules (all DST-safe, constructor arithmetic only):
// - A detail doc for date D expires at D + 21 days.
// - A week (Sunday weekKey) counts as older than 3 weeks when its
//   week-start is MORE than 21 days before today.
// - The sync upload filter uses the per-doc rule: a detail doc whose
//   date is 21+ days old is never uploaded, so sync can never
//   resurrect a doc TTL already deleted.
import '../date_time/week_calendar.dart';
import 'adjustment_logic.dart';
import 'cloud_types.dart';

/// Retention window, in days. Details older than this are deleted.
const int retentionDays = 21;

/// The calendar date on which a detail doc for [dateKey] expires
/// (its date + 21 days). The backend converts this to a Firestore
/// Timestamp for the `expireAt` field.
DateTime detailExpireAtDate(String dateKey) =>
    WeekCalendar.addDays(WeekCalendar.parseDateKey(dateKey), retentionDays);

/// The calendar date on which an adjustment for [weekKey] (a Sunday
/// week-start dateKey) expires: week-start + 21 days.
DateTime adjustmentExpireAtDate(String weekKey) =>
    WeekCalendar.addDays(WeekCalendar.parseDateKey(weekKey), retentionDays);

/// True when a detail doc for [dateKey] is already expired relative
/// to [now]: its expireAt instant (midnight at date + 21 days) has
/// been reached. A doc expiring TODAY counts as expired — TTL may
/// already have deleted it, so uploading it now would resurrect it.
bool isDetailExpired(String dateKey, DateTime now) {
  final today = WeekCalendar.dateOnly(now);
  final expireDate = detailExpireAtDate(dateKey);
  return !today.isBefore(expireDate);
}

/// True when the week starting at [weekKey] (a Sunday dateKey) is
/// older than 3 weeks: its week-start is MORE than 21 days before
/// [now]'s date. Exactly 21 days old is NOT yet expired by this
/// week-level definition.
bool isWeekExpired(String weekKey, DateTime now) {
  final today = WeekCalendar.dateOnly(now);
  final start = WeekCalendar.parseDateKey(weekKey);
  return WeekCalendar.daysBetween(start, today) > retentionDays;
}

/// The Sunday weekKey containing [dateKey].
String weekKeyForDateKey(String dateKey) => WeekCalendar.dateKey(
      WeekCalendar.weekStart(WeekCalendar.parseDateKey(dateKey)),
    );

/// The 7 dateKeys (Sunday..Saturday) of the week starting at [weekKey].
List<String> weekDateKeys(String weekKey) {
  final start = WeekCalendar.parseDateKey(weekKey);
  return WeekCalendar.weekDays(start).map(WeekCalendar.dateKey).toList();
}

/// Merge day summaries from two sources for one backfill: cloud docs
/// WIN on a shared dateKey (a manager edit on the cloud is newer truth
/// than the device's local copy), local-only and cloud-only days are
/// all kept. The merged set is what the rollup is built from.
List<CloudDaySummary> mergeDaySummaries({
  required List<CloudDaySummary> local,
  required List<CloudDaySummary> cloud,
}) {
  final merged = <String, CloudDaySummary>{
    for (final s in local) s.dateKey: s,
  };
  for (final s in cloud) {
    merged[s.dateKey] = s;
  }
  final out = merged.values.toList()
    ..sort((a, b) => a.dateKey.compareTo(b.dateKey));
  return out;
}

/// Build the permanent weekly rollup for [weekKey] from a week's day
/// summaries and adjustments. Summaries / adjustments belonging to
/// other weeks are ignored (defensive — callers already filter).
///
/// Component math mirrors the day formula exactly: a day's fixed pay
/// counts only when the day has at least one order (same rule as
/// computeDaySalary). [salaryBase] is the sum of the day totals (the
/// same base the read-time composition used), and [salaryTotal] is
/// base + signed adjustments — folded in, so the total survives after
/// the adjustment docs themselves expire.
CloudWeekRollup buildWeekRollup({
  required String uid,
  required String weekKey,
  required List<CloudDaySummary> summaries,
  required List<CloudAdjustment> adjustments,
  int updatedAtMillis = 0,
}) {
  var ordersCount = 0;
  var totalKm = 0.0;
  var ordersAmount = 0.0;
  var fixedPayAmount = 0.0;
  var distanceBonus = 0.0;
  var manualBonus = 0.0;
  var flatBonus = 0.0;
  var salaryBase = 0.0;
  for (final s in summaries) {
    if (weekKeyForDateKey(s.dateKey) != weekKey) continue;
    ordersCount += s.ordersCount;
    totalKm += s.totalKm;
    ordersAmount += s.ordersCount * s.orderPrice;
    if (s.ordersCount >= 1) fixedPayAmount += s.dailyFixedPay;
    distanceBonus += s.distanceBonus;
    manualBonus += s.manualBonus;
    flatBonus += s.flatBonus;
    salaryBase += s.salaryTotal;
  }
  final weekAdjustments = adjustmentsForWeek(adjustments, weekKey);
  var adjustmentsTotal = 0.0;
  for (final a in weekAdjustments) {
    adjustmentsTotal += a.signedAmount;
  }
  return CloudWeekRollup(
    uid: uid,
    weekKey: weekKey,
    ordersCount: ordersCount,
    totalKm: totalKm,
    ordersAmount: ordersAmount,
    fixedPayAmount: fixedPayAmount,
    distanceBonus: distanceBonus,
    manualBonus: manualBonus,
    flatBonus: flatBonus,
    salaryBase: salaryBase,
    adjustmentsTotal: adjustmentsTotal,
    salaryTotal: salaryBase + adjustmentsTotal,
    adjustmentCount: weekAdjustments.length,
    updatedAtMillis: updatedAtMillis,
  );
}
