// v27.35 — Driver-side cloud sync: download + apply.
//
// BACKGROUND (code-verified gap): until v27.35 the cloud DOWNLOAD
// direction had no UI caller — downloadFor/downloadUserData existed
// but nothing called them, so a manager day-edit (e.g. a changed
// Manual bonus) never reached the driver's device. This file wires
// the download + apply path used by the manual Sync button (Cloud
// account screen + Reports screen) and by download-on-login.
//
// ORDER (safe merge, never silently drops local work):
//   1. Flush the pending local upload queue FIRST, so the driver's
//      own unsynced work reaches the cloud before anything is
//      downloaded (a queued upload must never be lost to a download).
//   2. Download the driver's cloud summaries + order records for his
//      dates (every date he has local data for, plus the current
//      week) — reading his OWN docs, which the Firestore rules
//      already allow (no rules change needed for this path).
//   3. Merge each cloud summary into local Hive per [decideDayMerge]:
//      newer updatedAtMillis wins; a newer local edit is never
//      overwritten by an older cloud doc, and a stale override is
//      cleared when a local edit supersedes it. Manager-edited
//      stamps survive the merge as the record's cloudEditedByManager
//      flag + the override values themselves.
//   4. Totals are recomputed by the existing WeeklyReport math — the
//      applied override feeds buildWeeklyReport directly, so day and
//      week views show the manager's values with no separate totals
//      store to drift.
//
// LIMITS (stated honestly, not papered over):
// - Only summaries drive the apply. Order records are downloaded
//   (they are the driver's detail docs) but a day with an order
//   record and NO summary is skipped: without the summary's bonuses
//   there is nothing sound to apply. That state should not occur —
//   manager edits and migration always write both docs together.
// - Manager day DELETES do not propagate: a day missing from the
//   cloud is indistinguishable from a never-uploaded local day
//   without tombstones, so the merge never deletes local days.
// - A manager edit to a day's per-order price or daily fixed pay is
//   stored on the cloud summary but the driver's local week total
//   still recomputes with HIS settings rates; the day's orders, km
//   and bonuses always match the manager's edit. Carrying per-day
//   rates into DayBreakdown is a future step, not this one.
import '../../core/cloud/cloud_services.dart';
import '../../core/cloud/cloud_types.dart';
import '../../core/database/database_service.dart';
import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';

/// Merge decision for one cloud day summary against the local record.
enum DayMergeDecision {
  /// Apply the cloud values (new record, or cloud strictly newer).
  apply,

  /// Keep the local record untouched (local newer, or cloud undatable).
  keepLocal,

  /// The local record was edited after its override was applied:
  /// the local edit wins, so the stale override is cleared and the
  /// day returns to entry-derived values.
  clearStaleOverride,
}

/// Pure merge rule (unit-tested without Hive):
/// - No local record → apply (a fresh device still gets cloud days).
/// - Override already applied: a local edit AFTER the override
///   (record updatedAt past the stored override time) supersedes it
///   — when that edit is also newer than this cloud doc, the stale
///   override is cleared and local wins; when this cloud doc is
///   newer still, it applies over the edit. Otherwise keep when the
///   stored override is at least as new as this cloud doc, else
///   apply. (Comparing only record-updatedAt to cloud-updatedAt
///   would wrongly clear a valid override whose apply itself set
///   the record time — the stored override time is what separates
///   "applied by sync" from "edited locally after".)
/// - No override → apply only when the cloud doc is strictly newer
///   than the local record. A cloud doc with updatedAtMillis == 0
///   (pre-v27.35 summaries carry no timestamp) never overwrites
///   local work — it is undatable, so local wins by default.
DayMergeDecision decideDayMerge({
  required DailyOrderRecord? local,
  required CloudDaySummary cloud,
}) {
  if (local == null) return DayMergeDecision.apply;
  if (local.cloudOverrideApplied) {
    final editedAfterOverride =
        local.updatedAtMillis > local.cloudUpdatedAtMillis;
    if (editedAfterOverride &&
        local.updatedAtMillis > cloud.updatedAtMillis) {
      return DayMergeDecision.clearStaleOverride;
    }
    if (local.cloudUpdatedAtMillis >= cloud.updatedAtMillis) {
      return DayMergeDecision.keepLocal;
    }
    return DayMergeDecision.apply;
  }
  if (cloud.updatedAtMillis == 0) return DayMergeDecision.keepLocal;
  if (local.updatedAtMillis >= cloud.updatedAtMillis) {
    return DayMergeDecision.keepLocal;
  }
  return DayMergeDecision.apply;
}

/// Outcome of applying one download to local Hive.
class CloudApplyResult {
  const CloudApplyResult({
    required this.createdDays,
    required this.updatedDays,
    required this.clearedDays,
    required this.skippedDays,
  });

  /// Days newly created from cloud summaries.
  final int createdDays;

  /// Days whose override was (re-)applied from a newer cloud doc.
  final int updatedDays;

  /// Days whose stale override was cleared by a newer local edit.
  final int clearedDays;

  /// Days skipped (local newer, or order-only without a summary).
  final int skippedDays;

  /// Days the driver visibly gained or changed.
  int get changedDays => createdDays + updatedDays;
}

/// Apply a downloaded [CloudDownload] to local Hive, one summary at
/// a time, per [decideDayMerge]. Order records without a summary are
/// counted as skipped (see the file header for why).
Future<CloudApplyResult> applyCloudDownload({
  required DatabaseService db,
  required CloudDownload download,
}) async {
  var created = 0;
  var updated = 0;
  var cleared = 0;
  var skipped = 0;
  final summaryDates = <String>{};
  for (final summary in download.summaries) {
    summaryDates.add(summary.dateKey);
    final local = db.orderRecord(summary.dateKey);
    switch (decideDayMerge(local: local, cloud: summary)) {
      case DayMergeDecision.apply:
        await db.applyCloudOverride(
          dateKey: summary.dateKey,
          ordersCount: summary.ordersCount,
          kmTotal: summary.totalKm,
          distanceBonus: summary.distanceBonus,
          manualBonus: summary.manualBonus,
          flatBonus: summary.flatBonus,
          cloudUpdatedAtMillis: summary.updatedAtMillis,
          editedByManager: summary.editedByManager,
        );
        if (local == null) {
          created++;
        } else {
          updated++;
        }
      case DayMergeDecision.keepLocal:
        skipped++;
      case DayMergeDecision.clearStaleOverride:
        await db.clearCloudOverride(summary.dateKey);
        cleared++;
    }
  }
  for (final dateKey in download.ordersByDateKey.keys) {
    if (!summaryDates.contains(dateKey)) skipped++;
  }
  return CloudApplyResult(
    createdDays: created,
    updatedDays: updated,
    clearedDays: cleared,
    skippedDays: skipped,
  );
}

/// Outcome of one full driver sync (button or login).
class DriverSyncResult {
  const DriverSyncResult({
    required this.flushedUploads,
    required this.applied,
    this.error,
  });

  /// Queued local uploads flushed before downloading.
  final int flushedUploads;

  /// Applied download outcome (null when the sync failed first).
  final CloudApplyResult? applied;

  /// Plain error text when the sync failed, else null.
  final String? error;

  bool get succeeded => error == null;

  /// Days the driver visibly gained or changed.
  int get changedDays => applied?.changedDays ?? 0;
}

/// Full driver sync: flush queue → download → apply. Never throws:
/// failures are returned as [DriverSyncResult.error] so the UI can
/// show a plain-language message instead of crashing or silently
/// doing nothing.
Future<DriverSyncResult> runDriverSync({
  required CloudAccount? account,
  required CloudSyncService sync,
  required DatabaseService db,
}) async {
  if (account == null) {
    return const DriverSyncResult(
      flushedUploads: 0,
      applied: null,
      error: 'Not signed in.',
    );
  }
  try {
    // 1. Local unsynced work goes up FIRST — never lost to a download.
    final flushed = await sync.flushQueue();
    // 2. Download: every local date + the current week (the manager
    // may have edited a current-week day the driver never recorded
    // locally, e.g. from another device).
    final dateKeys = <String>{
      for (final record in db.allOrderRecords) record.dateKey,
      for (final day in WeekCalendar.weekDays(DateTime.now()))
        WeekCalendar.dateKey(day),
    }.toList()
      ..sort();
    final download = await sync.downloadUserData(account.uid, dateKeys);
    // 3. Merge into Hive with newer-wins.
    final applied = await applyCloudDownload(db: db, download: download);
    return DriverSyncResult(flushedUploads: flushed, applied: applied);
  } catch (e) {
    return DriverSyncResult(
      flushedUploads: 0,
      applied: null,
      error: e.toString(),
    );
  }
}
