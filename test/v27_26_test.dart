import 'dart:io';

import 'package:deliveryflow/core/app_lock/app_lock_service.dart';
import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/profile/profile_screen.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:local_auth/local_auth.dart';

/// Fake OS client that can throw a plugin error, return no biometrics,
/// or succeed — drives the v27.26 structured-result mapping.
class _ThrowingClient implements AppLockAuthClient {
  _ThrowingClient({
    this.enrolled = const [],
    this.throwCode,
    this.authResult = true,
  });

  final List<BiometricType> enrolled;
  final String? throwCode;
  final bool authResult;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> authenticate({required String localizedReason}) async {
    if (throwCode != null) {
      throw PlatformException(code: throwCode!, message: 'test $throwCode');
    }
    return authResult;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => enrolled;

  @override
  Future<AppLockAuthResult> authenticateDetailed({
    required String localizedReason,
  }) async {
    try {
      final ok = await authenticate(localizedReason: localizedReason);
      return AppLockAuthResult(
        ok: ok,
        failure: ok ? null : AppLockFailure.cancelled,
      );
    } on PlatformException catch (e) {
      return AppLockAuthResult(
        ok: false,
        failure: mapAuthException(e),
        detail: '${e.code}: ${e.message}',
      );
    }
  }
}

/// Pumps [screen] inside a minimal localized app with real (temp-dir)
/// Hive-backed providers (same shape as widget_test's pumpScreen).
Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required DatabaseService db,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        notificationServiceProvider
            .overrideWithValue(NotificationService()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: screen,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  group('v27.26 fingerprint: exception mapping', () {
    test('plugin codes map to specific failures', () {
      expect(mapAuthException(PlatformException(code: 'NotEnrolled')),
          AppLockFailure.notEnrolled);
      expect(mapAuthException(PlatformException(code: 'NotAvailable')),
          AppLockFailure.notAvailable);
      expect(mapAuthException(PlatformException(code: 'LockedOut')),
          AppLockFailure.lockedOut);
      expect(
          mapAuthException(
              PlatformException(code: 'PermanentlyLockedOut')),
          AppLockFailure.lockedOut);
      expect(
          mapAuthException(PlatformException(code: 'auth_in_progress')),
          AppLockFailure.busy);
      expect(mapAuthException(PlatformException(code: 'no_activity')),
          AppLockFailure.busy);
      expect(mapAuthException(PlatformException(code: 'SomethingElse')),
          AppLockFailure.unknown);
      expect(mapAuthException(StateError('boom')), AppLockFailure.unknown);
    });

    test('throwing client yields structured result with detail', () async {
      final svc = AppLockService(
          _ThrowingClient(throwCode: 'NotAvailable'));
      final r = await svc.authenticateDetailed(localizedReason: 'test');
      expect(r.ok, isFalse);
      expect(r.failure, AppLockFailure.notAvailable);
      expect(r.detail, contains('NotAvailable'));
    });

    test('empty enrolled biometrics is reported, success stays ok', () async {
      final empty = AppLockService(_ThrowingClient(enrolled: const []));
      expect(await empty.enrolledBiometrics(), isEmpty);
      final okSvc = AppLockService(_ThrowingClient(
          enrolled: const [BiometricType.fingerprint]));
      expect(await okSvc.enrolledBiometrics(),
          [BiometricType.fingerprint]);
      final r = await okSvc.authenticateDetailed(localizedReason: 'test');
      expect(r.ok, isTrue);
      expect(r.failure, isNull);
    });

    test('plain false without exception maps to cancelled', () async {
      final svc = AppLockService(_ThrowingClient(authResult: false));
      final r = await svc.authenticateDetailed(localizedReason: 'test');
      expect(r.ok, isFalse);
      expect(r.failure, AppLockFailure.cancelled);
    });
  });

  group('v27.26 fingerprint: wiring', () {
    test('service exposes detailed auth + enrolled precheck, gate uses it',
        () {
      final service =
          File('lib/core/app_lock/app_lock_service.dart').readAsStringSync();
      expect(service, contains('authenticateDetailed'));
      expect(service, contains('getAvailableBiometrics'));
      expect(service, contains('mapAuthException'));
      // No more swallowed errors in the production client.
      expect(service, isNot(contains('catch (_) {\n      return false;\n    }\n  }\n\n  @override\n  Future<AppLockAuthResult>')));
      final gate =
          File('lib/core/app_lock/app_lock_gate.dart').readAsStringSync();
      expect(gate, contains('authenticateDetailed'));
      expect(gate, contains('App lock unlock failed'));
      // Lock semantics unchanged: no disable from inside the lock screen.
      expect(gate, isNot(contains('appLockEnabled = false')));
    });

    test('profile toggle logs the exact failure and shows specifics', () {
      final profile =
          File('lib/features/profile/profile_screen.dart').readAsStringSync();
      expect(profile, contains('enrolledBiometrics()'));
      expect(profile, contains('authenticateDetailed'));
      expect(profile, contains('App lock enable failed'));
      expect(profile, contains('appLockNoBiometrics'));
      expect(profile, contains('appLockHardwareUnavailable'));
      expect(profile, contains('appLockLockedOut'));
      expect(profile, contains('appLockAuthCancelled'));
    });
  });

  group('v27.26 profile hub', () {
    late Directory tmp;
    late DatabaseService db;

    setUp(() async {
      tmp = Directory(
          '/tmp/df_v2726_${DateTime.now().microsecondsSinceEpoch}');
      tmp.createSync(recursive: true);
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
    });

    tearDown(() async {
      await Hive.close();
      tmp.deleteSync(recursive: true);
    });

    testWidgets('hub shows section titles, not the old long scroll',
        (tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpScreen(tester, const ProfileScreen(), db: db);
      // Hub menu titles (the old section words, kept).
      for (final title in [
        'التطبيق',
        'المظهر',
        'الملاحة التلقائية',
        'الإشعارات',
        'اللغة',
        'صيغة الوقت',
        'تفضيلات العمل',
        'المرتب',
        'إدارة البيانات',
        'عن DeliveryFlow',
        'نسخة المطور',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      // Section controls are NOT on the hub — they live in detail pages.
      expect(find.text('الوضع الداكن'), findsNothing);
      expect(find.text('الوضع الفاتح'), findsNothing);
      expect(find.text('قفل التطبيق بالبصمة'), findsNothing);
    });

    testWidgets('tapping appearance opens its detail screen with theme rows',
        (tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpScreen(tester, const ProfileScreen(), db: db);
      await tester.tap(find.text('المظهر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('الوضع الداكن'), findsOneWidget);
      expect(find.text('الوضع الفاتح'), findsOneWidget);
      expect(find.text('حسب النظام'), findsOneWidget);
      expect(find.text('اختار الثيم'), findsOneWidget);
      // Back returns to the hub.
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('المظهر'), findsOneWidget);
      expect(find.text('الوضع الداكن'), findsNothing);
    });

    testWidgets('theme reveal still works from the appearance screen',
        (tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpScreen(tester, const ProfileScreen(), db: db);
      await tester.tap(find.text('المظهر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        await tester.tap(find.text('الوضع الداكن'));
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (db.settings.themeMode == 2) break;
        }
      });
      expect(db.settings.themeMode, 2);
    });

    testWidgets('language and notifications detail screens hold their rows',
        (tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpScreen(tester, const ProfileScreen(), db: db);
      await tester.tap(find.text('اللغة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('العربية', skipOffstage: false), findsOneWidget);
      expect(find.text('English', skipOffstage: false), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('الإشعارات'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('تفعيل الإشعارات'), findsOneWidget);
      expect(find.text('تذكير الأوردرات اليومي'), findsOneWidget);
      expect(find.text('قفل التطبيق بالبصمة'), findsOneWidget);
    });

    testWidgets('about detail: contact rows stay one line, no stacking',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await _pumpScreen(tester, const ProfileScreen(), db: db);
      await tester.ensureVisible(find.text('عن DeliveryFlow'));
      await tester.pump();
      await tester.tap(find.text('عن DeliveryFlow'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      // Long Latin values render (truncated with ellipsis at paint level).
      expect(find.text('mohamed5946.github.io/portfolio'), findsOneWidget);
      expect(find.text('ma4670156@gmail.com'), findsOneWidget);
      // v27.26 regression: the old bug squeezed the label to ~0px wide
      // and stacked its letters vertically (label height 320px for a
      // short label). Both labels must stay single-line height.
      for (final label in ['الموقع الشخصي', 'البريد الإلكتروني']) {
        final box = tester.getSize(find.text(label));
        expect(box.height, lessThan(40), reason: label);
        expect(box.width, greaterThan(20), reason: label);
      }
    });

    test('hub wiring: every section id has a detail body', () {
      final profile =
          File('lib/features/profile/profile_screen.dart').readAsStringSync();
      for (final id in [
        '_quickLinksBody',
        '_appearanceBody',
        '_autoNavBody',
        '_notificationsBody',
        '_languageBody',
        '_timeFormatBody',
        '_workPrefsBody',
        '_salaryBody',
        '_dataBody',
        '_aboutBody',
        '_developerBody',
      ]) {
        expect(profile, contains(id), reason: id);
      }
      expect(profile, contains('_ProfileDetailPage'));
      // Value rows are bounded + single-line with ellipsis (the fix).
      expect(profile, contains('TextOverflow.ellipsis'));
    });
  });
}
