// v27.35 — Blacklist (reversible block, NOT a deletion).
//
// Supersedes the destructive-wipe brief: blocking a driver sets
// blocked/blockedAt/blockedBy on his profile and deletes NOTHING —
// orders, summaries, adjustments, rollups and login lookups are all
// kept, so unblocking restores him fully.
//
// Covered here: block/unblock guards, the sign-in gates (email,
// Google, Google sign-up, restore), the changeUsername
// permission-denied fix (console-created account without mappings +
// own-orphan retry tolerance), dashboard hiding (team list, KPIs,
// payouts), the swipe-to-block UX (never blocks on swipe alone),
// the Blacklist section + unblock, and the driver detail's
// phone/email display + blocked state.
//
// All values here are DUMMY. No real code, password, or secret
// appears in this file.

import 'dart:io';

import 'package:deliveryflow/core/cloud/cloud_providers.dart';
import 'package:deliveryflow/core/cloud/cloud_services.dart';
import 'package:deliveryflow/core/cloud/cloud_types.dart';
import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/cloud/management_dashboard_logic.dart';
import 'package:deliveryflow/features/cloud/management_driver_screen.dart';
import 'package:deliveryflow/features/cloud/management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'v27_33_test.dart' show FakeCloudBackend;

void main() {
  Future<DatabaseService> tempDb(WidgetTester tester) async {
    late Directory tmp;
    late DatabaseService db;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('df_v2735_block_');
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
    });
    addTearDown(() => tester.runAsync(() async {
          await Hive.close();
          await tmp.delete(recursive: true);
        }));
    return db;
  }

  /// Signs up a manager (boss) + one driver, both through the fake
  /// backend, and leaves the session signed in as the manager.
  /// Returns (backend, bossUid, driverUid).
  Future<(FakeCloudBackend, String, String)> setupTeam(
    FakeCloudBackend backend,
    CloudAccountNotifier notifier,
  ) async {
    await notifier.signUp(
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
    await notifier.signOut();
    await notifier.signIn(email: 'boss@x.y', password: 'dummy123');
    final driver = await backend.signUp(
      email: 'driver@x.y',
      password: 'dummy123',
      username: 'DriverOne',
      phone: '01551234567',
    );
    await backend.signOut();
    await backend.signIn(email: 'boss@x.y', password: 'dummy123');
    return (backend, bossUid, driver.uid);
  }

  group('block/unblock guards (backend)', () {
    test('manager blocks a driver; data and lookups are all kept',
        () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await backend.signUp(
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
      await backend.signOut();
      await backend.signIn(email: 'boss@x.y', password: 'dummy123');
      final driver = await backend.signUp(
        email: 'driver@x.y',
        password: 'dummy123',
        username: 'DriverOne',
        phone: '01551234567',
      );
      await backend.signOut();
      await backend.signIn(email: 'boss@x.y', password: 'dummy123');
      // Seed work data + mappings that a wipe would have destroyed.
      (backend.summaries[driver.uid] ??= {})['2026-10-29'] =
          buildDaySummary(
        uid: driver.uid,
        dateKey: '2026-10-29',
        ordersCount: 5,
        totalKm: 40,
        orderPrice: 20,
        dailyFixedPay: 100,
        distanceBonus: 0,
        manualBonus: 0,
        flatBonus: 0,
        updatedAtMillis: 1000,
      );
      (backend.orders[driver.uid] ??= {})['2026-10-29'] = {'orders': 5};
      await backend.saveAdjustment(
        CloudAdjustment(
          id: '',
          uid: driver.uid,
          type: CloudAdjustmentType.bonus,
          amount: 50,
          reason: 'Good week',
          weekKey: '2026-10-25',
          createdBy: bossUid,
          createdAtMillis: 2000,
        ),
      );
      expect(backend.usernameLookups.containsKey('driverone'), isTrue);

      await auth.blockUser(driver.uid);
      final blocked = backend.users[driver.uid]!;
      expect(blocked.blocked, isTrue);
      expect(blocked.blockedBy, bossUid);
      expect(blocked.blockedAt, greaterThan(0));
      // Nothing was deleted.
      expect(backend.summaries[driver.uid], isNotEmpty);
      expect(backend.orders[driver.uid], isNotEmpty);
      expect(backend.adjustments[driver.uid], isNotEmpty);
      expect(backend.usernameLookups.containsKey('driverone'), isTrue);
      expect(backend.phoneLookups.isNotEmpty, isTrue);
      expect(
        backend.emailUsernameLookups.isNotEmpty,
        isTrue,
      );
    });

    test('guards: driver caller, self, manager target, unknown, '
        'already blocked, unblock of live account', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await backend.signUp(
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
      await backend.signOut();
      await backend.signIn(email: 'boss@x.y', password: 'dummy123');
      final driver = await backend.signUp(
        email: 'driver@x.y',
        password: 'dummy123',
        username: 'DriverOne',
      );
      final other = await backend.signUp(
        email: 'other@x.y',
        password: 'dummy123',
        username: 'Other',
      );
      backend.users[other.uid] = CloudAccount(
        uid: other.uid,
        email: 'other@x.y',
        username: 'Other',
        role: CloudRole.manager,
      );
      await backend.signOut();
      // Driver caller cannot block anyone.
      await backend.signIn(email: 'driver@x.y', password: 'dummy123');
      await expectLater(
        () => auth.blockUser(driver.uid),
        throwsA(isA<CloudDenied>()),
      );
      await backend.signOut();
      await backend.signIn(email: 'boss@x.y', password: 'dummy123');
      // Self, manager target, unknown uid.
      await expectLater(
        () => auth.blockUser(bossUid),
        throwsA(isA<CloudDenied>()),
      );
      await expectLater(
        () => auth.blockUser(other.uid),
        throwsA(isA<CloudDenied>()),
      );
      await expectLater(
        () => auth.blockUser('no_such_uid'),
        throwsA(isA<CloudDenied>()),
      );
      // Unblock of a live account is refused.
      await expectLater(
        () => auth.unblockUser(driver.uid),
        throwsA(isA<CloudDenied>()),
      );
      // Block then re-block refused; unblock clears; data intact.
      await auth.blockUser(driver.uid);
      await expectLater(
        () => auth.blockUser(driver.uid),
        throwsA(isA<CloudDenied>()),
      );
      await auth.unblockUser(driver.uid);
      final restored = backend.users[driver.uid]!;
      expect(restored.blocked, isFalse);
      expect(restored.blockedAt, 0);
      expect(restored.blockedBy, '');
      expect(restored.username, 'DriverOne');
    });

    test('saveProfile cannot overwrite a blocked profile', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await backend.signUp(
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
      await backend.signOut();
      await backend.signIn(email: 'boss@x.y', password: 'dummy123');
      final driver = await backend.signUp(
        email: 'driver@x.y',
        password: 'dummy123',
        username: 'DriverOne',
      );
      await backend.signOut();
      await backend.signIn(email: 'boss@x.y', password: 'dummy123');
      await auth.blockUser(driver.uid);
      await expectLater(
        () => backend.saveProfile(
          CloudAccount(
            uid: driver.uid,
            email: 'driver@x.y',
            username: 'DriverOne',
            role: CloudRole.driver,
          ),
        ),
        throwsA(isA<CloudDenied>()),
      );
      expect(backend.users[driver.uid]!.blocked, isTrue);
    });
  });

  group('sign-in gates', () {
    test('blocked driver cannot sign in (email/password); session '
        'cleared', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await backend.signUp(
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
      await backend.signOut();
      await backend.signIn(email: 'boss@x.y', password: 'dummy123');
      await backend.signUp(
        email: 'driver@x.y',
        password: 'dummy123',
        username: 'DriverOne',
      );
      await backend.signOut();
      await backend.signIn(email: 'boss@x.y', password: 'dummy123');
      final driverUid =
          backend.users.values.firstWhere((u) => u.email == 'driver@x.y').uid;
      await auth.blockUser(driverUid);
      await backend.signOut();
      await expectLater(
        () => backend.signIn(email: 'driver@x.y', password: 'dummy123'),
        throwsA(
          predicate(
            (e) =>
                e is CloudAccountBlocked &&
                e.toString() == 'This account has been blocked.',
          ),
        ),
      );
      // No session survived the gate.
      expect(await backend.restoreSession(), isNull);
    });

    test('blocked Google user is gated on sign-in, sign-up begin, '
        'and completion', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      // First Google sign-in creates the fake Google driver.
      final google = (await backend.signInWithGoogle())!;
      expect(google.uid, 'google_uid');
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
      await auth.blockUser('google_uid');
      await backend.signOut();
      await expectLater(
        () => backend.signInWithGoogle(),
        throwsA(isA<CloudAccountBlocked>()),
      );
      await expectLater(
        () => backend.beginGoogleSignUp(),
        throwsA(isA<CloudAccountBlocked>()),
      );
      // Unblocking restores Google sign-in too: begin now returns
      // the existing account instead of gating.
      await backend.signIn(email: 'boss@x.y', password: 'dummy123');
      await auth.unblockUser('google_uid');
      await backend.signOut();
      final start = await backend.beginGoogleSignUp();
      expect(start.account?.uid, 'google_uid');
    });

    test('completeGoogleSignUp gate: a blocked profile appearing '
        'after begin is gated', () async {
      final backend = FakeCloudBackend();
      final start = await backend.beginGoogleSignUp();
      expect(start.account, isNull); // Needs completion.
      // The profile appears (e.g. created on another device) and is
      // blocked before the user completes the form.
      backend.users['google_uid'] = const CloudAccount(
        uid: 'google_uid',
        email: 'google.driver@example.com',
        username: 'Google Driver',
        blocked: true,
        blockedAt: 1,
        blockedBy: 'boss_uid',
      );
      await expectLater(
        () => backend.completeGoogleSignUp(
          username: 'NewName',
          phone: '01551234567',
        ),
        throwsA(isA<CloudAccountBlocked>()),
      );
    });

    test('restoreSession gate: a session live when the block lands '
        'is signed out on restore', () async {
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'driver@x.y',
        password: 'dummy123',
        username: 'DriverOne',
      );
      final driverUid = backend.users.values.first.uid;
      // Block lands while the session is live (direct doc edit
      // mirrors a manager blocking from another device).
      backend.users[driverUid] = CloudAccount(
        uid: driverUid,
        email: 'driver@x.y',
        username: 'DriverOne',
        blocked: true,
        blockedAt: 123456,
        blockedBy: 'boss_uid',
      );
      await expectLater(
        () => backend.restoreSession(),
        throwsA(isA<CloudAccountBlocked>()),
      );
      expect(await backend.restoreSession(), isNull);
    });
  });

  group('changeUsername permission-denied fix', () {
    test('console-created account without mappings can change '
        'username', () async {
      final backend = FakeCloudBackend();
      final driver = await backend.signUp(
        email: 'driver@x.y',
        password: 'dummy123',
        username: 'OldName',
      );
      // Simulate the console-created state: profile exists, but the
      // username mapping was never created.
      backend.usernameLookups.remove('oldname');
      backend.emailUsernameLookups.clear();
      await backend.signOut();
      await backend.signIn(email: 'driver@x.y', password: 'dummy123');
      final updated = await backend.changeUsername('NewName');
      expect(updated.username, 'NewName');
      expect(backend.usernameLookups['newname'], 'driver@x.y');
      expect(
        backend.users[driver.uid]!.username,
        'NewName',
      );
    });

    test('retry after a partial failure succeeds (own orphaned '
        'mapping is not "taken")', () async {
      final backend = FakeCloudBackend();
      final driver = await backend.signUp(
        email: 'driver@x.y',
        password: 'dummy123',
        username: 'OldName',
      );
      // Partial-failure state: the new mapping was created, then the
      // old delete failed — the new mapping points at the caller.
      backend.usernameLookups['newname'] = 'driver@x.y';
      await backend.signOut();
      await backend.signIn(email: 'driver@x.y', password: 'dummy123');
      final updated = await backend.changeUsername('NewName');
      expect(updated.username, 'NewName');
      expect(backend.usernameLookups['newname'], 'driver@x.y');
      expect(backend.usernameLookups.containsKey('oldname'), isFalse);
      expect(
        backend.users[driver.uid]!.username,
        'NewName',
      );
    });

    test('a genuinely taken username is still rejected', () async {
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'taken@x.y',
        password: 'dummy123',
        username: 'TakenName',
      );
      await backend.signOut();
      await backend.signUp(
        email: 'driver@x.y',
        password: 'dummy123',
        username: 'OldName',
      );
      await expectLater(
        () => backend.changeUsername('TakenName'),
        throwsA(
          predicate(
            (e) => e is Exception && e.toString().contains('taken'),
          ),
        ),
      );
    });
  });

  group('dashboard hiding + swipe block + blacklist (widget)', () {
    Future<ProviderContainer> setupWidgetTeam(
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

    testWidgets('blocked driver hidden from team/KPIs/payouts, '
        'shown once in Blacklist', (tester) async {
      final backend = FakeCloudBackend();
      final container = await setupWidgetTeam(tester, backend);
      final notifier = container.read(cloudAccountProvider.notifier);
      final (_, bossUid, blockedUid) =
          await setupTeam(backend, notifier);
      // A second live driver (unsynced) + a synced blocked driver.
      final live = await backend.signUp(
        email: 'live@x.y',
        password: 'dummy123',
        username: 'LiveOne',
      );
      await backend.signOut();
      await backend.signIn(email: 'boss@x.y', password: 'dummy123');
      final today = managementDateKey(DateTime.now());
      (backend.summaries[bossUid] ??= {})[today] = buildDaySummary(
        uid: bossUid,
        dateKey: today,
        ordersCount: 6,
        totalKm: 30,
        orderPrice: 20,
        dailyFixedPay: 100,
        distanceBonus: 10,
        manualBonus: 0,
        flatBonus: 0,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      (backend.summaries[blockedUid] ??= {})[today] = buildDaySummary(
        uid: blockedUid,
        dateKey: today,
        ordersCount: 4,
        totalKm: 20,
        orderPrice: 20,
        dailyFixedPay: 100,
        distanceBonus: 0,
        manualBonus: 0,
        flatBonus: 0,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await container
          .read(cloudAccountProvider.notifier)
          .blockUser(blockedUid);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ManagementScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Team card gone, blacklist card present, payout row gone.
      expect(
        find.byKey(ValueKey('managementUser-$blockedUid')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('managementBlocked-$blockedUid')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('managementPayout-$blockedUid')),
        findsNothing,
      );
      // Live driver still in the team list.
      expect(
        find.byKey(ValueKey('managementUser-${live.uid}')),
        findsOneWidget,
      );
      // KPIs count visible team only: 1 synced (boss) / 2 users.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('managementKpiDrivers')),
          matching: find.text('1 / 2'),
        ),
        findsOneWidget,
      );
      expect(find.text('Blacklist'), findsOneWidget);
    });

    testWidgets('swipe reveals Block; cancel keeps driver, confirm '
        'blocks', (tester) async {
      final backend = FakeCloudBackend();
      final container = await setupWidgetTeam(tester, backend);
      final notifier = container.read(cloudAccountProvider.notifier);
      final (_, _, driverUid) = await setupTeam(backend, notifier);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ManagementScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final card = find.byKey(ValueKey('managementUser-$driverUid'));
      expect(card, findsOneWidget);
      // The card sits below the fold in the scrollable dashboard —
      // bring it into view before dragging.
      await tester.ensureVisible(card);
      await tester.pump();
      // Swipe alone blocks NOTHING.
      await tester.drag(card, const Offset(-300, 0));
      await tester.pump();
      expect(backend.users[driverUid]!.blocked, isFalse);
      final action =
          find.byKey(ValueKey('managementBlockUserAction-$driverUid'));
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pump();
      expect(find.text('Block driver?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(backend.users[driverUid]!.blocked, isFalse);
      expect(card, findsOneWidget);
      // Swipe again, confirm through the bin button. The dialog's
      // entrance transition must settle before tapping the bin
      // button, and the 1400ms bin animation needs stepped pumps
      // (a single long pump does not drive it to completion).
      await tester.ensureVisible(card);
      await tester.pump();
      await tester.drag(card, const Offset(-300, 0));
      await tester.pump();
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('managementBlockUserConfirm')),
      );
      for (var i = 0;
          i < 30 && find.text('Block driver?').evaluate().isNotEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump();
      await tester.pump();
      expect(backend.users[driverUid]!.blocked, isTrue);
      expect(find.text('Driver blocked'), findsOneWidget);
      expect(
        find.byKey(ValueKey('managementBlocked-$driverUid')),
        findsOneWidget,
      );
    });

    testWidgets('driver sees denied state and no block action',
        (tester) async {
      final backend = FakeCloudBackend();
      final container = await setupWidgetTeam(tester, backend);
      final notifier = container.read(cloudAccountProvider.notifier);
      await setupTeam(backend, notifier);
      await notifier.signOut();
      await notifier.signIn(email: 'driver@x.y', password: 'dummy123');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ManagementScreen()),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Access denied'), findsOneWidget);
      expect(find.byType(SlidableAction), findsNothing);
    });

    testWidgets('unblock from Blacklist restores the driver',
        (tester) async {
      final backend = FakeCloudBackend();
      final container = await setupWidgetTeam(tester, backend);
      final notifier = container.read(cloudAccountProvider.notifier);
      final (_, _, driverUid) = await setupTeam(backend, notifier);
      await notifier.blockUser(driverUid);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ManagementScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(ValueKey('managementBlocked-$driverUid')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(ValueKey('managementUnblock-$driverUid')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('managementUnblock-$driverUid')),
      );
      await tester.pump();
      expect(find.text('Unblock driver?'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('managementUnblockUserConfirm')),
      );
      await tester.pump();
      await tester.pump();
      expect(backend.users[driverUid]!.blocked, isFalse);
      expect(
        find.byKey(ValueKey('managementUser-$driverUid')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('managementBlocked-$driverUid')),
        findsNothing,
      );
    });
  });

  group('driver detail phone/email + blocked state (widget)', () {
    testWidgets('detail shows phone + email; missing phone renders '
        'nothing', (tester) async {
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
      final (_, _, driverUid) = await setupTeam(backend, notifier);
      final today = managementDateKey(DateTime.now());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ManagementDriverScreen(uid: driverUid, dateKey: today),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // DriverOne's phone was normalized at sign-up; email as-is.
      expect(find.text('1551234567'), findsOneWidget);
      expect(find.text('driver@x.y'), findsOneWidget);
      expect(find.text('null'), findsNothing);
    });

    testWidgets('detail for a blocked driver shows blocked state '
        'only', (tester) async {
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
      final (_, _, driverUid) = await setupTeam(backend, notifier);
      await notifier.blockUser(driverUid);
      final today = managementDateKey(DateTime.now());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ManagementDriverScreen(uid: driverUid, dateKey: today),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('managementDriverBlocked')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('managementDriverEditDay')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('managementDriverBlock')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('managementDriverUnblock')),
        findsOneWidget,
      );
    });
  });
}
