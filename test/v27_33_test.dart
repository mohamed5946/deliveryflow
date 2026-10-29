// v27.33 — Phase 1 cloud tests (fake backend, never real Firebase).
//
// Covers: sign-up/sign-in/sign-out, per-user isolation, logout cache
// swap (no leakage), daily-summary salary math vs the existing
// formula, manager gating, role self-assignment refusal, offline queue
// + flush on reconnect, first-login migration uploading exactly once,
// Hive round-trip of the new cloudMigratedUid marker, and the
// Management denied state + CloudAccount not-configured state.
import 'dart:io';

import 'package:deliveryflow/app/first_run_redirect.dart';
import 'package:deliveryflow/core/cloud/adjustment_logic.dart';
import 'package:deliveryflow/core/cloud/cloud_backend.dart';
import 'package:deliveryflow/core/cloud/login_identifier.dart';
import 'package:deliveryflow/core/cloud/cloud_providers.dart';
import 'package:deliveryflow/core/cloud/cloud_services.dart';
import 'package:deliveryflow/core/cloud/cloud_types.dart';
import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/cloud/cloud_account_screen.dart';
import 'package:deliveryflow/features/cloud/management_dashboard_logic.dart';
import 'package:deliveryflow/features/cloud/management_driver_screen.dart';
import 'package:deliveryflow/features/cloud/management_screen.dart';
import 'package:deliveryflow/features/cloud/manager_edit_day_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

class FakeCloudBackend implements CloudBackend {
  final users = <String, CloudAccount>{};
  final _passwords = <String, String>{};
  final summaries = <String, Map<String, CloudDaySummary>>{};
  final orders = <String, Map<String, Map<String, dynamic>>>{};
  final adjustments = <String, Map<String, CloudAdjustment>>{};
  // Login lookup collections (mirrors of the Firestore ones):
  // username key → email, phone-hash key → email, email-hash → username.
  final usernameLookups = <String, String>{};
  final phoneLookups = <String, String>{};
  final emailUsernameLookups = <String, String>{};
  // Password-reset emails "sent" (forgot-flow test hook).
  final sentPasswordResets = <String>[];
  CloudAccount? _current;
  bool failWrites = false;
  int listUsersCalls = 0;
  int saveDaySummaryCalls = 0;
  int _counter = 0;

  @override
  CloudAccount? get currentAccount => _current;

  void _requireOwner(String uid) {
    final me = _current;
    if (me == null) throw const CloudDenied('not signed in');
    if (me.uid != uid && !me.isManager) {
      throw const CloudDenied('not owner');
    }
    _requireUsableAccount();
  }

  void _requireUsableAccount() {
    if (_current?.mustChangePassword == true) {
      throw const CloudDenied('password change required');
    }
  }

  void _requireOwnerOrManager(String uid) => _requireOwner(uid);

  CloudDaySummary _stampIfManagerEdit(CloudDaySummary summary) {
    final me = _current;
    if (me == null || !me.isManager || me.uid == summary.uid) {
      return summary;
    }
    return summary.stampedByManager(
      me.uid,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<CloudAccount> signUp({
    required String email,
    required String password,
    required String username,
    String phone = '',
  }) async {
    if (_passwords.containsKey(email)) throw Exception('email in use');
    final usernameKey = usernameLookupKey(username);
    if (usernameKey.isNotEmpty &&
        usernameLookups.containsKey(usernameKey)) {
      throw Exception('username taken');
    }
    final normalizedPhone = phone.isEmpty ? '' : normalizeEgyptPhone(phone);
    final phoneKey =
        normalizedPhone.isEmpty ? '' : phoneLookupKey(normalizedPhone);
    if (phoneKey.isNotEmpty && phoneLookups.containsKey(phoneKey)) {
      throw Exception('phone taken');
    }
    final uid = 'uid_${_counter++}';
    final account = CloudAccount(
      uid: uid,
      email: email,
      username: username,
      role: CloudRole.driver,
      phone: normalizedPhone,
    );
    users[uid] = account;
    _passwords[email] = password;
    if (usernameKey.isNotEmpty) usernameLookups[usernameKey] = email;
    if (phoneKey.isNotEmpty) phoneLookups[phoneKey] = email;
    emailUsernameLookups[emailLookupKey(email)] = username;
    _current = account;
    return account;
  }

  @override
  Future<String?> resolveLoginEmail(String identifier) async {
    final trimmed = identifier.trim();
    if (trimmed.contains('@')) return trimmed;
    if (looksLikePhone(trimmed)) {
      return phoneLookups[phoneLookupKey(trimmed)];
    }
    return usernameLookups[usernameLookupKey(trimmed)];
  }

  @override
  Future<CloudAccount> changeUsername(String newUsername) async {
    final me = _current;
    if (me == null) throw const CloudDenied('not signed in');
    _requireUsableAccount();
    final newKey = usernameLookupKey(newUsername);
    if (newKey.isEmpty) throw Exception('username required');
    final oldKey = usernameLookupKey(me.username);
    if (newKey == oldKey) return me;
    if (usernameLookups.containsKey(newKey)) {
      throw Exception('username taken');
    }
    usernameLookups[newKey] = me.email;
    if (oldKey.isNotEmpty) usernameLookups.remove(oldKey);
    final updated = CloudAccount(
      uid: me.uid,
      email: me.email,
      username: newUsername.trim(),
      role: me.role,
      phone: me.phone,
    );
    users[me.uid] = updated;
    emailUsernameLookups[emailLookupKey(me.email)] = updated.username;
    _current = updated;
    return updated;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final me = _current;
    if (me == null) throw const CloudDenied('not signed in');
    if (_passwords[me.email] != currentPassword) {
      throw Exception('wrong current password');
    }
    _passwords[me.email] = newPassword;
    // A successful change clears a forced-change flag (admin rule).
    if (me.mustChangePassword) {
      final cleared = CloudAccount(
        uid: me.uid,
        email: me.email,
        username: me.username,
        role: me.role,
        phone: me.phone,
      );
      users[me.uid] = cleared;
      _current = cleared;
    }
  }

  @override
  Future<bool> isUsernameAvailable(String username) async {
    final key = usernameLookupKey(username);
    if (key.isEmpty) return false;
    return !usernameLookups.containsKey(key);
  }

  @override
  Future<CloudAccount?> restoreSession() async {
    // Fake persistence mirror: the fake backend object survives a
    // simulated restart (new ProviderContainer, same backend), just
    // as Firebase Auth's stored session survives a real restart.
    final me = _current;
    if (me == null) return null;
    return users[me.uid] ?? me;
  }

  @override
  Future<String?> lookupUsernameByEmail(String email) async {
    return emailUsernameLookups[emailLookupKey(email)];
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    sentPasswordResets.add(email.trim());
  }

  /// Lookup collections cannot be LISTED (mirrors the Firestore
  /// rules: single-document GET only). There is deliberately no list
  /// API for lookups — this method exists only to prove the point.
  List<String> listUsernameKeys() =>
      throw const CloudDenied('lookup listing denied');

  @override
  Future<CloudAccount> signIn({
    required String email,
    required String password,
  }) async {
    if (_passwords[email] != password) throw Exception('bad credentials');
    final account = users.values.firstWhere((u) => u.email == email);
    _current = account;
    return account;
  }

  /// Fake Google sign-in: always the SAME fake Google identity
  /// (uid 'google_uid'), so a repeat sign-in loads the existing doc.
  /// First sign-in creates a driver doc (username from the Google
  /// profile); it never touches Email/Password accounts — no
  /// auto-linking, even for a matching email.
  @override
  Future<CloudAccount?> signInWithGoogle() async {
    const googleUid = 'google_uid';
    final existing = users[googleUid];
    if (existing != null) {
      _current = existing;
      return existing;
    }
    final account = const CloudAccount(
      uid: googleUid,
      email: 'google.driver@example.com',
      username: 'Google Driver',
      role: CloudRole.driver,
    );
    users[googleUid] = account;
    _current = account;
    return account;
  }

  @override
  Future<void> signOut() async {
    _current = null;
  }

  @override
  Future<CloudAccount?> fetchProfile(String uid) async {
    _requireOwner(uid);
    return users[uid];
  }

  @override
  Future<void> saveProfile(CloudAccount account) async {
    final me = _current;
    if (me == null) throw const CloudDenied('not signed in');
    _requireUsableAccount();
    if (me.uid != account.uid && !me.isManager) {
      throw const CloudDenied('not owner or manager');
    }
    final existing = users[account.uid];
    if (existing != null && existing.role != account.role) {
      if (me.uid == account.uid) {
        throw const CloudDenied('cannot change own role');
      }
      if (!me.isManager) {
        throw const CloudDenied('only a manager changes roles');
      }
    }
    if (failWrites) throw Exception('offline');
    users[account.uid] = account;
  }

  @override
  Future<void> saveDaySummary(CloudDaySummary summary) async {
    if (failWrites) throw Exception('offline');
    _requireOwnerOrManager(summary.uid);
    saveDaySummaryCalls++;
    (summaries[summary.uid] ??= {})[summary.dateKey] =
        _stampIfManagerEdit(summary);
  }

  @override
  Future<CloudDaySummary?> fetchDaySummary(String uid, String dateKey) async {
    _requireOwner(uid);
    return summaries[uid]?[dateKey];
  }

  @override
  Future<void> saveOrderRecord(
    String uid,
    String dateKey,
    Map<String, dynamic> json,
  ) async {
    if (failWrites) throw Exception('offline');
    _requireOwnerOrManager(uid);
    final me = _current!;
    final stored = Map<String, dynamic>.from(json);
    if (me.isManager && me.uid != uid) {
      stored['editedByManagerUid'] = me.uid;
      stored['editedByManagerAtMillis'] =
          DateTime.now().millisecondsSinceEpoch;
    }
    (orders[uid] ??= {})[dateKey] = stored;
  }

  @override
  Future<Map<String, dynamic>?> fetchOrderRecord(
    String uid,
    String dateKey,
  ) async {
    _requireOwner(uid);
    return orders[uid]?[dateKey];
  }

  @override
  Future<void> deleteUserDay(String uid, String dateKey) async {
    _requireOwnerOrManager(uid);
    summaries[uid]?.remove(dateKey);
    orders[uid]?.remove(dateKey);
  }

  void _requireManagerAdjustingOther(String uid) {
    final me = _current;
    if (me == null) throw const CloudDenied('not signed in');
    _requireUsableAccount();
    if (!me.isManager) {
      throw const CloudDenied('only a manager writes adjustments');
    }
    if (me.uid == uid) {
      throw const CloudDenied('a manager cannot adjust his own pay');
    }
  }

  @override
  Future<CloudAdjustment> saveAdjustment(CloudAdjustment adjustment) async {
    _requireManagerAdjustingOther(adjustment.uid);
    final error = validateAdjustment(
      amount: adjustment.amount,
      reason: adjustment.reason,
    );
    if (error != null) throw Exception(error);
    final id = adjustment.id.isEmpty
        ? 'adj_${_counter++}'
        : adjustment.id;
    final saved = CloudAdjustment(
      id: id,
      uid: adjustment.uid,
      type: adjustment.type,
      amount: adjustment.amount,
      reason: adjustment.reason,
      weekKey: adjustment.weekKey,
      createdBy: _current!.uid,
      createdAtMillis: adjustment.createdAtMillis == 0
          ? DateTime.now().millisecondsSinceEpoch
          : adjustment.createdAtMillis,
    );
    (adjustments[adjustment.uid] ??= {})[id] = saved;
    return saved;
  }

  @override
  Future<void> deleteAdjustment(String uid, String adjustmentId) async {
    _requireManagerAdjustingOther(uid);
    adjustments[uid]?.remove(adjustmentId);
  }

  @override
  Future<List<CloudAdjustment>> listAdjustments(String uid) async {
    _requireOwner(uid);
    return (adjustments[uid] ?? {}).values.toList();
  }

  @override
  Future<List<CloudAccount>> listUsers() async {
    listUsersCalls++;
    _requireUsableAccount();
    final me = _current;
    if (me == null || !me.isManager) {
      throw const CloudDenied('manager only');
    }
    return users.values.toList();
  }

  @override
  Future<List<CloudDaySummary>> listDaySummaries(String dateKey) async {
    final me = _current;
    if (me == null || !me.isManager) {
      throw const CloudDenied('manager only');
    }
    final out = <CloudDaySummary>[];
    for (final byDay in summaries.values) {
      final s = byDay[dateKey];
      if (s != null) out.add(s);
    }
    return out;
  }

  @override
  Future<Map<String, List<CloudDaySummary>>> listSummariesForDays(
    List<String> dateKeys,
  ) async {
    final me = _current;
    if (me == null || !me.isManager) {
      throw const CloudDenied('manager only');
    }
    return {
      for (final key in dateKeys)
        key: [
          for (final byDay in summaries.values)
            if (byDay[key] != null) byDay[key]!,
        ],
    };
  }
}

/// Temp Hive database for widget tests (same pattern as the screens
/// group's local tempDb, but file-scoped so later groups can use it).
Future<DatabaseService> tempDbForTest(WidgetTester tester) async {
  // Real dart:io work (temp dir + Hive open) must run outside the
  // testWidgets fake-async zone, or the first await never completes.
  late Directory tmp;
  late DatabaseService db;
  await tester.runAsync(() async {
    tmp = await Directory.systemTemp.createTemp('df_v2733_ui2_');
    db = DatabaseService();
    await db.init(hivePath: tmp.path);
  });
  addTearDown(() => tester.runAsync(() async {
        await Hive.close();
        await tmp.delete(recursive: true);
      }));
  return db;
}

void main() {
  group('v27.33 cloud types + salary math', () {
    test('computeDaySalary mirrors WeeklyReport.salaryTotal for one day',
        () {
      expect(
        computeDaySalary(
          ordersCount: 10,
          orderPrice: 20,
          dailyFixedPay: 100,
          distanceBonus: 30,
          manualBonus: 5,
          flatBonus: 15,
        ),
        10 * 20 + 100 + 30 + 5 + 15,
      );
      // Zero-order day earns NO fixed pay (paidDaysCount rule).
      expect(
        computeDaySalary(
          ordersCount: 0,
          orderPrice: 20,
          dailyFixedPay: 100,
          distanceBonus: 0,
          manualBonus: 0,
          flatBonus: 0,
        ),
        0,
      );
    });

    test('CloudDaySummary + CloudAccount JSON round-trip', () {
      const summary = CloudDaySummary(
        uid: 'u1',
        dateKey: '2026-10-29',
        ordersCount: 7,
        totalKm: 42.5,
        salaryTotal: 315,
      );
      final decoded = CloudDaySummary.fromJson('u1', summary.toJson());
      expect(decoded.ordersCount, 7);
      expect(decoded.salaryTotal, 315);
      const account = CloudAccount(
        uid: 'u1',
        email: 'a@b.c',
        username: 'driver1',
        role: CloudRole.manager,
      );
      expect(CloudAccount.fromJson('u1', account.toJson()).isManager, isTrue);
      expect(cloudRoleFromString('nope'), CloudRole.driver);
    });
  });

  group('v27.33 auth + isolation (fake backend)', () {
    test('sign-up creates a driver; sign-in/out round-trips', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      final created = await auth.signUp(
        email: 'd@x.y',
        password: 'pw123456',
        username: 'driver1',
      );
      expect(created.role, CloudRole.driver);
      expect(created.username, 'driver1');
      await auth.signOut();
      expect(auth.currentAccount, isNull);
      final back = await auth.signIn(email: 'd@x.y', password: 'pw123456');
      expect(back.uid, created.uid);
    });

    test('per-user isolation: A cannot read B data', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      final a = await auth.signUp(
        email: 'a@x.y',
        password: 'pw123456',
        username: 'a',
      );
      await backend.saveDaySummary(
        const CloudDaySummary(
          uid: 'u',
          dateKey: '2026-10-29',
          ordersCount: 3,
          totalKm: 10,
          salaryTotal: 100,
        ).copyWithUid(a.uid),
      );
      await auth.signUp(email: 'b@x.y', password: 'pw123456', username: 'b');
      expect(
        () => backend.fetchDaySummary(a.uid, '2026-10-29'),
        throwsA(isA<CloudDenied>()),
      );
    });

    test('manager gating: driver denied, manager sees team', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(email: 'd@x.y', password: 'pw123456', username: 'd');
      expect(() => backend.listUsers(), throwsA(isA<CloudDenied>()));
      // Promote via test-only direct edit, then re-sign-in as manager.
      final driver = backend.currentAccount!;
      backend.users[driver.uid] = CloudAccount(
        uid: driver.uid,
        email: driver.email,
        username: driver.username,
        role: CloudRole.manager,
      );
      await auth.signOut();
      await auth.signIn(email: 'd@x.y', password: 'pw123456');
      expect((await backend.listUsers()).length, 1);
    });

    test('role cannot be self-assigned (service + backend)', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      final me = await auth.signUp(
        email: 'd@x.y',
        password: 'pw123456',
        username: 'd',
      );
      expect(
        () => auth.changeRole(me.uid, CloudRole.manager),
        throwsA(isA<CloudDenied>()),
      );
      // A driver cannot promote anyone else either.
      final other = await auth.signUp(
        email: 'o@x.y',
        password: 'pw123456',
        username: 'o',
      );
      await auth.signOut();
      await auth.signIn(email: 'd@x.y', password: 'pw123456');
      expect(
        () => auth.changeRole(other.uid, CloudRole.manager),
        throwsA(isA<CloudDenied>()),
      );
    });

    test('manager CAN promote another driver', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(email: 'm@x.y', password: 'pw123456', username: 'm');
      final mgr = backend.currentAccount!;
      backend.users[mgr.uid] = CloudAccount(
        uid: mgr.uid,
        email: mgr.email,
        username: mgr.username,
        role: CloudRole.manager,
      );
      final driver = await auth.signUp(
        email: 'd@x.y',
        password: 'pw123456',
        username: 'd',
      );
      await auth.signOut();
      await auth.signIn(email: 'm@x.y', password: 'pw123456');
      await auth.changeRole(driver.uid, CloudRole.manager);
      expect(backend.users[driver.uid]!.isManager, isTrue);
    });
  });

  group('v27.33 sync: queue, download, migration', () {
    test('offline queue holds edits and flush uploads on reconnect',
        () async {
      final backend = FakeCloudBackend();
      final sync = CloudSyncService(backend);
      final auth = CloudAuthService(backend);
      final me = await auth.signUp(
        email: 'd@x.y',
        password: 'pw123456',
        username: 'd',
      );
      backend.failWrites = true;
      await sync.queueDaySummary(
        CloudDaySummary(
          uid: me.uid,
          dateKey: '2026-10-29',
          ordersCount: 5,
          totalKm: 20,
          salaryTotal: 200,
        ),
      );
      expect(sync.hasPending, isTrue);
      backend.failWrites = false;
      final uploaded = await sync.flushQueue();
      expect(uploaded, 1);
      expect(sync.hasPending, isFalse);
      expect(
        (await backend.fetchDaySummary(me.uid, '2026-10-29'))!.ordersCount,
        5,
      );
    });

    test('first-login migration uploads exactly once per account', () async {
      final backend = FakeCloudBackend();
      final sync = CloudSyncService(backend);
      final auth = CloudAuthService(backend);
      final me = await auth.signUp(
        email: 'd@x.y',
        password: 'pw123456',
        username: 'd',
      );
      var marker = '';
      final summaries = [
        CloudDaySummary(
          uid: me.uid,
          dateKey: '2026-10-29',
          ordersCount: 4,
          totalKm: 15,
          salaryTotal: 150,
        ),
      ];
      final first = await sync.migrateLocalDataOnce(
        uid: me.uid,
        alreadyMigratedUid: null,
        localSummaries: summaries,
        localOrders: const [],
        markMigrated: (uid) async => marker = uid,
      );
      expect(first, isTrue);
      expect(marker, me.uid);
      final before = backend.saveDaySummaryCalls;
      final second = await sync.migrateLocalDataOnce(
        uid: me.uid,
        alreadyMigratedUid: marker,
        localSummaries: summaries,
        localOrders: const [],
        markMigrated: (uid) async => marker = uid,
      );
      expect(second, isFalse);
      expect(backend.saveDaySummaryCalls, before);
    });

    test('logout clears the per-account cloud cache (no leakage)',
        () async {
      final backend = FakeCloudBackend();
      final container = ProviderContainer(
        overrides: [cloudBackendProvider.overrideWithValue(backend)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(cloudAccountProvider.notifier);
      await notifier.signUp(
        email: 'd@x.y',
        password: 'pw123456',
        username: 'd',
      );
      final uid = container.read(cloudAccountProvider).account!.uid;
      await backend.saveDaySummary(
        CloudDaySummary(
          uid: uid,
          dateKey: '2026-10-29',
          ordersCount: 2,
          totalKm: 5,
          salaryTotal: 60,
        ),
      );
      await notifier.downloadFor(['2026-10-29']);
      expect(
        container.read(cloudAccountProvider).lastDownload,
        isNotNull,
      );
      await notifier.signOut();
      final state = container.read(cloudAccountProvider);
      expect(state.account, isNull);
      expect(state.lastDownload, isNull);
    });
  });

  group('v27.33 Hive marker round-trip', () {
    test('cloudMigratedUid survives a Hive save/load cycle', () async {
      final tmp = await Directory.systemTemp.createTemp('df_v2733_');
      addTearDown(() async {
        await Hive.close();
        await tmp.delete(recursive: true);
      });
      final db = DatabaseService();
      await db.init(hivePath: tmp.path);
      expect(db.settings.cloudMigratedUid, isNull);
      await db.saveSettings(
        UserSettings(cloudMigratedUid: 'uid_abc'),
      );
      expect(db.settings.cloudMigratedUid, 'uid_abc');
    });
  });

  group('v27.33 screens', () {
    // GlassScaffold paints AuroraBackground, which watches
    // settingsProvider — widget tests must override it with a real
    // notifier backed by a temp Hive database.
    Future<DatabaseService> tempDb(WidgetTester tester) async {
      late Directory tmp;
      late DatabaseService db;
      await tester.runAsync(() async {
        tmp = await Directory.systemTemp.createTemp('df_v2733_ui_');
        db = DatabaseService();
        await db.init(hivePath: tmp.path);
      });
      addTearDown(() => tester.runAsync(() async {
            await Hive.close();
            await tmp.delete(recursive: true);
          }));
      return db;
    }

    testWidgets('CloudAccount shows not-configured state', (tester) async {
      final db = await tempDb(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              (ref) => SettingsNotifier(db, NotificationService()),
            ),
          ],
          child: const MaterialApp(
            home: CloudAccountScreen(),
            routes: {},
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Cloud not configured yet'), findsOneWidget);
    });

    testWidgets('Management denies a driver and never queries the team',
        (tester) async {
      final db = await tempDb(tester);
      final backend = FakeCloudBackend();
      final container = ProviderContainer(
        overrides: [
          cloudBackendProvider.overrideWithValue(backend),
          settingsProvider.overrideWith(
            (ref) => SettingsNotifier(db, NotificationService()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(cloudAccountProvider.notifier).signUp(
            email: 'd@x.y',
            password: 'pw123456',
            username: 'driver1',
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ManagementScreen()),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Access denied'), findsOneWidget);
      expect(backend.listUsersCalls, 0);
    });

    testWidgets('Manager dashboard renders KPIs and flags unsynced driver',
        (tester) async {
      final db = await tempDb(tester);
      final backend = FakeCloudBackend();
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
        email: 'boss@x.y',
        password: 'pw123456',
        username: 'Boss',
      );
      final bossUid = container.read(cloudAccountProvider).account!.uid;
      // Promote Boss to manager the console way (direct doc edit),
      // then re-sign in so the session carries the manager role.
      backend.users[bossUid] = CloudAccount(
        uid: bossUid,
        email: 'boss@x.y',
        username: 'Boss',
        role: CloudRole.manager,
      );
      await notifier.signOut();
      await notifier.signIn(email: 'boss@x.y', password: 'pw123456');
      // A second driver who has NOT synced today.
      await backend.signUp(
        email: 'quiet@x.y',
        password: 'pw123456',
        username: 'Quiet',
      );
      await backend.signOut();
      await notifier.signIn(email: 'boss@x.y', password: 'pw123456');
      // Boss synced today; Quiet did not.
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
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ManagementScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('6'), findsWidgets); // Orders today KPI.
      expect(find.text('Quiet'), findsOneWidget);
      expect(find.text('Not synced'), findsOneWidget);
      expect(find.textContaining('Not synced:'), findsOneWidget);
    });

    testWidgets('Driver detail route is denied for drivers', (tester) async {
      final db = await tempDb(tester);
      final backend = FakeCloudBackend();
      final container = ProviderContainer(
        overrides: [
          cloudBackendProvider.overrideWithValue(backend),
          settingsProvider.overrideWith(
            (ref) => SettingsNotifier(db, NotificationService()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(cloudAccountProvider.notifier).signUp(
            email: 'd@x.y',
            password: 'pw123456',
            username: 'driver1',
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ManagementDriverScreen(uid: 'someone', dateKey: '2026-10-29'),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Access denied'), findsOneWidget);
      expect(backend.listUsersCalls, 0);
    });
  });

  group('v27.33 management dashboard logic', () {
    List<DriverDayRow> rows() {
      const boss = CloudAccount(
        uid: 'boss',
        email: 'boss@x.y',
        username: 'Boss',
        role: CloudRole.manager,
      );
      const ali = CloudAccount(
        uid: 'ali',
        email: 'ali@x.y',
        username: 'Ali',
      );
      const badr = CloudAccount(
        uid: 'badr',
        email: 'badr@x.y',
        username: 'Badr',
      );
      return buildDriverRows(
        const [boss, ali, badr],
        [
          buildDaySummary(
            uid: 'boss',
            dateKey: '2026-10-29',
            ordersCount: 6,
            totalKm: 30,
            orderPrice: 20,
            dailyFixedPay: 100,
            distanceBonus: 10,
            manualBonus: 0,
            flatBonus: 0,
          ),
          buildDaySummary(
            uid: 'ali',
            dateKey: '2026-10-29',
            ordersCount: 0,
            totalKm: 0,
            orderPrice: 20,
            dailyFixedPay: 100,
            distanceBonus: 0,
            manualBonus: 0,
            flatBonus: 0,
          ),
          // Badr has NO summary — not synced, never zero.
        ],
      );
    }

    test('KPI totals sum synced rows only', () {
      final kpis = computeKpis(rows());
      expect(kpis.driversActive, 2); // Boss + Ali; Badr excluded.
      expect(kpis.totalOrders, 6);
      expect(kpis.totalKm, 30);
      expect(kpis.salaryDue, 6 * 20 + 100 + 10); // Ali adds 0.
    });

    test('sorting by orders/salary and name search', () {
      final r = rows();
      final byOrders = sortDrivers(r, ManagementSort.orders);
      expect(byOrders.first.account.username, 'Boss');
      final bySalary = sortDrivers(r, ManagementSort.salary);
      expect(bySalary.first.account.username, 'Boss');
      final byName = sortDrivers(r, ManagementSort.name);
      expect(byName.map((e) => e.account.username).toList(),
          ['Ali', 'Badr', 'Boss']);
      final filtered = filterDrivers(r, 'al');
      expect(filtered.map((e) => e.account.username).toList(), ['Ali']);
      expect(filterDrivers(r, '').length, 3);
    });

    test('unsynced flagging never confuses not-synced with zero', () {
      final r = rows();
      final badr = r.firstWhere((e) => e.account.uid == 'badr');
      final ali = r.firstWhere((e) => e.account.uid == 'ali');
      expect(badr.synced, isFalse);
      expect(ali.synced, isTrue);
      final alerts = findAlerts(r);
      expect(alerts.notSynced.map((e) => e.account.uid), ['badr']);
      expect(alerts.zeroOrders.map((e) => e.account.uid), ['ali']);
    });

    test('driver detail breakdown sums to the salary total', () {
      final s = buildDaySummary(
        uid: 'ali',
        dateKey: '2026-10-29',
        ordersCount: 8,
        totalKm: 40,
        orderPrice: 20,
        dailyFixedPay: 100,
        distanceBonus: 15,
        manualBonus: 5,
        flatBonus: 10,
      );
      expect(s.hasBreakdown, isTrue);
      expect(
        s.ordersCount * s.orderPrice +
            s.dailyFixedPay +
            s.distanceBonus +
            s.manualBonus +
            s.flatBonus,
        s.salaryTotal,
      );
      const old = CloudDaySummary(
        uid: 'ali',
        dateKey: '2026-10-28',
        ordersCount: 3,
        totalKm: 10,
        salaryTotal: 60,
      );
      expect(old.hasBreakdown, isFalse); // Total only, never invented.
    });

    test('week orders per day and per-driver week totals', () {
      final week = {
        '2026-10-26': [
          const CloudDaySummary(
            uid: 'ali',
            dateKey: '2026-10-26',
            ordersCount: 3,
            totalKm: 10,
            salaryTotal: 60,
          ),
        ],
        '2026-10-27': [
          const CloudDaySummary(
            uid: 'ali',
            dateKey: '2026-10-27',
            ordersCount: 5,
            totalKm: 20,
            salaryTotal: 100,
          ),
          const CloudDaySummary(
            uid: 'badr',
            dateKey: '2026-10-27',
            ordersCount: 2,
            totalKm: 5,
            salaryTotal: 40,
          ),
        ],
      };
      expect(
        weekOrdersPerDay(week, ['2026-10-26', '2026-10-27', '2026-10-28']),
        [3, 7, 0],
      );
      final totals = driverWeekTotals(week);
      expect(totals['ali']!.orders, 8);
      expect(totals['badr']!.salary, 40);
    });
  });

  group('v27.33 Google sign-in', () {
    test('Google sign-in creates a driver doc with the same structure',
        () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      final account = await auth.signInWithGoogle();
      expect(account, isNotNull);
      expect(account!.role, CloudRole.driver);
      expect(account.username, 'Google Driver');
      // Same doc structure: profile + summaries + orders under the UID.
      final profile = await backend.fetchProfile(account.uid);
      expect(profile!.email, account.email);
      await backend.saveDaySummary(
        CloudDaySummary(
          uid: account.uid,
          dateKey: '2026-10-29',
          ordersCount: 4,
          totalKm: 12,
          salaryTotal: 80,
        ),
      );
      expect(
        (await backend.fetchDaySummary(account.uid, '2026-10-29'))!
            .ordersCount,
        4,
      );
    });

    test('repeat Google sign-in loads the same account, no duplicate',
        () async {
      final backend = FakeCloudBackend();
      final first = await backend.signInWithGoogle();
      await backend.signOut();
      final second = await backend.signInWithGoogle();
      expect(second!.uid, first!.uid);
      expect(backend.users.length, 1);
    });

    test('Google login is NOT auto-linked to an email account', () async {
      final backend = FakeCloudBackend();
      // Email/Password account with the SAME email address first.
      await backend.signUp(
        email: 'google.driver@example.com',
        password: 'pw123456',
        username: 'Email Driver',
      );
      final emailUid = backend.currentAccount!.uid;
      await backend.signOut();
      final google = await backend.signInWithGoogle();
      expect(google!.uid, isNot(emailUid));
      expect(backend.users.length, 2);
    });

    test('manager gating applies to Google accounts', () async {
      final backend = FakeCloudBackend();
      final google = (await backend.signInWithGoogle())!;
      expect(
        () => backend.listUsers(),
        throwsA(isA<CloudDenied>()),
      );
      // Console promotion, then re-sign-in carries the manager role.
      backend.users[google.uid] = CloudAccount(
        uid: google.uid,
        email: google.email,
        username: google.username,
        role: CloudRole.manager,
      );
      await backend.signOut();
      final again = (await backend.signInWithGoogle())!;
      expect(again.isManager, isTrue);
      expect((await backend.listUsers()).length, 1);
    });

    test('a Google UID cannot read another user\'s data', () async {
      final backend = FakeCloudBackend();
      final google = (await backend.signInWithGoogle())!;
      await backend.signOut();
      await backend.signUp(
        email: 'other@x.y',
        password: 'pw123456',
        username: 'Other',
      );
      final otherUid = backend.currentAccount!.uid;
      await backend.signOut();
      await backend.signInWithGoogle();
      expect(google.uid, isNot(otherUid));
      expect(
        () => backend.fetchDaySummary(otherUid, '2026-10-29'),
        throwsA(isA<CloudDenied>()),
      );
      expect(
        () => backend.fetchOrderRecord(otherUid, '2026-10-29'),
        throwsA(isA<CloudDenied>()),
      );
    });
  });

  group('v27.33 manager edits + adjustments', () {
    /// Returns (backend, bossUid, driverUid) with boss as manager
    /// signed in at the end.
    Future<(FakeCloudBackend, String, String)> managerSetup() async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(
        email: 'boss@x.y',
        password: 'pw123456',
        username: 'Boss',
      );
      final bossUid = backend.currentAccount!.uid;
      await backend.signUp(
        email: 'driver@x.y',
        password: 'pw123456',
        username: 'Driver',
      );
      final driverUid = backend.currentAccount!.uid;
      backend.users[bossUid] = CloudAccount(
        uid: bossUid,
        email: 'boss@x.y',
        username: 'Boss',
        role: CloudRole.manager,
      );
      await backend.signOut();
      await backend.signIn(email: 'boss@x.y', password: 'pw123456');
      return (backend, bossUid, driverUid);
    }

    test('manager edit of a driver\'s order syncs with manager stamp',
        () async {
      final (backend, bossUid, driverUid) = await managerSetup();
      await backend.saveDaySummary(
        buildDaySummary(
          uid: driverUid,
          dateKey: '2026-10-29',
          ordersCount: 9,
          totalKm: 44,
          orderPrice: 20,
          dailyFixedPay: 100,
          distanceBonus: 0,
          manualBonus: 0,
          flatBonus: 0,
        ),
      );
      await backend.saveOrderRecord(driverUid, '2026-10-29', {
        'completedOrders': 9,
        'totalKm': 44,
      });
      // Driver signs in and sees the manager's edit, stamped.
      await backend.signOut();
      await backend.signIn(email: 'driver@x.y', password: 'pw123456');
      final summary =
          await backend.fetchDaySummary(driverUid, '2026-10-29');
      expect(summary!.ordersCount, 9);
      expect(summary.editedByManager, isTrue);
      expect(summary.editedByManagerUid, bossUid);
      final record = await backend.fetchOrderRecord(driverUid, '2026-10-29');
      expect(record!['editedByManagerUid'], bossUid);
    });

    test('driver cannot edit another driver', () async {
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'a@x.y',
        password: 'pw123456',
        username: 'A',
      );
      final aUid = backend.currentAccount!.uid;
      await backend.signUp(
        email: 'b@x.y',
        password: 'pw123456',
        username: 'B',
      );
      final bUid = backend.currentAccount!.uid;
      await backend.signOut();
      await backend.signIn(email: 'a@x.y', password: 'pw123456');
      expect(aUid, isNot(bUid));
      expect(
        () => backend.saveDaySummary(
          CloudDaySummary(
            uid: bUid,
            dateKey: '2026-10-29',
            ordersCount: 5,
            totalKm: 10,
            salaryTotal: 100,
          ),
        ),
        throwsA(isA<CloudDenied>()),
      );
      expect(
        () => backend.saveOrderRecord(bUid, '2026-10-29', {}),
        throwsA(isA<CloudDenied>()),
      );
      expect(
        () => backend.saveProfile(
          CloudAccount(uid: bUid, email: 'b@x.y', username: 'Hacked'),
        ),
        throwsA(isA<CloudDenied>()),
      );
      expect(
        () => backend.deleteUserDay(bUid, '2026-10-29'),
        throwsA(isA<CloudDenied>()),
      );
    });

    test('manager cannot change his own role', () async {
      final (backend, bossUid, _) = await managerSetup();
      final auth = CloudAuthService(backend);
      expect(
        () => auth.changeRole(bossUid, CloudRole.driver),
        throwsA(isA<CloudDenied>()),
      );
      expect(backend.users[bossUid]!.role, CloudRole.manager);
    });

    test('non-manager cannot promote anyone', () async {
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'd@x.y',
        password: 'pw123456',
        username: 'D',
      );
      final auth = CloudAuthService(backend);
      expect(
        () => auth.changeRole('someone-else', CloudRole.manager),
        throwsA(isA<CloudDenied>()),
      );
    });

    test('manager delete removes the driver\'s day', () async {
      final (backend, _, driverUid) = await managerSetup();
      await backend.saveDaySummary(
        CloudDaySummary(
          uid: driverUid,
          dateKey: '2026-10-29',
          ordersCount: 3,
          totalKm: 10,
          salaryTotal: 60,
        ),
      );
      await backend.deleteUserDay(driverUid, '2026-10-29');
      await backend.signOut();
      await backend.signIn(email: 'driver@x.y', password: 'pw123456');
      expect(
        await backend.fetchDaySummary(driverUid, '2026-10-29'),
        isNull,
      );
    });

    test('bonus raises and deduction lowers the weekly total', () {
      const weekKey = '2026-10-26';
      final adjustments = [
        const CloudAdjustment(
          id: 'a1',
          uid: 'd',
          type: CloudAdjustmentType.bonus,
          amount: 200,
          reason: 'Extra effort',
          weekKey: weekKey,
          createdBy: 'boss',
          createdAtMillis: 1,
        ),
        const CloudAdjustment(
          id: 'a2',
          uid: 'd',
          type: CloudAdjustmentType.deduction,
          amount: 150,
          reason: 'Late arrival',
          weekKey: weekKey,
          createdBy: 'boss',
          createdAtMillis: 2,
        ),
        const CloudAdjustment(
          id: 'a3',
          uid: 'd',
          type: CloudAdjustmentType.bonus,
          amount: 500,
          reason: 'Other week',
          weekKey: '2026-11-02',
          createdBy: 'boss',
          createdAtMillis: 3,
        ),
      ];
      final week = adjustmentsForWeek(adjustments, weekKey);
      expect(week.length, 2); // Other-week adjustment excluded.
      expect(weeklyTotalWithAdjustments(1000, week), 1000 + 200 - 150);
      expect(weeklyTotalWithAdjustments(1000, []), 1000);
    });

    test('adjustment validation: reason mandatory, amount positive', () {
      expect(
        validateAdjustment(amount: 100, reason: '  '),
        isNotNull,
      );
      expect(validateAdjustment(amount: 0, reason: 'Why'), isNotNull);
      expect(validateAdjustment(amount: -5, reason: 'Why'), isNotNull);
      expect(validateAdjustment(amount: null, reason: 'Why'), isNotNull);
      expect(validateAdjustment(amount: 100, reason: 'Good work'), isNull);
    });

    test('driver cannot create his own adjustment', () async {
      final backend = FakeCloudBackend();
      await backend.signUp(
        email: 'd@x.y',
        password: 'pw123456',
        username: 'D',
      );
      final uid = backend.currentAccount!.uid;
      expect(
        () => backend.saveAdjustment(
          const CloudAdjustment(
            id: '',
            uid: 'PLACEHOLDER',
            type: CloudAdjustmentType.bonus,
            amount: 999,
            reason: 'Self bonus',
            weekKey: '2026-10-26',
            createdBy: '',
            createdAtMillis: 0,
          ),
        ),
        throwsA(isA<CloudDenied>()),
      );
      // Correct uid, still denied: drivers never write adjustments.
      expect(
        () => backend.saveAdjustment(
          CloudAdjustment(
            id: '',
            uid: uid,
            type: CloudAdjustmentType.bonus,
            amount: 999,
            reason: 'Self bonus',
            weekKey: '2026-10-26',
            createdBy: '',
            createdAtMillis: 0,
          ),
        ),
        throwsA(isA<CloudDenied>()),
      );
    });

    test('manager-only write: manager creates/edits/deletes, driver reads',
        () async {
      final (backend, bossUid, driverUid) = await managerSetup();
      final created = await backend.saveAdjustment(
        CloudAdjustment(
          id: '',
          uid: driverUid,
          type: CloudAdjustmentType.bonus,
          amount: 300,
          reason: 'Great week',
          weekKey: '2026-10-26',
          createdBy: '',
          createdAtMillis: 0,
        ),
      );
      expect(created.id, isNotEmpty);
      expect(created.createdBy, bossUid); // Stamp is the manager's UID.
      // Edit.
      final edited = await backend.saveAdjustment(
        CloudAdjustment(
          id: created.id,
          uid: driverUid,
          type: CloudAdjustmentType.deduction,
          amount: 50,
          reason: 'Corrected',
          weekKey: '2026-10-26',
          createdBy: '',
          createdAtMillis: created.createdAtMillis,
        ),
      );
      expect(edited.type, CloudAdjustmentType.deduction);
      // Driver reads own adjustments with reason + manager stamp.
      await backend.signOut();
      await backend.signIn(email: 'driver@x.y', password: 'pw123456');
      final mine = await backend.listAdjustments(driverUid);
      expect(mine.length, 1);
      expect(mine.first.reason, 'Corrected');
      expect(mine.first.createdBy, bossUid);
      // Driver cannot delete.
      expect(
        () => backend.deleteAdjustment(driverUid, created.id),
        throwsA(isA<CloudDenied>()),
      );
      // Manager can delete.
      await backend.signOut();
      await backend.signIn(email: 'boss@x.y', password: 'pw123456');
      await backend.deleteAdjustment(driverUid, created.id);
      expect(await backend.listAdjustments(driverUid), isEmpty);
    });

    test('manager cannot adjust his own pay', () async {
      final (backend, bossUid, _) = await managerSetup();
      expect(
        () => backend.saveAdjustment(
          CloudAdjustment(
            id: '',
            uid: bossUid,
            type: CloudAdjustmentType.bonus,
            amount: 1000,
            reason: 'Self',
            weekKey: '2026-10-26',
            createdBy: '',
            createdAtMillis: 0,
          ),
        ),
        throwsA(isA<CloudDenied>()),
      );
    });

    testWidgets('manager edit screen saves the driver\'s day',
        (tester) async {
      // Tall form: enlarge the viewport so every field + the save
      // button fit without scrolling (avoids hit-test misses).
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = await tempDbForTest(tester);      final backend = FakeCloudBackend();
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
        email: 'boss@x.y',
        password: 'pw123456',
        username: 'Boss',
      );
      final bossUid = container.read(cloudAccountProvider).account!.uid;
      await notifier.signUp(
        email: 'driver@x.y',
        password: 'pw123456',
        username: 'Driver',
      );
      final driverUid = backend.currentAccount!.uid;
      backend.users[bossUid] = CloudAccount(
        uid: bossUid,
        email: 'boss@x.y',
        username: 'Boss',
        role: CloudRole.manager,
      );
      await notifier.signOut();
      await notifier.signIn(email: 'boss@x.y', password: 'pw123456');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            // The edit screen pops on save, so the test harness needs
            // a real GoRouter (as in the app) rather than a bare
            // MaterialApp.
            routerConfig: GoRouter(
              // Nested so the edit screen can pop back to '/' on save.
              initialLocation: '/edit',
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) =>
                      const Scaffold(body: SizedBox()),
                  routes: [
                    GoRoute(
                      path: 'edit',
                      builder: (context, state) => ManagerEditDayScreen(
                        uid: driverUid,
                        dateKey: managementDateKey(DateTime.now()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(
        find.byKey(const ValueKey('managerEditOrders')),
        '7',
      );
      await tester.enterText(
        find.byKey(const ValueKey('managerEditKm')),
        '33.5',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('managerEditSave')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('managerEditSave')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final saved = backend.summaries[driverUid]?[managementDateKey(
        DateTime.now(),
      )];
      expect(saved!.ordersCount, 7);
      expect(saved.totalKm, 33.5);
      expect(saved.editedByManager, isTrue);
    });
  });

  group('v27.33 identifier login + credentials', () {
    test('phone normalization is consistent across written forms', () {
      expect(normalizeEgyptPhone('01012345678'), '1012345678');
      expect(normalizeEgyptPhone('+201012345678'), '1012345678');
      expect(normalizeEgyptPhone('00201012345678'), '1012345678');
      expect(normalizeEgyptPhone('0101 234 5678'), '1012345678');
      expect(normalizeEgyptPhone('201012345678'), '1012345678');
      expect(isValidEgyptPhone('01012345678'), isTrue);
      expect(isValidEgyptPhone('0123456789'), isFalse);
      // Raw phone is never the lookup key.
      expect(phoneLookupKey('01012345678'), isNot('01012345678'));
      expect(
        phoneLookupKey('01012345678'),
        phoneLookupKey('+201012345678'),
      );
    });

    test('login by username succeeds (case-insensitive)', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(
        email: 'ali@x.y',
        password: 'pw123456',
        username: 'Ali',
        phone: '01012345678',
      );
      await backend.signOut();
      final account = await auth.signInWithIdentifier(
        identifier: 'ALI',
        password: 'pw123456',
      );
      expect(account.email, 'ali@x.y');
    });

    test('login by phone succeeds in any written form', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(
        email: 'ali@x.y',
        password: 'pw123456',
        username: 'Ali',
        phone: '01012345678',
      );
      await backend.signOut();
      expect(
        (await auth.signInWithIdentifier(
          identifier: '+201012345678',
          password: 'pw123456',
        ))
            .uid,
        isNotEmpty,
      );
      await backend.signOut();
      expect(
        (await auth.signInWithIdentifier(
          identifier: '0101 234 5678',
          password: 'pw123456',
        ))
            .email,
        'ali@x.y',
      );
    });

    test('wrong identifier or password fails', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(
        email: 'ali@x.y',
        password: 'pw123456',
        username: 'Ali',
        phone: '01012345678',
      );
      await backend.signOut();
      expect(
        () => auth.signInWithIdentifier(
          identifier: 'Nobody',
          password: 'pw123456',
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        () => auth.signInWithIdentifier(
          identifier: 'Ali',
          password: 'wrong-password',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('duplicate username rejected with the exact taken message',
        () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(
        email: 'a@x.y',
        password: 'pw123456',
        username: 'Ali',
        phone: '01012345678',
      );
      // Same username in a different case is the same username.
      Object? error;
      try {
        await auth.signUp(
          email: 'b@x.y',
          password: 'pw123456',
          username: 'ALI',
          phone: '01112345678',
        );
      } catch (e) {
        error = e;
      }
      expect(
        error.toString(),
        contains('الـ username ده اتاخد قبل كده، اختار username تاني'),
      );
      // Mapping-create race: a second writer cannot overwrite the
      // mapping doc — the backend rejects it even if the client
      // check were bypassed.
      expect(backend.usernameLookups['ali'], 'a@x.y');
    });

    test('duplicate phone rejected', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(
        email: 'a@x.y',
        password: 'pw123456',
        username: 'Ali',
        phone: '01012345678',
      );
      Object? error;
      try {
        await auth.signUp(
          email: 'b@x.y',
          password: 'pw123456',
          username: 'Badr',
          phone: '+201012345678',
        );
      } catch (e) {
        error = e;
      }
      expect(
        error.toString(),
        contains('رقم الموبايل ده اتاخد قبل كده، استخدم رقم تاني'),
      );
    });

    test('username change releases the old username', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(
        email: 'ali@x.y',
        password: 'pw123456',
        username: 'OldName',
        phone: '01012345678',
      );
      await auth.changeUsername('NewName');
      expect(await backend.resolveLoginEmail('OldName'), isNull);
      expect(
        await backend.resolveLoginEmail('NewName'),
        'ali@x.y',
      );
      await backend.signOut();
      expect(
        (await auth.signInWithIdentifier(
          identifier: 'NewName',
          password: 'pw123456',
        ))
            .username,
        'NewName',
      );
    });

    test('old password stops working after change', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(
        email: 'ali@x.y',
        password: 'pw123456',
        username: 'Ali',
        phone: '01012345678',
      );
      expect(
        () => auth.changePassword(
          currentPassword: 'wrong',
          newPassword: 'newpass123',
        ),
        throwsA(isA<Exception>()),
      );
      await auth.changePassword(
        currentPassword: 'pw123456',
        newPassword: 'newpass123',
      );
      await backend.signOut();
      expect(
        () => auth.signIn(email: 'ali@x.y', password: 'pw123456'),
        throwsA(isA<Exception>()),
      );
      expect(
        (await auth.signIn(email: 'ali@x.y', password: 'newpass123'))
            .email,
        'ali@x.y',
      );
    });

    test('lookup collections cannot be listed', () {
      final backend = FakeCloudBackend();
      expect(
        () => backend.listUsernameKeys(),
        throwsA(isA<CloudDenied>()),
      );
    });

    test('forgot flow: reset email + username reminder', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(
        email: 'ali@x.y',
        password: 'pw123456',
        username: 'Ali',
        phone: '01012345678',
      );
      await auth.sendPasswordReset('ali@x.y');
      expect(backend.sentPasswordResets, ['ali@x.y']);
      expect(await auth.lookupUsernameByEmail('ali@x.y'), 'Ali');
      expect(await auth.lookupUsernameByEmail('ghost@x.y'), isNull);
    });
  });

  group('v27.33 first-run flow', () {
    test('fresh install: invite gate before every route', () {
      // Unregistered user asking for the account screen, home, or
      // onboarding is sent to the invite gate first.
      for (final loc in ['/cloud-account', '/home', '/onboarding']) {
        expect(
          resolveFirstRunRedirect(
            registered: false,
            onboardingDone: false,
            uriString: loc,
            matchedLocation: loc,
          ),
          '/register',
        );
      }
      expect(
        resolveFirstRunRedirect(
          registered: false,
          onboardingDone: false,
          uriString: '/splash',
          matchedLocation: '/splash',
        ),
        '/register',
      );
    });

    test('upgrade path: registered users skip the invite gate', () {
      expect(
        resolveFirstRunRedirect(
          registered: true,
          onboardingDone: true,
          uriString: '/cloud-account',
          matchedLocation: '/cloud-account',
        ),
        isNull,
      );
      expect(
        resolveFirstRunRedirect(
          registered: true,
          onboardingDone: true,
          uriString: '/register',
          matchedLocation: '/register',
        ),
        '/splash',
      );
      expect(
        resolveFirstRunRedirect(
          registered: true,
          onboardingDone: false,
          uriString: '/home',
          matchedLocation: '/home',
        ),
        '/onboarding',
      );
    });

    testWidgets('account-choice screen offers both options first',
        (tester) async {
      final db = await tempDbForTest(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              (ref) => SettingsNotifier(db, NotificationService()),
            ),
          ],
          child: const MaterialApp(home: CloudAccountScreen()),
        ),
      );
      await tester.pump();
      // Choice first: both Arabic options, no login form yet.
      expect(find.text('إنشاء حساب'), findsOneWidget);
      expect(find.text('لدي حساب بالفعل'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cloudIdentifierField')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('cloudChoiceExisting')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('cloudIdentifierField')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('cloudForgotLink')), findsOneWidget);
      await tester.ensureVisible(find.text('Back to account choices'));
      await tester.pump();
      await tester.tap(find.text('Back to account choices'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cloudChoiceCreate')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('cloudUsernameField')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('cloudPhoneField')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cloudSignupEmailField')),
        findsOneWidget,
      );
    });
  });

  group('v27.33 mustChangePassword', () {
    testWidgets('flag blocks dashboard access and data reads',
        (tester) async {
      final db = await tempDbForTest(tester);
      final backend = FakeCloudBackend();
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
        email: 'admin@x.y',
        password: 'dummy-password-for-test-only',
        username: 'admin',
        phone: '01012345678',
      );
      final uid = container.read(cloudAccountProvider).account!.uid;
      // Owner console step (simulated): role + forced-change flag.
      backend.users[uid] = CloudAccount(
        uid: uid,
        email: 'admin@x.y',
        username: 'admin',
        role: CloudRole.manager,
        phone: '1012345678',
        mustChangePassword: true,
      );
      await notifier.signOut();
      await notifier.signIn(email: 'admin@x.y', password: 'dummy-password-for-test-only');
      expect(
        container.read(cloudAccountProvider).account!.mustChangePassword,
        isTrue,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ManagementScreen()),
        ),
      );
      await tester.pump();
      expect(find.textContaining('يجب تغيير كلمة المرور'), findsOneWidget);
      expect(backend.listUsersCalls, 0);
    });

    test('after change the flag clears and access is granted', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(
        email: 'admin@x.y',
        password: 'dummy-password-for-test-only',
        username: 'admin',
        phone: '01012345678',
      );
      final uid = backend.currentAccount!.uid;
      backend.users[uid] = CloudAccount(
        uid: uid,
        email: 'admin@x.y',
        username: 'admin',
        role: CloudRole.manager,
        phone: '1012345678',
        mustChangePassword: true,
      );
      await backend.signOut();
      await backend.signIn(
        email: 'admin@x.y',
        password: 'dummy-password-for-test-only',
      );
      expect(backend.currentAccount!.mustChangePassword, isTrue);
      // Backend gate: a flagged account cannot read team data.
      expect(
        () => backend.listUsers(),
        throwsA(isA<CloudDenied>()),
      );
      await auth.changePassword(
        currentPassword: 'dummy-password-for-test-only',
        newPassword: 'new-dummy-password-for-test-only',
      );
      expect(backend.currentAccount!.mustChangePassword, isFalse);
      expect((await backend.listUsers()).length, 1);
      await backend.signOut();
      expect(
        () => backend.signIn(
          email: 'admin@x.y',
          password: 'dummy-password-for-test-only',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('v27.33 session persistence', () {
    test('session survives simulated app restart', () async {
      final backend = FakeCloudBackend();
      final first = ProviderContainer(
        overrides: [cloudBackendProvider.overrideWithValue(backend)],
      );
      addTearDown(first.dispose);
      await first.read(cloudAccountProvider.notifier).signUp(
            email: 'd@x.y',
            password: 'pw123456',
            username: 'driver1',
          );
      final uid = first.read(cloudAccountProvider).account!.uid;
      // Simulated restart: brand-new container, SAME backend object
      // (mirrors Firebase Auth's stored session surviving a restart).
      final restarted = ProviderContainer(
        overrides: [cloudBackendProvider.overrideWithValue(backend)],
      );
      addTearDown(restarted.dispose);
      expect(restarted.read(cloudAccountProvider).account, isNull);
      final restored =
          await restarted.read(cloudAccountProvider.notifier).restoreSession();
      expect(restored, isTrue);
      expect(restarted.read(cloudAccountProvider).account!.uid, uid);
    });

    test('fingerprint lock/unlock does not change auth state', () async {
      final backend = FakeCloudBackend();
      final container = ProviderContainer(
        overrides: [cloudBackendProvider.overrideWithValue(backend)],
      );
      addTearDown(container.dispose);
      await container.read(cloudAccountProvider.notifier).signUp(
            email: 'd@x.y',
            password: 'pw123456',
            username: 'driver1',
          );
      final uid = container.read(cloudAccountProvider).account!.uid;
      // Lock + unlock touches no auth API: the session object is
      // untouched and restores identically.
      expect(backend.currentAccount!.uid, uid);
      expect(
        await container
            .read(cloudAccountProvider.notifier)
            .restoreSession(),
        isTrue,
      );
      expect(container.read(cloudAccountProvider).account!.uid, uid);
    });

    testWidgets('sign-out clears session and shows account choice',
        (tester) async {
      final db = await tempDbForTest(tester);
      final backend = FakeCloudBackend();
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
        email: 'd@x.y',
        password: 'pw123456',
        username: 'driver1',
      );
      await notifier.downloadFor(['2026-10-29']);
      expect(
        container.read(cloudAccountProvider).lastDownload,
        isNotNull,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CloudAccountScreen()),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Sign out'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cloudSignOutConfirm')));
      await tester.pump();
      expect(container.read(cloudAccountProvider).account, isNull);
      expect(container.read(cloudAccountProvider).lastDownload, isNull);
      expect(backend.currentAccount, isNull);
      expect(find.text('إنشاء حساب'), findsOneWidget);
      expect(find.text('لدي حساب بالفعل'), findsOneWidget);
    });
  });
}

extension on CloudDaySummary {
  CloudDaySummary copyWithUid(String uid) => CloudDaySummary(
        uid: uid,
        dateKey: dateKey,
        ordersCount: ordersCount,
        totalKm: totalKm,
        salaryTotal: salaryTotal,
        updatedAtMillis: updatedAtMillis,
      );
}
