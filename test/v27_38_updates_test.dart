import 'dart:async';
import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/core/update/app_update.dart';
import 'package:deliveryflow/core/update/app_update_flow.dart';
import 'package:deliveryflow/core/update/updates_screen.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:deliveryflow/theme/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v27.38: Updates row + Updates screen, replacing the v27.37
/// standalone bottom button whose dialog-based check blanked the
/// screen (field report 2026-10-30).
///
/// Root cause (reproduced in a throwaway widget test before the
/// fix, then removed with the buggy code): the v27.37 manual check
/// dismissed its progress dialog with an unconditional
/// Navigator.pop(). barrierDismissible:false does NOT block
/// Android's system Back button — so a Back press during the check
/// left the dialog already gone when the fetch returned, and the
/// blind pop removed the page underneath, leaving an empty
/// navigator = blank black screen. These tests pin the fixed
/// behavior: loading lives inside the Updates screen, results that
/// arrive after the screen is gone are ignored, and nothing is ever
/// popped blindly.

class _FakeInstaller implements AppUpdateInstaller {
  @override
  Future<bool> canInstallUnknownApps() async => true;
  @override
  Future<void> openUnknownAppsSettings() async {}
  @override
  Future<void> installApk(File _) async {}
}

AppUpdateManifest _manifest({required int code}) => AppUpdateManifest(
      versionCode: code,
      versionName: '27.38.0',
      changelog: 'This update provides fixes for DeliveryFlow.',
      apkUrl: 'https://example.invalid/app-release.apk',
      apkSha256: 'abc',
      apkSizeBytes: 0,
    );

/// fetchManifest gated by a Completer (or failing on demand) so
/// tests can observe the loading state and the back-during-check
/// path. Download/install are never triggered by these tests.
class _GatedUpdateService extends AppUpdateService {
  _GatedUpdateService({this.gate, this.failure})
      : super(installer: _FakeInstaller());

  final Completer<AppUpdateManifest>? gate;
  final String? failure;

  @override
  Future<AppUpdateManifest> fetchManifest() async {
    if (failure != null) throw AppUpdateException(failure!);
    return gate!.future;
  }
}

Future<AppUpdateFlow> _flow(AppUpdateService service) async {
  final prefs = await SharedPreferences.getInstance();
  return AppUpdateFlow(service: service, prefs: prefs);
}

/// Real Hive-backed settings (temp dir) so GlassScaffold's
/// AuroraBackground can read themePreset — the established pattern
/// from the v27.33 screen tests. Without this override the settings
/// provider throws UnimplementedError in widget tests.
Future<DatabaseService> _tempDb(WidgetTester tester) async {
  late Directory tmp;
  late DatabaseService db;
  // Hive/dart:io init deadlocks under the test binding's fake async
  // unless run in real async — the established v27.33 pattern.
  await tester.runAsync(() async {
    tmp = await Directory.systemTemp.createTemp('df_v2738_');
    db = DatabaseService();
    await db.init(hivePath: tmp.path);
  });
  addTearDown(() => tester.runAsync(() async {
        await Hive.close();
        await tmp.delete(recursive: true);
      }));
  return db;
}

List<Override> _settingsOverrides(DatabaseService db) => [
      settingsProvider.overrideWith(
        (ref) => SettingsNotifier(db, NotificationService()),
      ),
    ];

Future<void> _pumpUpdatesScreen(
  WidgetTester tester, {
  required AppUpdateService service,
  required DatabaseService db,
  AppUpdateFlow? flow,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _settingsOverrides(db),
      child: MaterialApp(
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
          body: UpdatesScreen(
            service: service,
            flow: flow ?? await _flow(service),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Installed build 70 ("27.37.0"), so manifest 70 = up to date
  // and 71 = a newer version.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/package_info'),
    (call) async {
      if (call.method == 'getAll') {
        return <String, dynamic>{
          'appName': 'DeliveryFlow',
          'packageName': 'com.valor.deliveryflow',
          'version': '27.37.0',
          'buildNumber': '70',
        };
      }
      return null;
    },
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Updates screen (v27.38)', () {
    testWidgets('renders version, auto-check toggle, check button',
        (tester) async {
      final db = await _tempDb(tester);
      final service = _GatedUpdateService(gate: Completer());
      await _pumpUpdatesScreen(tester, service: service, db: db);
      expect(find.text('Updates'), findsOneWidget);
      expect(find.text('Current version'), findsOneWidget);
      expect(find.text('27.37.0 (70)'), findsOneWidget);
      expect(find.text('Automatic Updates'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('updates-auto-check-switch')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('updates-check-button')),
        findsOneWidget,
      );
      expect(find.text('Check for updates'), findsOneWidget);
    });

    testWidgets('check shows loading first, then up-to-date (never blank)',
        (tester) async {
      final db = await _tempDb(tester);
      final gate = Completer<AppUpdateManifest>();
      final service = _GatedUpdateService(gate: gate);
      await _pumpUpdatesScreen(tester, service: service, db: db);
      await tester.tap(find.byKey(const ValueKey('updates-check-button')));
      await tester.pump();
      // Loading lives INSIDE the screen: spinner + text, and the
      // screen chrome (Scaffold + version) is still there.
      expect(
        find.byKey(const ValueKey('updates-checking-indicator')),
        findsOneWidget,
      );
      expect(find.text('Checking for updates…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Scaffold), findsWidgets);
      gate.complete(_manifest(code: 70));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('updates-up-to-date')),
        findsOneWidget,
      );
      expect(find.text("You're on the latest update"), findsOneWidget);
      expect(
        find.text('You already have the latest version of DeliveryFlow.'),
        findsOneWidget,
      );
      expect(find.text('27.37.0 (70)'), findsWidgets);
    });

    testWidgets('check with a newer version opens the iOS update screen',
        (tester) async {
      final db = await _tempDb(tester);
      final gate = Completer<AppUpdateManifest>();
      final service = _GatedUpdateService(gate: gate);
      await _pumpUpdatesScreen(tester, service: service, db: db);
      await tester.tap(find.byKey(const ValueKey('updates-check-button')));
      await tester.pump();
      gate.complete(_manifest(code: 71));
      await tester.pumpAndSettle();
      expect(find.text('Software Update'), findsOneWidget);
      expect(find.text('DeliveryFlow 27.38.0'), findsOneWidget);
      expect(find.text('Update Now'), findsOneWidget);
    });

    testWidgets('check failure shows a loud dialog with the exact reason',
        (tester) async {
      final db = await _tempDb(tester);
      final service = _GatedUpdateService(failure: 'boom reason');
      await _pumpUpdatesScreen(tester, service: service, db: db);
      await tester.tap(find.byKey(const ValueKey('updates-check-button')));
      await tester.pumpAndSettle();
      expect(find.text('Update failed'), findsOneWidget);
      expect(find.text('boom reason'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('updates-up-to-date')),
        findsNothing,
      );
    });

    testWidgets(
        'back during a check never pops the page underneath (no black screen)',
        (tester) async {
      final db = await _tempDb(tester);
      final gate = Completer<AppUpdateManifest>();
      final service = _GatedUpdateService(gate: gate);
      final flow = await _flow(service);
      await tester.pumpWidget(
        ProviderScope(
          overrides: _settingsOverrides(db),
          child: MaterialApp(
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
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    key: const ValueKey('repro-home-button'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => UpdatesScreen(
                          service: service,
                          flow: flow,
                        ),
                      ),
                    ),
                    child: const Text('HOME PAGE'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('repro-home-button')));
      await tester.pumpAndSettle();
      expect(find.text('Updates'), findsOneWidget);
      // Start a check, then press system Back mid-check: the Updates
      // screen goes away and the home page is back on top.
      await tester.tap(find.byKey(const ValueKey('updates-check-button')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('updates-checking-indicator')),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('HOME PAGE'), findsOneWidget);
      // The late fetch result must be ignored: the home page stays
      // put, nothing is popped, no black screen.
      gate.complete(_manifest(code: 71));
      await tester.pumpAndSettle();
      expect(find.text('HOME PAGE'), findsOneWidget);
      expect(find.text('Software Update'), findsNothing);
    });

    testWidgets('automatic-updates toggle persists', (tester) async {
      final db = await _tempDb(tester);
      final service = _GatedUpdateService(gate: Completer());
      await _pumpUpdatesScreen(tester, service: service, db: db);
      final switchFinder =
          find.byKey(const ValueKey('updates-auto-check-switch'));
      expect(tester.widget<Switch>(switchFinder).value, isTrue);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(switchFinder).value, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppUpdateFlow.autoCheckKey), isFalse);
    });
  });

  group('Updates settings row (v27.38)', () {
    testWidgets(
        'row looks like its siblings and navigates to the Updates screen',
        (tester) async {
      final db = await _tempDb(tester);
      final service = _GatedUpdateService(gate: Completer());
      final flow = await _flow(service);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: Center(child: UpdatesHubRow()),
            ),
          ),
          GoRoute(
            path: '/updates',
            builder: (context, state) => UpdatesScreen(
              service: service,
              flow: flow,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: _settingsOverrides(db),
          child: MaterialApp.router(
            theme: AppTheme.light(),
            locale: const Locale('en'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Sibling-row shape: icon + label + chevron, NOT a button.
      expect(find.byIcon(Icons.system_update_rounded), findsOneWidget);
      expect(find.text('Updates'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.byType(GlassButton), findsNothing);
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      expect(find.text('Check for updates'), findsOneWidget);
      expect(find.text('Current version'), findsOneWidget);
    });
  });
}
