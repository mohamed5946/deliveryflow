import 'package:hive/hive.dart';

import 'models.dart';

/// One-time schema migrations for the local Hive store (v27.2 split).
///
/// Extracted from [DatabaseService] on purpose: runtime CRUD and
/// schema evolution are two different responsibilities. This class
/// owns ONLY the upgrade path — it runs once per schema bump, guarded
/// by the `schemaVersion` stamp in the meta box, and never touches
/// live data outside the blocks below.
///
/// Returns short tags describing each block that ran (empty when the
/// store is already current) so the caller can record them in the
/// diagnostics log.
class SchemaMigrations {
  SchemaMigrations._();

  static Future<List<String>> applyIfNeeded({
    required Box<DailyOrderRecord> orders,
    required Box<UserSettings> settings,
    required Box meta,
  }) async {
    final applied = <String>[];
    final stored = meta.get('schemaVersion') as int?;
    if (stored == null || stored < kSchemaVersion) {
      if (stored != null && stored < 10) {
        // v27 (schema 10): orders count only once delivery starts.
        // Records written by older versions counted every created
        // entry immediately — recompute each stored total once,
        // preserving its bulk (non-entry) base. Runs exactly once:
        // the schema stamp below prevents any re-run.
        for (final record in orders.values) {
          final recomputed = recomputedCountedOrders(record);
          if (recomputed != record.completedOrders) {
            record.completedOrders = recomputed;
            await record.save();
          }
        }
        // v27: Google Maps becomes the default automatic navigation
        // ("خلي الخريطة التلقائية هي جوجل ماب"). Existing installs
        // still carrying the old in-app default are switched once;
        // any mode picked manually afterwards persists because this
        // block never runs again (schema stamp).
        final existing = settings.get('user');
        if (existing != null && existing.autoNavMode == 0) {
          existing.autoNavMode = 1;
          await settings.put('user', existing);
        }
        applied.add(
            'schema<10: count-on-start recompute + Google Maps nav default');
      }
      if (stored != null && stored < 11) {
        // v27.1 (schema 11): a bulk count used to live ONLY as the
        // stored number, with no entries — the report's day summary
        // (which reads entries) showed such days as 0/0, and the
        // orders couldn't be listed or deleted individually. Convert
        // each record's undetailed remainder into real count-only
        // entries (born completed). Totals are NOT touched: every
        // converted order is already inside `completedOrders`.
        for (final record in orders.values) {
          final added = countOnlyEntriesForLegacyRemainder(record);
          if (added.isNotEmpty) {
            record.entries.addAll(added);
            await record.save();
          }
        }
        applied.add(
            'schema<11: legacy bulk counts converted to count-only entries');
      }
      // v1 is the first schema; future versions migrate here.
      await meta.put('schemaVersion', kSchemaVersion);
    }
    return applied;
  }
}
