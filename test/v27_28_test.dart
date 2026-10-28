import 'dart:io';

import 'package:deliveryflow/core/app_lock/app_lock_gate.dart';
import 'package:deliveryflow/core/app_lock/app_lock_service.dart';
import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:deliveryflow/theme/bin_eating_delete_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:local_auth/local_auth.dart';

/// Scripted OS client: returns the scripted results in order, counting
/// calls so double-fires and retries are observable.
class _ScriptedClient implements AppLockAuthClient {
  _ScriptedClient(this._script);

  final List<AppLockAuthResult> _script;
  int calls = 0;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [];

  @override
  Future<bool> authenticate({required String localizedReason}) async {
    return (await authenticateDetailed(localizedReason: localizedReason)).ok;
  }

  @override
  Future<AppLockAuthResult> authenticateDetailed({
    required String localizedReason,
  }) async {
    final i = calls < _script.length ? calls : _script.length - 1;
    calls++;
    return _script[i];
  }
}

AppLockAuthResult _ok() => const AppLockAuthResult(ok: true);

AppLockAuthResult _fail(AppLockFailure f) =>
    AppLockAuthResult(ok: false, failure: f);

Future<void> _pumpGate(
  WidgetTester tester, {
  required DatabaseService db,
  required AppLockService service,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        notificationServiceProvider
            .overrideWithValue(NotificationService()),
        appLockServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AppLockGate(
          child: Text('UNLOCKED', key: Key('appContent')),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('v27.28 gate: resumed-after-auth must not re-lock', () {
    late Directory tmp;
    late DatabaseService db;

    setUp(() async {
      tmp = Directory(
          '/tmp/df_v2728_${DateTime.now().microsecondsSinceEpoch}');
      tmp.createSync(recursive: true);
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
      await db.saveSettings(UserSettings()
        ..appLockEnabled = true
        ..registered = true
        ..onboardingDone = true);
    });

    tearDown(() async {
      await Hive.close();
      tmp.deleteSync(recursive: true);
    });

    testWidgets('cold start auto-prompts once and unlocks', (tester) async {
      final client = _ScriptedClient([_ok()]);
      await _pumpGate(tester, db: db, service: AppLockService(client));
      await tester.pump(const Duration(milliseconds: 100));
      expect(client.calls, 1);
      expect(find.text('التطبيق مقفول'), findsNothing);
      expect(find.byKey(const Key('appContent')), findsOneWidget);
    });

    testWidgets('resumed noise after a success does NOT re-lock',
        (tester) async {
      final client = _ScriptedClient([_ok()]);
      await _pumpGate(tester, db: db, service: AppLockService(client));
      expect(find.text('التطبيق مقفول'), findsNothing);
      // The prompt-dismissal resumed event: no backgrounding happened.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(client.calls, 1);
      expect(find.text('التطبيق مقفول'), findsNothing);
    });

    testWidgets('no auto-prompt before the resumed event after background',
        (tester) async {
      final client = _ScriptedClient([_ok(), _ok()]);
      await _pumpGate(tester, db: db, service: AppLockService(client));
      expect(client.calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      // While paused the framework itself disables frames, so nothing
      // can render or fire yet — the lock only materialises on resume.
      expect(client.calls, 1);
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      // First resumed frame: lock screen appears, but the auto-prompt is
      // only armed by this frame's post-frame callback, so it has NOT
      // fired yet.
      expect(find.text('التطبيق مقفول'), findsOneWidget);
      expect(client.calls, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(client.calls, 2);
      expect(find.text('التطبيق مقفول'), findsNothing);
    });

    testWidgets('busy failure retries once automatically and then unlocks',
        (tester) async {
      final client = _ScriptedClient(
          [_fail(AppLockFailure.busy), _ok()]);
      await _pumpGate(tester, db: db, service: AppLockService(client));
      await tester.pump(const Duration(milliseconds: 500));
      expect(client.calls, 2);
      expect(find.text('التطبيق مقفول'), findsNothing);
    });

    testWidgets('lock screen shows the specific failure reason',
        (tester) async {
      final client = _ScriptedClient([_fail(AppLockFailure.lockedOut)]);
      await _pumpGate(tester, db: db, service: AppLockService(client));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('التطبيق مقفول'), findsOneWidget);
      // The locked-out message, not the generic line.
      expect(find.textContaining('اتقفلت مؤقتًا'), findsOneWidget);
      expect(find.text('التحقق فشل، حاول تاني'), findsNothing);
    });
  });

  group('v27.28 gate: wiring guards', () {
    test('re-lock requires a backgrounding; auto-prompt is armed', () {
      final gate = File('lib/core/app_lock/app_lock_gate.dart').readAsStringSync();
      expect(gate, contains('_wentBackground'));
      expect(gate, contains('_autoPromptArmed'));
      expect(gate, contains('_failureText'));
      expect(gate, contains('AppLockFailure.busy'));
      // Lock semantics unchanged: no disable from inside the lock screen.
      expect(gate, isNot(contains('appLockEnabled = false')));
      // v27.27 fix stays: FragmentActivity superclass untouched.
      final main = File(
              'android/app/src/main/kotlin/com/valor/deliveryflow/MainActivity.kt')
          .readAsStringSync();
      expect(main, contains('FlutterFragmentActivity'));
    });
  });

  group('v27.28 bin delete: lid → flight → lid → check → once', () {
    Future<void> pumpBin(
      WidgetTester tester, {
      required VoidCallback onConfirmed,
      bool disableAnimations = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(disableAnimations: disableAnimations),
              child: Center(
                child: BinEatingDeleteButton(
                  label: 'Delete',
                  onConfirmed: onConfirmed,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('sequence stages in order, completion fires once',
        (tester) async {
      var confirmed = 0;
      await pumpBin(tester, onConfirmed: () => confirmed++);
      final firstCenter =
          tester.getCenter(find.byKey(const Key('binLetter_0')));
      final idleLidCenter =
          tester.getCenter(find.byKey(const Key('binLid')));
      await tester.tap(find.byType(BinEatingDeleteButton));
      // Settle pump: tap's onTap fires on the next frame, so the
      // controller starts here; later pumps then measure real time.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Stage 1: lid visibly lifted straight up (center above idle).
      expect(
        tester.getCenter(find.byKey(const Key('binLid'))).dy,
        lessThan(idleLidCenter.dy - 2),
      );
      // Stage 2: first letter has travelled toward the bin (LTR: +x).
      await tester.pump(const Duration(milliseconds: 400));
      final midCenter =
          tester.getCenter(find.byKey(const Key('binLetter_0')));
      expect(midCenter.dx, greaterThan(firstCenter.dx));
      // Stage 3: lid coming back down once letters are inside
      // (t = 1100 ms is inside the 0.70 → 0.82 close window: below the
      // raised position, above the idle rim; full close coincides with
      // the check replacing the bin, asserted in stage 4).
      await tester.pump(const Duration(milliseconds: 600));
      final closingLidCenter =
          tester.getCenter(find.byKey(const Key('binLid')));
      expect(closingLidCenter.dy, lessThan(idleLidCenter.dy));
      expect(closingLidCenter.dy, greaterThan(idleLidCenter.dy - 14));
      // Stage 4: success check appears and draws.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('binSuccessCheck')), findsOneWidget);
      // Stage 5: completion exactly once, never again on later pumps.
      await tester.pump(const Duration(milliseconds: 500));
      expect(confirmed, 1);
      await tester.pump(const Duration(milliseconds: 500));
      expect(confirmed, 1);
    });

    testWidgets('reduce-motion skips the animation and completes at once',
        (tester) async {
      var confirmed = 0;
      await pumpBin(tester,
          onConfirmed: () => confirmed++, disableAnimations: true);
      await tester.tap(find.byType(BinEatingDeleteButton));
      await tester.pump();
      expect(confirmed, 1);
      expect(find.byKey(const Key('binSuccessCheck')), findsNothing);
    });
  });
}
