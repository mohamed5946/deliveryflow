// v27.35 driver sync — manual Sync button + download-on-login.
//
// The download direction was unwired before v27.35: manager day
// edits never reached the driver's device. These tests cover the
// merge rule (newer updatedAtMillis wins, never silently drops
// local work, manager stamps survive), the apply-to-Hive step
// (manager values show up in WeeklyReport), flush-before-download
// order, and the offline error surfacing.
//
// Hive tests use a temp database (same pattern as v27.33). All
// values are dummies; no real data appears here.
import 'dart:io';

import 'package:deliveryflow/core/cloud/cloud_services.dart';
import 'package:deliveryflow/core/cloud/cloud_types.dart';
import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:deliveryflow/features/cloud/cloud_download_apply.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'v27_33_test.dart' show FakeCloudBackend;

DailyOrderRecord localRecord({
  int updatedAt = 0,
  bool applied = false,
  int cloudMillis = 0,
  int orders = 0,
}) =>
    DailyOrderRecord(
      id: 'ord_2026-10-25',
      dateKey: '2026-10-25',
      completedOrders: orders,
      createdAtMillis: 0,
      updatedAtMillis: updatedAt,
      cloudOverrideApplied: applied,
      cloudUpdatedAtMillis: cloudMillis,
    );

CloudDaySummary cloudSummary({
  int orders = 0,
  double km = 0,
  double manual = 0,
  int updatedAt = 0,
  String dateKey = '2026-10-25',
  bool managerEdited = false,
}) {
  var summary = buildDaySummary(
    uid: 'driver1',
    dateKey: dateKey,
    ordersCount: orders,
    totalKm: km,
    orderPrice: 10,
    dailyFixedPay: 100,
    distanceBonus: 0,
    manualBonus: manual,
    flatBonus: 0,
    updatedAtMillis: updatedAt,
  );
  if (managerEdited) summary = summary.stampedByManager('mgr1', updatedAt);
  return summary;
}

void main() {
  group('v27.35 merge decision matrix', () {
    test('no local record → apply', () {
      expect(
        decideDayMerge(
          local: null,
          cloud: cloudSummary(orders: 7, updatedAt: 2000),
        ),
        DayMergeDecision.apply,
      );
    });

    test('local newer, no override → keepLocal', () {
      expect(
        decideDayMerge(
          local: localRecord(updatedAt: 3000, orders: 5),
          cloud: cloudSummary(orders: 7, updatedAt: 2000),
        ),
        DayMergeDecision.keepLocal,
      );
    });

    test('cloud newer, no override → apply', () {
      expect(
        decideDayMerge(
          local: localRecord(updatedAt: 1000, orders: 5),
          cloud: cloudSummary(orders: 7, updatedAt: 2000),
        ),
        DayMergeDecision.apply,
      );
    });

    test('undatable cloud doc (updatedAt 0) never overwrites local', () {
      expect(
        decideDayMerge(
          local: localRecord(updatedAt: 1000, orders: 5),
          cloud: cloudSummary(orders: 7, updatedAt: 0),
        ),
        DayMergeDecision.keepLocal,
      );
    });

    test('override already at least as new → keepLocal', () {
      expect(
        decideDayMerge(
          local: localRecord(
            updatedAt: 2000,
            applied: true,
            cloudMillis: 2000,
          ),
          cloud: cloudSummary(orders: 7, updatedAt: 2000),
        ),
        DayMergeDecision.keepLocal,
      );
      expect(
        decideDayMerge(
          local: localRecord(
            updatedAt: 2000,
            applied: true,
            cloudMillis: 2000,
          ),
          cloud: cloudSummary(orders: 7, updatedAt: 1500),
        ),
        DayMergeDecision.keepLocal,
      );
    });

    test('cloud newer than the stored override → apply', () {
      expect(
        decideDayMerge(
          local: localRecord(
            updatedAt: 1000,
            applied: true,
            cloudMillis: 1000,
          ),
          cloud: cloudSummary(orders: 9, updatedAt: 2000),
        ),
        DayMergeDecision.apply,
      );
    });

    test('local edit after the override → clearStaleOverride', () {
      expect(
        decideDayMerge(
          local: localRecord(
            updatedAt: 2500,
            applied: true,
            cloudMillis: 1000,
          ),
          cloud: cloudSummary(orders: 7, updatedAt: 2000),
        ),
        DayMergeDecision.clearStaleOverride,
      );
    });

    test('local edit after the override, but cloud newer still → apply',
        () {
      expect(
        decideDayMerge(
          local: localRecord(
            updatedAt: 2500,
            applied: true,
            cloudMillis: 1000,
          ),
          cloud: cloudSummary(orders: 7, updatedAt: 3000),
        ),
        DayMergeDecision.apply,
      );
    });
  });

  group('v27.35 apply to Hive + WeeklyReport', () {
    Future<DatabaseService> tempDb() async {
      final tmp = await Directory.systemTemp.createTemp('df_v2735_sync_');
      addTearDown(() async {
        await Hive.close();
        await tmp.delete(recursive: true);
      });
      final db = DatabaseService();
      await db.init(hivePath: tmp.path);
      return db;
    }

    test('manager edit applied: report shows cloud orders/km/bonus',
        () async {
      final db = await tempDb();
      final record = await db.upsertOrderRecord(
        dateKey: '2026-10-25',
        completedOrders: 5,
      );
      record.updatedAtMillis = 1000;
      await record.save();
      final result = await applyCloudDownload(
        db: db,
        download: CloudDownload(
          summaries: [
            cloudSummary(
              orders: 7,
              km: 42,
              manual: 100,
              updatedAt: 2000,
              managerEdited: true,
            ),
          ],
          ordersByDateKey: const {},
        ),
      );
      expect(result.changedDays, 1);
      final applied = db.orderRecord('2026-10-25')!;
      expect(applied.cloudOverrideApplied, isTrue);
      expect(applied.cloudOrders, 7);
      expect(applied.cloudEditedByManager, isTrue);
      final report = db.buildWeeklyReport(DateTime(2026, 10, 25));
      final dayBreakdown =
          report.days.firstWhere((d) => d.dateKey == '2026-10-25');
      expect(dayBreakdown.orders, 7);
      expect(dayBreakdown.kmTotal, 42);
      expect(dayBreakdown.manualBonus, 100);
    });

    test('newer local edit wins: cloud values ignored', () async {
      final db = await tempDb();
      final record = await db.upsertOrderRecord(
        dateKey: '2026-10-25',
        completedOrders: 5,
      );
      record.updatedAtMillis = 3000;
      await record.save();
      final result = await applyCloudDownload(
        db: db,
        download: CloudDownload(
          summaries: [
            cloudSummary(orders: 7, km: 42, manual: 100, updatedAt: 2000),
          ],
          ordersByDateKey: const {},
        ),
      );
      expect(result.changedDays, 0);
      expect(result.skippedDays, 1);
      expect(db.orderRecord('2026-10-25')!.cloudOverrideApplied, isFalse);
      final report = db.buildWeeklyReport(DateTime(2026, 10, 25));
      final dayBreakdown =
          report.days.firstWhere((d) => d.dateKey == '2026-10-25');
      expect(dayBreakdown.orders, 5);
      expect(dayBreakdown.manualBonus, 0);
    });

    test('stale override cleared when a local edit supersedes it',
        () async {
      final db = await tempDb();
      final record = await db.upsertOrderRecord(
        dateKey: '2026-10-25',
        completedOrders: 5,
      );
      record.updatedAtMillis = 1000;
      await record.save();
      await applyCloudDownload(
        db: db,
        download: CloudDownload(
          summaries: [
            cloudSummary(orders: 7, km: 42, manual: 100, updatedAt: 2000),
          ],
          ordersByDateKey: const {},
        ),
      );
      expect(db.orderRecord('2026-10-25')!.cloudOverrideApplied, isTrue);
      // The driver edits the day locally (newer than the override).
      await db.upsertOrderRecord(
        dateKey: '2026-10-25',
        completedOrders: 6,
      );
      final result = await applyCloudDownload(
        db: db,
        download: CloudDownload(
          summaries: [
            cloudSummary(orders: 7, km: 42, manual: 100, updatedAt: 2000),
          ],
          ordersByDateKey: const {},
        ),
      );
      expect(result.clearedDays, 1);
      expect(db.orderRecord('2026-10-25')!.cloudOverrideApplied, isFalse);
      final report = db.buildWeeklyReport(DateTime(2026, 10, 25));
      final dayBreakdown =
          report.days.firstWhere((d) => d.dateKey == '2026-10-25');
      expect(dayBreakdown.orders, 6);
      expect(dayBreakdown.manualBonus, 0);
    });

    test('order record without a summary is skipped, never invented',
        () async {
      final db = await tempDb();
      final result = await applyCloudDownload(
        db: db,
        download: const CloudDownload(
          summaries: [],
          ordersByDateKey: {
            '2026-10-25': {'dateKey': '2026-10-25'},
          },
        ),
      );
      expect(result.changedDays, 0);
      expect(result.skippedDays, 1);
      expect(db.orderRecord('2026-10-25'), isNull);
    });
  });

  group('v27.35 runDriverSync orchestration', () {
    Future<DatabaseService> tempDb() async {
      final tmp = await Directory.systemTemp.createTemp('df_v2735_sync2_');
      addTearDown(() async {
        await Hive.close();
        await tmp.delete(recursive: true);
      });
      final db = DatabaseService();
      await db.init(hivePath: tmp.path);
      return db;
    }

    test('flush-first: queued upload lands, then download applies',
        () async {
      final db = await tempDb();
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'd@x.y',
        password: 'dummy123',
        username: 'driver1',
        phone: '01012345678',
      );
      final account = backend.currentAccount!;
      final sync = CloudSyncService(backend);
      // A current-week cloud day (manager edit, no local record).
      final weekDay =
          WeekCalendar.dateKey(WeekCalendar.weekDays(DateTime.now()).first);
      await backend.saveDaySummary(
        buildDaySummary(
          uid: account.uid,
          dateKey: weekDay,
          ordersCount: 7,
          totalKm: 55,
          orderPrice: 10,
          dailyFixedPay: 100,
          distanceBonus: 0,
          manualBonus: 100,
          flatBonus: 0,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      // A local upload queued while offline, for a DIFFERENT
      // current-week day than the manager's (so the two docs can
      // never collide on the same dateKey whatever weekday today is).
      backend.failWrites = true;
      final queuedKey = WeekCalendar.dateKey(
        WeekCalendar.weekDays(DateTime.now())[1],
      );
      await sync.queueDaySummary(
        buildDaySummary(
          uid: account.uid,
          dateKey: queuedKey,
          ordersCount: 3,
          totalKm: 20,
          orderPrice: 10,
          dailyFixedPay: 100,
          distanceBonus: 0,
          manualBonus: 0,
          flatBonus: 0,
        ),
      );
      expect(sync.hasPending, isTrue);
      backend.failWrites = false;
      final result = await runDriverSync(
        account: account,
        sync: sync,
        db: db,
      );
      expect(result.succeeded, isTrue);
      expect(result.flushedUploads, 1);
      expect(sync.hasPending, isFalse);
      expect(
        backend.summaries[account.uid]?[queuedKey]?.ordersCount,
        3,
      );
      expect(result.changedDays, greaterThanOrEqualTo(1));
      expect(db.orderRecord(weekDay)?.cloudOrders, 7);
    });

    test('offline download surfaces an error and changes nothing',
        () async {
      final db = await tempDb();
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'd@x.y',
        password: 'dummy123',
        username: 'driver1',
        phone: '01012345678',
      );
      final account = backend.currentAccount!;
      final sync = CloudSyncService(backend);
      backend.failReads = true;
      final result = await runDriverSync(
        account: account,
        sync: sync,
        db: db,
      );
      expect(result.succeeded, isFalse);
      expect(result.error, contains('offline'));
      expect(result.changedDays, 0);
    });

    test('not signed in returns a plain error, never throws', () async {
      final db = await tempDb();
      final backend = FakeCloudBackend();
      final result = await runDriverSync(
        account: null,
        sync: CloudSyncService(backend),
        db: db,
      );
      expect(result.succeeded, isFalse);
      expect(result.error, 'Not signed in.');
    });
  });
}
