// v27.36 — Continuous foreground auto-sync.
//
// Until v27.36 DeliveryFlow had ZERO snapshot listeners: a manager
// edit never reached a driver while the app was running. These
// tests prove the live sync service against the shared fake backend
// (extended with manual snapshot emits) + real Hive apply:
//
//   - a listener applies an incoming cloud change with the merge
//     rules (manager stamps survive, report shows cloud values);
//   - an incoming snapshot never overwrites a pending local change,
//     the pending queue stays intact, and it flushes once writes
//     succeed again;
//   - listeners attach on session restore and detach on sign-out
//     (an emit after stop is NOT applied; a re-start re-attaches);
//   - the manager dashboard live-updates while open (users stream
//     + per-user summary streams fire dataChanged);
//   - a local edit uploads promptly while running;
//   - start-time reconcile never overwrites a manager edit;
//   - listener errors surface loudly with the exact reason (one per
//     episode) while other streams keep working;
//   - a sync apply never echoes back up (no upload loop).
//
// Hive tests use a temp database (same pattern as v27.33/v27.35).
// All values are dummies; no real data appears here.
import 'dart:async';
import 'dart:io';

import 'package:deliveryflow/core/cloud/cloud_live_sync.dart';
import 'package:deliveryflow/core/cloud/cloud_services.dart';
import 'package:deliveryflow/core/cloud/cloud_types.dart';
import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/features/cloud/cloud_download_apply.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'v27_33_test.dart' show FakeCloudBackend;

const _day = '2026-10-25';

CloudDaySummary cloudSummary({
  required String uid,
  int orders = 0,
  double km = 0,
  double manual = 0,
  int updatedAt = 0,
  String dateKey = _day,
  bool managerEdited = false,
}) {
  var summary = buildDaySummary(
    uid: uid,
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
  Future<DatabaseService> tempDb() async {
    final tmp = await Directory.systemTemp.createTemp('df_v2736_');
    addTearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });
    final db = DatabaseService();
    await db.init(hivePath: tmp.path);
    return db;
  }

  /// Signed-in fake backend + live sync wired to the real apply.
  /// [signInAsManager] signs in as a manager account instead.
  Future<(FakeCloudBackend, CloudAccount, CloudLiveSync)>
      signedInLiveSync({
    required DatabaseService db,
    bool signInAsManager = false,
  }) async {
    final backend = FakeCloudBackend();
    final auth = CloudAuthService(backend);
    final created = await auth.signUp(
      email: 'd@x.y',
      password: 'pw123456',
      username: 'driver1',
    );
    CloudAccount account = created;
    if (signInAsManager) {
      // The fake's sign-up always creates a driver; promote via the
      // public users map (the console equivalent), then sign in.
      backend.users[created.uid] = CloudAccount(
        uid: created.uid,
        email: 'd@x.y',
        username: 'driver1',
        role: CloudRole.manager,
      );
      await auth.signOut();
      account = await auth.signIn(email: 'd@x.y', password: 'pw123456');
    }
    final sync = CloudSyncService(backend);
    final live = CloudLiveSync(
      backend: backend,
      sync: sync,
      db: db,
      applyDownload: (download) async {
        final result = await applyCloudDownload(db: db, download: download);
        return result.changedDays + result.clearedDays;
      },
      snapshotDebounce: Duration.zero,
      changeDebounce: Duration.zero,
    );
    addTearDown(() async {
      await live.stop();
    });
    return (backend, account, live);
  }

  /// Wait for stream/timer delivery (debounces are Duration.zero,
  /// so a few event-loop turns suffice).
  Future<void> settle() =>
      Future.delayed(const Duration(milliseconds: 30));

  group('v27.36 live sync', () {
    test('listener applies an incoming cloud change (merge rules)',
        () async {
      final db = await tempDb();
      final record = await db.upsertOrderRecord(
        dateKey: _day,
        completedOrders: 5,
      );
      record.updatedAtMillis = 1000;
      await record.save();
      final (backend, account, live) = await signedInLiveSync(db: db);
      await live.start(account);
      await settle();
      // No cloud data at start: nothing applied yet.
      expect(db.orderRecord(_day)!.cloudOverrideApplied, isFalse);

      final changed = Completer<void>();
      final sub = live.dataChanged.listen((_) {
        if (!changed.isCompleted) changed.complete();
      });
      addTearDown(sub.cancel);

      // Manager edit arrives WHILE the app runs.
      (backend.summaries[account.uid] ??= {})[_day] = cloudSummary(
        uid: account.uid,
        orders: 7,
        km: 42,
        manual: 100,
        updatedAt: 2000,
        managerEdited: true,
      );
      backend.emitSummaries(account.uid);
      await changed.future.timeout(const Duration(seconds: 5));

      final applied = db.orderRecord(_day)!;
      expect(applied.cloudOverrideApplied, isTrue);
      expect(applied.cloudOrders, 7);
      expect(applied.cloudEditedByManager, isTrue);
      final day = db
          .buildWeeklyReport(DateTime(2026, 10, 25))
          .days
          .firstWhere((d) => d.dateKey == _day);
      expect(day.orders, 7);
      expect(day.kmTotal, 42);
      expect(day.manualBonus, 100);
    });

    test('incoming snapshot never overwrites a pending local change',
        () async {
      final db = await tempDb();
      final (backend, account, live) = await signedInLiveSync(db: db);
      backend.failWrites = true;
      final record = await db.upsertOrderRecord(
        dateKey: _day,
        completedOrders: 5,
      );
      record.updatedAtMillis = 1000;
      await record.save();
      await live.start(account);
      await settle();
      // Reconcile tried to upload the local day and failed: queued.
      expect(backend.summaries[account.uid]?[_day], isNull);

      // Local edit while offline: also queued, never lost.
      await db.upsertOrderRecord(dateKey: _day, completedOrders: 6);
      await settle();

      // A cloud doc arrives (older than the local edit): the merge
      // must keep the local values, and the queue must stay intact.
      (backend.summaries[account.uid] ??= {})[_day] = cloudSummary(
        uid: account.uid,
        orders: 7,
        km: 42,
        manual: 100,
        updatedAt: 2000,
        managerEdited: true,
      );
      backend.emitSummaries(account.uid);
      await settle();
      final day = db
          .buildWeeklyReport(DateTime(2026, 10, 25))
          .days
          .firstWhere((d) => d.dateKey == _day);
      expect(day.orders, 6);
      // The live sync's queue still holds the pending uploads:
      // prove it by flushing through resume once writes succeed.
      backend.failWrites = false;
      await live.onAppResumed();
      await settle();
      expect(
        backend.summaries[account.uid]![_day]!.ordersCount,
        6,
        reason: 'pending local change uploads once online again',
      );
    });

    test('listeners attach on restore, detach on sign-out', () async {
      final db = await tempDb();
      final (backend, account, live) = await signedInLiveSync(db: db);
      // Session restore = start with an already-signed-in account.
      await live.start(account);
      expect(live.isRunning, isTrue);
      await settle();

      (backend.summaries[account.uid] ??= {})[_day] = cloudSummary(
        uid: account.uid,
        orders: 7,
        updatedAt: 2000,
        managerEdited: true,
      );
      backend.emitSummaries(account.uid);
      await settle();
      expect(db.orderRecord(_day)!.cloudOrders, 7);

      // Sign-out detaches: a later emit must NOT apply.
      await live.stop();
      expect(live.isRunning, isFalse);
      (backend.summaries[account.uid] ??= {})[_day] = cloudSummary(
        uid: account.uid,
        orders: 9,
        updatedAt: 3000,
        managerEdited: true,
      );
      backend.emitSummaries(account.uid);
      await settle();
      expect(db.orderRecord(_day)!.cloudOrders, 7);

      // Sign-in again re-attaches (initial download-apply picks the
      // newer cloud doc up even before any new emit).
      await live.start(account);
      await settle();
      expect(db.orderRecord(_day)!.cloudOrders, 9);
    });

    test('manager dashboard live-updates while open', () async {
      final db = await tempDb();
      final (backend, account, live) = await signedInLiveSync(
        db: db,
        signInAsManager: true,
      );
      // A driver already on the team when the manager opens the app.
      const driverUid = 'driver_uid';
      backend.users[driverUid] = const CloudAccount(
        uid: driverUid,
        email: 'other@x.y',
        username: 'other',
      );
      await live.start(account);
      await settle();

      var events = 0;
      final sub = live.dataChanged.listen((_) => events++);
      addTearDown(sub.cancel);

      // A new driver joins: users stream fires.
      backend.users['new_uid'] = const CloudAccount(
        uid: 'new_uid',
        email: 'new@x.y',
        username: 'newbie',
      );
      backend.emitUsers();
      await settle();
      expect(events, greaterThanOrEqualTo(1));

      // An existing driver changes a day: per-user stream fires.
      final before = events;
      (backend.summaries[driverUid] ??= {})[_day] = cloudSummary(
        uid: driverUid,
        orders: 3,
        updatedAt: 2000,
      );
      backend.emitSummaries(driverUid);
      await settle();
      expect(events, greaterThan(before));

      // After sign-out, manager streams go quiet.
      await live.stop();
      final stopped = events;
      backend.emitUsers();
      backend.emitSummaries(driverUid);
      await settle();
      expect(events, stopped);
    });

    test('local edit uploads promptly while running', () async {
      final db = await tempDb();
      final (backend, account, live) = await signedInLiveSync(db: db);
      await live.start(account);
      await settle();

      await db.upsertOrderRecord(dateKey: _day, completedOrders: 5);
      await settle();
      expect(
        backend.summaries[account.uid]![_day]!.ordersCount,
        5,
      );
      expect(
        backend.orders[account.uid]![_day]!['completedOrders'],
        5,
      );
    });

    test('reconcile on start never overwrites a manager edit',
        () async {
      final db = await tempDb();
      final record = await db.upsertOrderRecord(
        dateKey: _day,
        completedOrders: 5,
      );
      record.updatedAtMillis = 1000;
      await record.save();
      final (backend, account, live) = await signedInLiveSync(db: db);
      // Manager edit is NEWER than the local day before start.
      (backend.summaries[account.uid] ??= {})[_day] = cloudSummary(
        uid: account.uid,
        orders: 7,
        km: 42,
        manual: 100,
        updatedAt: 5000,
        managerEdited: true,
      );
      await live.start(account);
      await settle();
      // The cloud doc is untouched by the local day…
      expect(
        backend.summaries[account.uid]![_day]!.ordersCount,
        7,
      );
      // …and the driver sees the manager's values.
      final day = db
          .buildWeeklyReport(DateTime(2026, 10, 25))
          .days
          .firstWhere((d) => d.dateKey == _day);
      expect(day.orders, 7);
      expect(day.manualBonus, 100);
    });

    test('listener error surfaces loudly; other streams keep working',
        () async {
      final db = await tempDb();
      final (backend, account, live) = await signedInLiveSync(db: db);
      await live.start(account);
      await settle();

      final failures = <LiveSyncFailure>[];
      final sub = live.failures.listen(failures.add);
      addTearDown(sub.cancel);

      backend.failSummaries(account.uid, Exception('boom'));
      await settle();
      expect(failures, hasLength(1));
      expect(failures.single.source, 'summaries');
      expect(failures.single.reason, contains('boom'));

      // Same episode again: no duplicate dialog.
      backend.failSummaries(account.uid, Exception('boom'));
      await settle();
      expect(failures, hasLength(1));

      // A successful event clears the episode; the same error then
      // surfaces again as a new episode.
      backend.emitSummaries(account.uid);
      await settle();
      backend.failSummaries(account.uid, Exception('boom'));
      await settle();
      expect(failures, hasLength(2));

      // Orders stream unaffected by the summaries failure.
      backend.emitOrders(account.uid);
      await settle();
      expect(failures, hasLength(2));
    });

    test('sync apply does not echo back up (no upload loop)',
        () async {
      final db = await tempDb();
      final record = await db.upsertOrderRecord(
        dateKey: _day,
        completedOrders: 5,
      );
      record.updatedAtMillis = 1000;
      await record.save();
      final (backend, account, live) = await signedInLiveSync(db: db);
      await live.start(account);
      await settle();
      // Start-time reconcile uploaded the local day once.
      final callsAfterStart = backend.saveDaySummaryCalls;
      expect(callsAfterStart, 1);

      (backend.summaries[account.uid] ??= {})[_day] = cloudSummary(
        uid: account.uid,
        orders: 7,
        updatedAt: 2000,
        managerEdited: true,
      );
      backend.emitSummaries(account.uid);
      await settle();
      expect(db.orderRecord(_day)!.cloudOrders, 7);
      // The apply fired no day-change event, so no echo upload.
      expect(backend.saveDaySummaryCalls, callsAfterStart);
    });
  });
}
