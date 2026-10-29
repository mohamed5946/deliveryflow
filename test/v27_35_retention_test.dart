// v27.35 retention — details-only, totals forever (unit + service).
//
// Details (orders, day summaries, adjustments) get an expireAt and
// are deleted by Firestore TTL after 3 weeks; the permanent weekly
// rollup folds adjustments into its stored total, so week totals
// stay correct after the details are gone. Identity docs are never
// retention targets. Sync never uploads (or re-uploads) a detail
// doc old enough to have expired, so it can never resurrect one TTL
// already deleted.
//
// All dates here are relative to the test's own today (or fixed
// calendar dates for pure expiry math), so the tests are stable
// under both timezones. No real values appear in this file.
import 'package:deliveryflow/core/cloud/cloud_services.dart';
import 'package:deliveryflow/core/cloud/cloud_types.dart';
import 'package:deliveryflow/core/cloud/retention_logic.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'v27_33_test.dart' show FakeCloudBackend;

String keyOf(DateTime dt) => WeekCalendar.dateKey(dt);

DateTime today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

CloudDaySummary day(
  String uid,
  String dateKey, {
  int orders = 0,
  double km = 0,
  double price = 0,
  double fixed = 0,
  double distance = 0,
  double manual = 0,
  double flat = 0,
  int updatedAt = 0,
}) {
  final summary = buildDaySummary(
    uid: uid,
    dateKey: dateKey,
    ordersCount: orders,
    totalKm: km,
    orderPrice: price,
    dailyFixedPay: fixed,
    distanceBonus: distance,
    manualBonus: manual,
    flatBonus: flat,
    updatedAtMillis: updatedAt,
  );
  return summary;
}

CloudAdjustment adjustment(
  String uid,
  String weekKey, {
  CloudAdjustmentType type = CloudAdjustmentType.bonus,
  double amount = 0,
  String id = 'adj1',
}) =>
    CloudAdjustment(
      id: id,
      uid: uid,
      type: type,
      amount: amount,
      reason: 'test reason',
      weekKey: weekKey,
      createdBy: 'manager_uid',
      createdAtMillis: 1,
    );

void main() {
  group('v27.35 retention expiry math', () {
    test('detail expiry is date + 21 days, DST-safe', () {
      expect(detailExpireAtDate('2026-10-25'), DateTime(2026, 11, 15));
      expect(detailExpireAtDate('2026-10-29'), DateTime(2026, 11, 19));
      // Month + leap-year boundaries (constructor arithmetic).
      expect(detailExpireAtDate('2024-02-10'), DateTime(2024, 3, 2));
      expect(detailExpireAtDate('2026-12-20'), DateTime(2027, 1, 10));
    });

    test('isDetailExpired: 21+ days old is expired, 20 days is not',
        () {
      final now = today();
      String daysAgo(int n) => keyOf(WeekCalendar.addDays(now, -n));
      expect(isDetailExpired(daysAgo(30), now), isTrue);
      expect(isDetailExpired(daysAgo(21), now), isTrue);
      expect(isDetailExpired(daysAgo(20), now), isFalse);
      expect(isDetailExpired(daysAgo(0), now), isFalse);
    });

    test('isWeekExpired: week-start MORE than 21 days old', () {
      final now = today();
      // Relative checks that hold any weekday: four Sundays back is
      // always 28+ days old (expired); this Sunday is 0-6 days old.
      final thisSunday = WeekCalendar.weekStart(now);
      expect(
        isWeekExpired(
          keyOf(WeekCalendar.addDays(thisSunday, -28)),
          now,
        ),
        isTrue,
      );
      expect(isWeekExpired(keyOf(thisSunday), now), isFalse);
      // Fixed-date boundary: a Sunday EXACTLY 21 days before the
      // reference Sunday is NOT yet expired (the rule is MORE than
      // 21 days), while 28 days is, and a Sunday 25 days before a
      // Thursday reference is expired.
      expect(
        isWeekExpired('2026-10-04', DateTime(2026, 10, 25)),
        isFalse,
      );
      expect(
        isWeekExpired('2026-09-27', DateTime(2026, 10, 25)),
        isTrue,
      );
      expect(
        isWeekExpired('2026-10-04', DateTime(2026, 10, 29)),
        isTrue,
      );
    });

    test('weekKeyForDateKey and weekDateKeys follow Sunday weeks', () {
      expect(weekKeyForDateKey('2026-10-28'), '2026-10-25');
      expect(weekKeyForDateKey('2026-10-25'), '2026-10-25');
      expect(weekKeyForDateKey('2026-10-31'), '2026-10-25');
      expect(
        weekDateKeys('2026-10-25'),
        [
          '2026-10-25',
          '2026-10-26',
          '2026-10-27',
          '2026-10-28',
          '2026-10-29',
          '2026-10-30',
          '2026-10-31',
        ],
      );
    });
  });

  group('v27.35 weekly rollup', () {
    test('rollup sums components and folds adjustments into the total',
        () {
      const uid = 'driver1';
      const weekKey = '2026-10-25';
      final summaries = [
        day(uid, '2026-10-25',
            orders: 5, km: 40, price: 10, fixed: 100, manual: 20),
        day(uid, '2026-10-27',
            orders: 3, km: 25, price: 10, fixed: 100, distance: 15),
        // Zero-order day: fixed pay must NOT count for it.
        day(uid, '2026-10-28',
            orders: 0, km: 0, price: 10, fixed: 100, flat: 5),
      ];
      final adjustments = [
        adjustment(uid, weekKey,
            type: CloudAdjustmentType.bonus, amount: 50, id: 'a1'),
        adjustment(uid, weekKey,
            type: CloudAdjustmentType.deduction, amount: 30, id: 'a2'),
        // Another week's adjustment must not leak into this rollup.
        adjustment(uid, '2026-11-01',
            type: CloudAdjustmentType.bonus, amount: 999, id: 'a3'),
      ];
      final rollup = buildWeekRollup(
        uid: uid,
        weekKey: weekKey,
        summaries: summaries,
        adjustments: adjustments,
      );
      expect(rollup.ordersCount, 8);
      expect(rollup.totalKm, 65);
      expect(rollup.ordersAmount, 80);
      // Fixed pay only for the two days with >= 1 order.
      expect(rollup.fixedPayAmount, 200);
      expect(rollup.distanceBonus, 15);
      expect(rollup.manualBonus, 20);
      expect(rollup.flatBonus, 5);
      // Base = 5*10+100+20 + 3*10+100+15 + 0*10+0+5 = 170+145+5.
      expect(rollup.salaryBase, 320);
      expect(rollup.adjustmentsTotal, 20);
      expect(rollup.salaryTotal, 340);
      expect(rollup.adjustmentCount, 2);
    });

    test('rollup ignores summaries from other weeks', () {
      const uid = 'driver1';
      final rollup = buildWeekRollup(
        uid: uid,
        weekKey: '2026-10-25',
        summaries: [
          day(uid, '2026-10-25', orders: 2, km: 10, price: 10, fixed: 50),
          day(uid, '2026-11-02', orders: 9, km: 90, price: 10, fixed: 50),
        ],
        adjustments: const [],
      );
      expect(rollup.ordersCount, 2);
      expect(rollup.totalKm, 10);
    });

    test('mergeDaySummaries: cloud wins on shared dates, all days kept',
        () {
      const uid = 'driver1';
      final merged = mergeDaySummaries(
        local: [
          day(uid, '2026-10-25', orders: 5),
          day(uid, '2026-10-26', orders: 1),
        ],
        cloud: [
          // Manager edit of the 25th: 7 orders, not the local 5.
          day(uid, '2026-10-25', orders: 7),
          day(uid, '2026-10-27', orders: 3),
        ],
      );
      expect(
        [for (final s in merged) '${s.dateKey}:${s.ordersCount}'],
        ['2026-10-25:7', '2026-10-26:1', '2026-10-27:3'],
      );
    });
  });

  group('v27.35 sync retention filter (fake backend)', () {
    test('queue drops expired summaries and orders, keeps young ones',
        () async {
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'd@x.y',
        password: 'dummy123',
        username: 'driver1',
        phone: '01012345678',
      );
      final uid = backend.currentAccount!.uid;
      final sync = CloudSyncService(backend);
      final now = today();
      final oldKey = keyOf(WeekCalendar.addDays(now, -40));
      final youngKey = keyOf(now);
      await sync.queueDaySummary(day(uid, oldKey, orders: 9));
      await sync.queueDaySummary(day(uid, youngKey, orders: 2));
      await sync.queueOrderRecord(uid, oldKey, {'dateKey': oldKey});
      await sync.queueOrderRecord(uid, youngKey, {'dateKey': youngKey});
      // Nothing expired was saved or queued; the young docs went up.
      expect(backend.summaries[uid]?.containsKey(oldKey), isFalse);
      expect(backend.summaries[uid]?[youngKey]?.ordersCount, 2);
      expect(backend.orders[uid]?.containsKey(oldKey), isFalse);
      expect(backend.orders[uid]?.containsKey(youngKey), isTrue);
      expect(sync.hasPending, isFalse);
    });

    test('flush drops entries that expired while queued', () async {
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'd@x.y',
        password: 'dummy123',
        username: 'driver1',
        phone: '01012345678',
      );
      final uid = backend.currentAccount!.uid;
      var clock = today();
      final sync = CloudSyncService(
        backend,
        now: () => clock,
      );
      // 20 days old at queue time: young, so it queues (offline).
      final dateKey = keyOf(WeekCalendar.addDays(clock, -20));
      backend.failWrites = true;
      await sync.queueDaySummary(day(uid, dateKey, orders: 4));
      expect(sync.hasPending, isTrue);
      // Two days pass: the entry is now 22 days old — expired.
      backend.failWrites = false;
      clock = WeekCalendar.addDays(clock, 2);
      final uploaded = await sync.flushQueue();
      expect(uploaded, 0);
      expect(sync.hasPending, isFalse);
      expect(
        backend.summaries[uid]?.containsKey(dateKey) ?? false,
        isFalse,
      );
    });

    test('migration never uploads expired local docs', () async {
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'd@x.y',
        password: 'dummy123',
        username: 'driver1',
        phone: '01012345678',
      );
      final uid = backend.currentAccount!.uid;
      final sync = CloudSyncService(backend);
      final now = today();
      final oldKey = keyOf(WeekCalendar.addDays(now, -60));
      final youngKey = keyOf(now);
      var marked = '';
      final done = await sync.migrateLocalDataOnce(
        uid: uid,
        alreadyMigratedUid: null,
        localSummaries: [
          day(uid, oldKey, orders: 9),
          day(uid, youngKey, orders: 3),
        ],
        localOrders: [
          {'dateKey': oldKey},
          {'dateKey': youngKey},
        ],
        markMigrated: (u) async => marked = u,
      );
      expect(done, isTrue);
      expect(marked, uid);
      expect(backend.summaries[uid]?.containsKey(oldKey), isFalse);
      expect(backend.summaries[uid]?[youngKey]?.ordersCount, 3);
      expect(backend.orders[uid]?.containsKey(oldKey), isFalse);
      expect(backend.orders[uid]?.containsKey(youngKey), isTrue);
    });
  });

  group('v27.35 backfill: rollup first, then stamp', () {
    test('backfill writes the rollup and stamps only existing docs',
        () async {
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'd@x.y',
        password: 'dummy123',
        username: 'driver1',
        phone: '01012345678',
      );
      final uid = backend.currentAccount!.uid;
      final sync = CloudSyncService(backend);
      // Cloud already has the 25th (manager-edited: 7 orders) and
      // the 26th; the local device also has the 27th (never
      // uploaded — no cloud doc, so no stamp for it).
      await backend.saveDaySummary(day(uid, '2026-10-25', orders: 7));
      await backend.saveDaySummary(day(uid, '2026-10-26', orders: 2));
      // Adjustments for the week (bonus 50, deduction 10), written
      // straight into the fake's store: the rule under test is the
      // backfill's rollup-then-stamp order, not the manager write
      // guard, which v27.33 tests already cover.
      backend.adjustments[uid] = {
        'a1': adjustment(uid, '2026-10-25',
            type: CloudAdjustmentType.bonus, amount: 50, id: 'a1'),
        'a2': adjustment(uid, '2026-10-25',
            type: CloudAdjustmentType.deduction, amount: 10, id: 'a2'),
      };
      await sync.backfillWeekRollups(
        uid: uid,
        localSummaries: [
          day(uid, '2026-10-25', orders: 5),
          day(uid, '2026-10-27', orders: 4, km: 30, price: 10, fixed: 50),
        ],
      );
      final rollup = await backend.fetchWeekRollup(uid, '2026-10-25');
      expect(rollup, isNotNull);
      // Merged: 25th from cloud (7), 26th from cloud (2), 27th from
      // local (4) — never the stale local 5 for the 25th.
      expect(rollup!.ordersCount, 13);
      expect(rollup.totalKm, 30);
      // Base: 27th only carries pay (7/2-order days have no
      // components in this fixture): 4*10+50 = 90.
      expect(rollup.salaryBase, 90);
      expect(rollup.adjustmentsTotal, 40);
      expect(rollup.salaryTotal, 130);
      expect(rollup.adjustmentCount, 2);
      // Stamps: only for docs that exist in the cloud (25th, 26th
      // + both adjustments). The local-only 27th is NOT stamped —
      // stamping must never create a doc.
      expect(backend.stampedDetails, {'$uid|2026-10-25', '$uid|2026-10-26'});
      expect(
        backend.stampedAdjustments,
        {'$uid|a1', '$uid|a2'},
      );
      // Identity docs untouched by the backfill.
      expect(backend.usernameLookups['driver1'], 'd@x.y');
    });

    test('refreshWeekRollup recomputes from cloud summaries + adjustments',
        () async {
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'd@x.y',
        password: 'dummy123',
        username: 'driver1',
        phone: '01012345678',
      );
      final uid = backend.currentAccount!.uid;
      await backend.saveDaySummary(
        day(uid, '2026-10-25', orders: 6, km: 50, price: 10, fixed: 100),
      );
      backend.adjustments[uid] = {
        'a1': adjustment(uid, '2026-10-25',
            type: CloudAdjustmentType.bonus, amount: 25, id: 'a1'),
      };
      await backend.refreshWeekRollup(uid, '2026-10-25');
      final rollup = await backend.fetchWeekRollup(uid, '2026-10-25');
      expect(rollup, isNotNull);
      expect(rollup!.ordersCount, 6);
      expect(rollup.salaryBase, 160);
      expect(rollup.salaryTotal, 185);
    });
  });
}
