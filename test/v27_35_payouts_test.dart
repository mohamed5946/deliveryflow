// v27.35 — Driver payout preferences + manager Payouts list +
// payout detail.
//
// Driver side: payout method (InstaPay / Vodafone Cash / Manual) +
// payment number + wallet display name, stored on the cloud profile
// (users/{uid}: payoutMethod, payoutNumber, payoutName). Number +
// name are REQUIRED for InstaPay and Vodafone Cash (Egyptian mobile
// validation, same normalization as login phones); Manual needs
// neither and clears any stale details.
//
// Manager side: a Payouts list on the Management dashboard, one row
// per visible driver for the displayed WEEK (never monthly), amount
// due = week net (day totals + bonus adjustments − deduction
// adjustments). Rows visibly show the week's bonus total ("+Y
// bonus") and deduction total ("−X deduction") next to the net —
// never a silent net. Drivers without prefs are listed as "Not
// set" with their amount due. Blocked drivers are excluded.
// Tapping a row opens the payout detail: day-by-day (Sun–Sat) totals
// with bonus/deduction markers, adjustment lines (reason + amount)
// attributed by createdAtMillis day, and a net total that matches
// the row.
//
// All values here are DUMMY. No real code, password, or secret
// appears in this file.

import 'dart:io';

import 'package:deliveryflow/core/cloud/cloud_providers.dart';
import 'package:deliveryflow/core/cloud/cloud_services.dart';
import 'package:deliveryflow/core/cloud/cloud_types.dart';
import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/cloud/cloud_account_screen.dart';
import 'package:deliveryflow/features/cloud/management_dashboard_logic.dart';
import 'package:deliveryflow/features/cloud/management_payout_screen.dart';
import 'package:deliveryflow/features/cloud/management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'v27_33_test.dart' show FakeCloudBackend;

void main() {
  Future<DatabaseService> tempDb(WidgetTester tester) async {
    late Directory tmp;
    late DatabaseService db;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('df_v2735_pay_');
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
    });
    addTearDown(() => tester.runAsync(() async {
          await Hive.close();
          await tmp.delete(recursive: true);
        }));
    return db;
  }

  /// Signs up a manager + signs in as him. Returns the manager uid.
  Future<String> setupManager(
    FakeCloudBackend backend,
    CloudAccountNotifier notifier,
  ) async {
    await notifier.signUp(
      email: 'boss@x.y',
      password: 'dummy123',
      username: 'Boss',
    );
    final bossUid = backend.users.values.first.uid;
    backend.users[bossUid] = CloudAccount(
      uid: bossUid,
      email: 'boss@x.y',
      username: 'Boss',
      role: CloudRole.manager,
    );
    await notifier.signOut();
    await notifier.signIn(email: 'boss@x.y', password: 'dummy123');
    return bossUid;
  }

  /// Signs up a driver through the backend and returns his uid.
  /// Leaves the backend session on the manager afterwards.
  Future<String> addDriver(
    FakeCloudBackend backend, {
    required String email,
    required String username,
    String phone = '',
  }) async {
    final driver = await backend.signUp(
      email: email,
      password: 'dummy123',
      username: username,
      phone: phone,
    );
    await backend.signOut();
    await backend.signIn(email: 'boss@x.y', password: 'dummy123');
    return driver.uid;
  }

  group('payout validation + storage (backend)', () {
    test('InstaPay requires a valid Egyptian number + wallet name',
        () async {
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'driver@x.y',
        password: 'dummy123',
        username: 'DriverOne',
      );
      await expectLater(
        () => backend.updatePayoutPrefs(
          method: CloudPayoutMethod.instapay,
          number: '',
          name: 'Wallet Name',
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        () => backend.updatePayoutPrefs(
          method: CloudPayoutMethod.instapay,
          number: '123',
          name: 'Wallet Name',
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        () => backend.updatePayoutPrefs(
          method: CloudPayoutMethod.instapay,
          number: '01551234567',
          name: '   ',
        ),
        throwsA(isA<Exception>()),
      );
      // Valid, with messy formatting: stored normalized.
      await backend.updatePayoutPrefs(
        method: CloudPayoutMethod.instapay,
        number: '0155 123 4567',
        name: '  Wallet Name ',
      );
      final saved = backend.users.values.first;
      expect(saved.payoutMethod, CloudPayoutMethod.instapay);
      expect(saved.payoutNumber, '1551234567');
      expect(saved.payoutName, 'Wallet Name');
    });

    test('Manual needs nothing and clears stale transfer details',
        () async {
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'driver@x.y',
        password: 'dummy123',
        username: 'DriverOne',
      );
      await backend.updatePayoutPrefs(
        method: CloudPayoutMethod.vodafoneCash,
        number: '01551234567',
        name: 'Wallet Name',
      );
      await backend.updatePayoutPrefs(
        method: CloudPayoutMethod.manual,
        number: '',
        name: '',
      );
      final saved = backend.users.values.first;
      expect(saved.payoutMethod, CloudPayoutMethod.manual);
      expect(saved.payoutNumber, '');
      expect(saved.payoutName, '');
    });

    test('prefs are visible to managers via listUsers', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await backend.signUp(
        email: 'driver@x.y',
        password: 'dummy123',
        username: 'DriverOne',
      );
      await backend.updatePayoutPrefs(
        method: CloudPayoutMethod.instapay,
        number: '01551234567',
        name: 'Wallet Name',
      );
      await backend.signUp(
        email: 'boss@x.y',
        password: 'dummy123',
        username: 'Boss',
      );
      final bossUid =
          backend.users.values.firstWhere((u) => u.email == 'boss@x.y').uid;
      backend.users[bossUid] = CloudAccount(
        uid: bossUid,
        email: 'boss@x.y',
        username: 'Boss',
        role: CloudRole.manager,
      );
      await backend.signOut();
      await backend.signIn(email: 'boss@x.y', password: 'dummy123');
      final users = await backend.listUsers();
      final driver =
          users.firstWhere((u) => u.email == 'driver@x.y');
      expect(driver.payoutMethod, CloudPayoutMethod.instapay);
      expect(driver.payoutNumber, '1551234567');
      expect(driver.payoutName, 'Wallet Name');
      expect(auth, isNotNull);
    });
  });

  group('payoutWeek computation', () {
    test('net = base + bonus adjustments − deduction adjustments; '
        'other-week adjustments ignored', () {
      final summaries = [
        buildDaySummary(
          uid: 'd1',
          dateKey: '2026-10-25',
          ordersCount: 5,
          totalKm: 40,
          orderPrice: 20,
          dailyFixedPay: 100,
          distanceBonus: 30,
          manualBonus: 20,
          flatBonus: 0,
          updatedAtMillis: 1000,
        ),
        buildDaySummary(
          uid: 'd1',
          dateKey: '2026-10-26',
          ordersCount: 3,
          totalKm: 20,
          orderPrice: 20,
          dailyFixedPay: 100,
          distanceBonus: 0,
          manualBonus: 0,
          flatBonus: 0,
          updatedAtMillis: 1000,
        ),
      ];
      // Day 1 total: 5*20 + 100 + 30 + 20 = 250.
      // Day 2 total: 3*20 + 100 = 160. Base = 410, dayBonus = 50.
      final adjustments = [
        const CloudAdjustment(
          id: 'a1',
          uid: 'd1',
          type: CloudAdjustmentType.bonus,
          amount: 200,
          reason: 'Good week',
          weekKey: '2026-10-25',
          createdBy: 'boss',
          createdAtMillis: 2000,
        ),
        const CloudAdjustment(
          id: 'a2',
          uid: 'd1',
          type: CloudAdjustmentType.deduction,
          amount: 100,
          reason: 'Late',
          weekKey: '2026-10-25',
          createdBy: 'boss',
          createdAtMillis: 3000,
        ),
        const CloudAdjustment(
          id: 'a3',
          uid: 'd1',
          type: CloudAdjustmentType.bonus,
          amount: 999,
          reason: 'Other week',
          weekKey: '2026-11-01',
          createdBy: 'boss',
          createdAtMillis: 4000,
        ),
      ];
      final week = payoutWeek(
        summaries: summaries,
        adjustments: adjustments,
        weekKey: '2026-10-25',
      );
      expect(week.base, 410);
      expect(week.dayBonus, 50);
      expect(week.bonus, 200);
      expect(week.deduction, 100);
      expect(week.net, 510);
      expect(week.totalBonus, 250);
    });

    test('driver with no summaries but a week bonus still has a net',
        () {
      final week = payoutWeek(
        summaries: const [],
        adjustments: const [
          CloudAdjustment(
            id: 'a1',
            uid: 'd1',
            type: CloudAdjustmentType.bonus,
            amount: 75,
            reason: 'Bonus only',
            weekKey: '2026-10-25',
            createdBy: 'boss',
            createdAtMillis: 2000,
          ),
        ],
        weekKey: '2026-10-25',
      );
      expect(week.net, 75);
      expect(week.totalBonus, 75);
    });
  });

  group('payout list + detail (widget)', () {
    Future<ProviderContainer> setupContainer(
      WidgetTester tester,
      FakeCloudBackend backend,
    ) async {
      final db = await tempDb(tester);
      final container = ProviderContainer(
        overrides: [
          cloudBackendProvider.overrideWithValue(backend),
          settingsProvider.overrideWith(
            (ref) => SettingsNotifier(db, NotificationService()),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    /// Seeds one week (Sun 2026-10-25 .. Sat 2026-10-31) for the
    /// given driver: two day summaries + one bonus + one deduction
    /// adjustment, both created on Monday 2026-10-26. Returns the
    /// expected net for that driver.
    Future<double> seedWeek(
      FakeCloudBackend backend,
      String bossUid,
      String driverUid,
    ) async {
      (backend.summaries[driverUid] ??= {})['2026-10-25'] =
          buildDaySummary(
        uid: driverUid,
        dateKey: '2026-10-25',
        ordersCount: 5,
        totalKm: 40,
        orderPrice: 20,
        dailyFixedPay: 100,
        distanceBonus: 30,
        manualBonus: 20,
        flatBonus: 0,
        updatedAtMillis: 1000,
      );
      (backend.summaries[driverUid] ??= {})['2026-10-26'] =
          buildDaySummary(
        uid: driverUid,
        dateKey: '2026-10-26',
        ordersCount: 3,
        totalKm: 20,
        orderPrice: 20,
        dailyFixedPay: 100,
        distanceBonus: 0,
        manualBonus: 0,
        flatBonus: 0,
        updatedAtMillis: 1000,
      );
      // Adjustments created Monday 2026-10-26 (local noon, so the
      // created-day mapping is stable under both test timezones).
      final mondayMillis =
          DateTime(2026, 10, 26, 12).millisecondsSinceEpoch;
      await backend.saveAdjustment(
        CloudAdjustment(
          id: '',
          uid: driverUid,
          type: CloudAdjustmentType.bonus,
          amount: 200,
          reason: 'Good week',
          weekKey: '2026-10-25',
          createdBy: bossUid,
          createdAtMillis: mondayMillis,
        ),
      );
      await backend.saveAdjustment(
        CloudAdjustment(
          id: '',
          uid: driverUid,
          type: CloudAdjustmentType.deduction,
          amount: 100,
          reason: 'Late delivery',
          weekKey: '2026-10-25',
          createdBy: bossUid,
          createdAtMillis: mondayMillis,
        ),
      );
      // Base 410 + bonus 200 − deduction 100 = 510.
      return 510;
    }

    testWidgets('payout rows: all methods + not-set + bonus/deduction '
        'lines + blocked excluded', (tester) async {
      final backend = FakeCloudBackend();
      final container = await setupContainer(tester, backend);
      final notifier = container.read(cloudAccountProvider.notifier);
      final bossUid = await setupManager(backend, notifier);
      final instaUid = await addDriver(
        backend,
        email: 'insta@x.y',
        username: 'InstaDriver',
      );
      final manualUid = await addDriver(
        backend,
        email: 'manual@x.y',
        username: 'ManualDriver',
      );
      final unsetUid = await addDriver(
        backend,
        email: 'unset@x.y',
        username: 'UnsetDriver',
      );
      final blockedUid = await addDriver(
        backend,
        email: 'blocked@x.y',
        username: 'BlockedDriver',
      );
      // Prefs: insta + manual set; unset + blocked left unset.
      await backend.signIn(email: 'insta@x.y', password: 'dummy123');
      await backend.updatePayoutPrefs(
        method: CloudPayoutMethod.instapay,
        number: '01551234567',
        name: 'Insta Wallet',
      );
      await backend.signIn(email: 'manual@x.y', password: 'dummy123');
      await backend.updatePayoutPrefs(
        method: CloudPayoutMethod.manual,
        number: '',
        name: '',
      );
      await backend.signIn(email: 'boss@x.y', password: 'dummy123');
      // Seed the CURRENT week (what ManagementScreen displays),
      // so the row amounts are deterministic on any run date.
      // Same numbers as seedWeek: base 410 + bonus 200 − 100 = 510.
      final currentWeek = WeekCalendar.weekDays(DateTime.now())
          .map(managementDateKey)
          .toList();
      final weekKey = currentWeek.first;
      (backend.summaries[instaUid] ??= {})[currentWeek[0]] =
          buildDaySummary(
        uid: instaUid,
        dateKey: currentWeek[0],
        ordersCount: 5,
        totalKm: 40,
        orderPrice: 20,
        dailyFixedPay: 100,
        distanceBonus: 30,
        manualBonus: 20,
        flatBonus: 0,
        updatedAtMillis: 1000,
      );
      (backend.summaries[instaUid] ??= {})[currentWeek[1]] =
          buildDaySummary(
        uid: instaUid,
        dateKey: currentWeek[1],
        ordersCount: 3,
        totalKm: 20,
        orderPrice: 20,
        dailyFixedPay: 100,
        distanceBonus: 0,
        manualBonus: 0,
        flatBonus: 0,
        updatedAtMillis: 1000,
      );
      await backend.saveAdjustment(
        CloudAdjustment(
          id: '',
          uid: instaUid,
          type: CloudAdjustmentType.bonus,
          amount: 200,
          reason: 'Good week',
          weekKey: weekKey,
          createdBy: bossUid,
          createdAtMillis: 2000,
        ),
      );
      await backend.saveAdjustment(
        CloudAdjustment(
          id: '',
          uid: instaUid,
          type: CloudAdjustmentType.deduction,
          amount: 100,
          reason: 'Late delivery',
          weekKey: weekKey,
          createdBy: bossUid,
          createdAtMillis: 3000,
        ),
      );
      await notifier.blockUser(blockedUid);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ManagementScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final instaRow =
          find.byKey(ValueKey('managementPayout-$instaUid'));
      expect(instaRow, findsOneWidget);
      expect(find.text('InstaPay'), findsWidgets);
      expect(find.text('1551234567'), findsOneWidget);
      expect(find.text('Insta Wallet'), findsOneWidget);
      // Net + visible bonus/deduction lines on the row itself
      // (totalBonus = dayBonus 50 + adjustment bonus 200 = 250).
      expect(
        find.descendant(of: instaRow, matching: find.text('510 EGP')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: instaRow,
          matching: find.text('+250 EGP bonus'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: instaRow,
          matching: find.text('−100 EGP deduction'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('managementPayout-$manualUid')),
        findsOneWidget,
      );
      expect(find.text('Manual'), findsWidgets);
      expect(
        find.byKey(ValueKey('managementPayout-$unsetUid')),
        findsOneWidget,
      );
      expect(find.text('Not set'), findsWidgets);
      expect(
        find.byKey(ValueKey('managementPayout-$blockedUid')),
        findsNothing,
      );
    });

    testWidgets('payout detail: day list, markers, adjustment lines, '
        'net matches row', (tester) async {
      final backend = FakeCloudBackend();
      final container = await setupContainer(tester, backend);
      final notifier = container.read(cloudAccountProvider.notifier);
      final bossUid = await setupManager(backend, notifier);
      final driverUid = await addDriver(
        backend,
        email: 'insta@x.y',
        username: 'InstaDriver',
      );
      await backend.signIn(email: 'insta@x.y', password: 'dummy123');
      await backend.updatePayoutPrefs(
        method: CloudPayoutMethod.instapay,
        number: '01551234567',
        name: 'Insta Wallet',
      );
      await backend.signIn(email: 'boss@x.y', password: 'dummy123');
      final expectedNet = await seedWeek(backend, bossUid, driverUid);
      // An adjustment for this week created OUTSIDE the week (late
      // entry next Sunday): counted in the net, listed separately.
      final nextSundayMillis =
          DateTime(2026, 11, 1, 12).millisecondsSinceEpoch;
      await backend.saveAdjustment(
        CloudAdjustment(
          id: '',
          uid: driverUid,
          type: CloudAdjustmentType.bonus,
          amount: 40,
          reason: 'Late entry',
          weekKey: '2026-10-25',
          createdBy: bossUid,
          createdAtMillis: nextSundayMillis,
        ),
      );
      final netWithLate = expectedNet + 40; // 550.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ManagementPayoutScreen(
              uid: driverUid,
              dateKey: '2026-10-26',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Header: name, method, number, wallet name, week label.
      expect(find.text('InstaDriver'), findsOneWidget);
      expect(find.text('Payout: InstaPay'), findsOneWidget);
      expect(find.text('1551234567'), findsOneWidget);
      expect(find.text('Insta Wallet'), findsOneWidget);
      expect(find.text('Week of 2026-10-25'), findsOneWidget);
      // Net matches the row computation (410 + 200 + 40 − 100).
      expect(
        find.byKey(const ValueKey('managementPayoutNet')),
        findsOneWidget,
      );
      expect(find.text('550 EGP'), findsWidgets);
      // All 7 day rows exist (Sun 2026-10-25 .. Sat 2026-10-31).
      final weekKeys = WeekCalendar.weekDays(DateTime(2026, 10, 26))
          .map(managementDateKey)
          .toList();
      expect(weekKeys.length, 7);
      for (final key in weekKeys) {
        expect(
          find.byKey(ValueKey('managementPayoutDay-$key')),
          findsOneWidget,
        );
      }
      // Sunday has a summary (250 EGP, day bonuses 50 → Bonus mark);
      // Monday has a summary (160 EGP) + both adjustments created
      // that day (bonus + deduction marks + reason lines).
      expect(find.text('250 EGP'), findsOneWidget);
      expect(find.text('160 EGP'), findsOneWidget);
      expect(find.text('Good week'), findsOneWidget);
      expect(find.text('Late delivery'), findsOneWidget);
      expect(find.text('+200 EGP'), findsOneWidget);
      expect(find.text('−100 EGP'), findsOneWidget);
      // Days without summaries show "No data".
      expect(find.text('No data'), findsWidgets);
      // Late-entry adjustment listed separately, still counted.
      expect(find.text('Other adjustments for this week'), findsOneWidget);
      expect(find.text('Late entry'), findsOneWidget);
      expect(find.text('+40 EGP'), findsOneWidget);
      expect(netWithLate, 550);
    });

    testWidgets('payout detail for a blocked driver shows blocked '
        'state', (tester) async {
      final backend = FakeCloudBackend();
      final container = await setupContainer(tester, backend);
      final notifier = container.read(cloudAccountProvider.notifier);
      await setupManager(backend, notifier);
      final driverUid = await addDriver(
        backend,
        email: 'driver@x.y',
        username: 'DriverOne',
      );
      await notifier.blockUser(driverUid);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ManagementPayoutScreen(
              uid: driverUid,
              dateKey: '2026-10-26',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('managementPayoutBlocked')),
        findsOneWidget,
      );
    });
  });

  group('driver payout form (widget)', () {
    testWidgets('saving InstaPay prefs stores them; Manual needs '
        'nothing; invalid input shows an error', (tester) async {
      final backend = FakeCloudBackend();
      final db = await tempDb(tester);
      final container = ProviderContainer(
        overrides: [
          cloudBackendProvider.overrideWithValue(backend),
          settingsProvider.overrideWith(
            (ref) => SettingsNotifier(db, NotificationService()),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(cloudAccountProvider.notifier);
      await notifier.signUp(
        email: 'driver@x.y',
        password: 'dummy123',
        username: 'DriverOne',
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CloudAccountScreen()),
        ),
      );
      await tester.pump();
      // The signed-in view shows the payout section.
      expect(
        find.byKey(const ValueKey('cloudPayoutSaveButton')),
        findsOneWidget,
      );
      // InstaPay without number/name → inline error, nothing saved.
      await tester.ensureVisible(
        find.byKey(const ValueKey('cloudPayoutMethod-instapay')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('cloudPayoutMethod-instapay')),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('cloudPayoutSaveButton')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('cloudPayoutSaveButton')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('cloudPayoutErrorText')),
        findsOneWidget,
      );
      expect(
        backend.users.values.first.payoutMethod,
        CloudPayoutMethod.none,
      );
      // Fill valid details → saved + snackbar.
      await tester.enterText(
        find.byKey(const ValueKey('cloudPayoutNumberField')),
        '01551234567',
      );
      await tester.enterText(
        find.byKey(const ValueKey('cloudPayoutNameField')),
        'Wallet Name',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('cloudPayoutSaveButton')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('cloudPayoutSaveButton')),
      );
      await tester.pump();
      expect(find.text('Payout preferences saved'), findsOneWidget);
      final saved = backend.users.values.first;
      expect(saved.payoutMethod, CloudPayoutMethod.instapay);
      expect(saved.payoutNumber, '1551234567');
      expect(saved.payoutName, 'Wallet Name');
      // Switch to Manual → saved without details.
      await tester.ensureVisible(
        find.byKey(const ValueKey('cloudPayoutMethod-manual')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('cloudPayoutMethod-manual')),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('cloudPayoutSaveButton')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('cloudPayoutSaveButton')),
      );
      await tester.pump();
      final manual = backend.users.values.first;
      expect(manual.payoutMethod, CloudPayoutMethod.manual);
      expect(manual.payoutNumber, '');
    });
  });
}
