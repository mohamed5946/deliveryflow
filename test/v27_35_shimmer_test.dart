// v27.35 — Shimmer loading skeleton for the Management screen.
//
// While the Management dashboard's data is loading, the screen
// shows a shimmer skeleton mirroring the real layout (freshness
// note, KPI cards, week chart card, search bar, sort chips, driver
// rows with avatar circle + text lines) instead of a bare spinner,
// so swapping to real content causes no layout jump. The shine is
// theme-aware: light base grey.shade300 / highlight grey.shade100,
// dark base grey.shade800 / highlight grey.shade700.
//
// Honest note: shimmer only FEELS faster — it does not make
// loading faster.
//
// All values here are DUMMY. No real code, password, or secret
// appears in this file.

import 'dart:io';

import 'package:deliveryflow/core/cloud/cloud_providers.dart';
import 'package:deliveryflow/core/cloud/cloud_types.dart';
import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/cloud/management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shimmer/shimmer.dart';

import 'v27_33_test.dart' show FakeCloudBackend;

void main() {
  Future<ProviderContainer> setupContainer(
    WidgetTester tester,
    FakeCloudBackend backend,
  ) async {
    late Directory tmp;
    late DatabaseService db;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('df_v2735_shim_');
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
    });
    addTearDown(() => tester.runAsync(() async {
          await Hive.close();
          await tmp.delete(recursive: true);
        }));
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

  /// Same promotion pattern as the blocklist widget tests: sign
  /// up, then replace the stored account with a manager one.
  Future<void> signInAsManager(
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
  }

  group('management shimmer skeleton', () {
    testWidgets('loading state renders the skeleton, not a spinner',
        (tester) async {
      final backend = FakeCloudBackend()
        ..listDelay = const Duration(seconds: 30);
      final container = await setupContainer(tester, backend);
      final notifier = container.read(cloudAccountProvider.notifier);
      await signInAsManager(backend, notifier);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ManagementScreen()),
        ),
      );
      await tester.pump();
      // Still loading (fake delay unelapsed): skeleton visible,
      // no CircularProgressIndicator anywhere in this state.
      expect(
        find.byKey(const ValueKey('managementSkeleton')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Skeleton sections mirror the real layout.
      expect(
        find.byKey(const ValueKey('managementSkeletonFreshness')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('managementSkeletonKpis')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('managementSkeletonChart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('managementSkeletonSearch')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('managementSkeletonChips')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('managementSkeletonRow-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('managementSkeletonRow-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('managementSkeletonRow-2')),
        findsOneWidget,
      );
      // Flush the fake delay so no timer is left pending.
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
    });

    testWidgets('skeleton uses light-theme shimmer colors',
        (tester) async {
      final backend = FakeCloudBackend()
        ..listDelay = const Duration(seconds: 30);
      final container = await setupContainer(tester, backend);
      final notifier = container.read(cloudAccountProvider.notifier);
      await signInAsManager(backend, notifier);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: const ManagementScreen(),
          ),
        ),
      );
      await tester.pump();
      final shimmer =
          tester.widget<Shimmer>(find.byType(Shimmer).first);
      // Shimmer.fromColors folds the colors into a LinearGradient
      // [base, base, highlight, base, base].
      final gradient = shimmer.gradient as LinearGradient;
      expect(gradient.colors, [
        Colors.grey.shade300,
        Colors.grey.shade300,
        Colors.grey.shade100,
        Colors.grey.shade300,
        Colors.grey.shade300,
      ]);
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
    });

    testWidgets('skeleton uses dark-theme shimmer colors',
        (tester) async {
      final backend = FakeCloudBackend()
        ..listDelay = const Duration(seconds: 30);
      final container = await setupContainer(tester, backend);
      final notifier = container.read(cloudAccountProvider.notifier);
      await signInAsManager(backend, notifier);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const ManagementScreen(),
          ),
        ),
      );
      await tester.pump();
      final shimmer =
          tester.widget<Shimmer>(find.byType(Shimmer).first);
      final gradient = shimmer.gradient as LinearGradient;
      expect(gradient.colors, [
        Colors.grey.shade800,
        Colors.grey.shade800,
        Colors.grey.shade700,
        Colors.grey.shade800,
        Colors.grey.shade800,
      ]);
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
    });

    testWidgets('real content replaces the skeleton after load',
        (tester) async {
      final backend = FakeCloudBackend()
        ..listDelay = const Duration(milliseconds: 200);
      final container = await setupContainer(tester, backend);
      final notifier = container.read(cloudAccountProvider.notifier);
      await signInAsManager(backend, notifier);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ManagementScreen()),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('managementSkeleton')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('managementSkeleton')),
        findsNothing,
      );
      // Real dashboard content: KPI tile present again.
      expect(
        find.byKey(const ValueKey('managementKpiDrivers')),
        findsOneWidget,
      );
    });
  });
}
