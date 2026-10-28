import 'dart:io';

import 'package:deliveryflow/core/app_lock/app_lock_service.dart';
import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/onboarding/df_monogram.dart';
import 'package:deliveryflow/features/onboarding/splash_screen.dart';
import 'package:deliveryflow/features/profile/profile_screen.dart';
import 'package:deliveryflow/features/schedule/schedule_screen.dart';
import 'package:deliveryflow/features/weekly_reports/report_screen.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:deliveryflow/theme/staggered_entrance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

/// v27.31: combined DF monogram (white D, blue F inside its bowl) +
/// staggered entrance everywhere with replay on every entry (incl.
/// tab switches) + profile hub separate cards.

Widget _splashApp(GoRouter router, {ValueNotifier<bool>? gateOpen}) {
  return ProviderScope(
    overrides: [
      if (gateOpen != null)
        appLockGateOpenProvider.overrideWithValue(gateOpen),
    ],
    child: MaterialApp.router(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    ),
  );
}

GoRouter _splashRouter() {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('home-screen'))),
      ),
    ],
  );
}

Future<void> _pumpDbScreen(
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
  await tester.pump(const Duration(milliseconds: 1000));
}

void main() {
  group('v27.31 combined DF monogram', () {
    test('F sits geometrically inside the D bowl (strict margins)', () {
      final d = monogramDPath().getBounds();
      final f = monogramFPath().getBounds();
      expect(d.isEmpty, isFalse);
      expect(f.isEmpty, isFalse);
      // Strictly inside on all four sides, with real margin.
      expect(f.left, greaterThan(d.left + 4));
      expect(f.right, lessThan(d.right - 4));
      expect(f.top, greaterThan(d.top + 4));
      expect(f.bottom, lessThan(d.bottom - 4));
    });

    test('splash stages still run in order with the new mark', () {
      expect(dfSplashStageFor(0.0), DfSplashStage.drawing);
      expect(dfSplashStageFor(0.55), DfSplashStage.drawing);
      expect(dfSplashStageFor(0.56), DfSplashStage.filling);
      expect(dfSplashStageFor(0.79), DfSplashStage.filling);
      expect(dfSplashStageFor(0.80), DfSplashStage.name);
      expect(dfSplashStageFor(0.91), DfSplashStage.name);
      expect(dfSplashStageFor(0.92), DfSplashStage.exiting);
      expect(dfSplashStageFor(1.0), DfSplashStage.exiting);
    });

    test('total entry time still inside the 1-1.5s budget', () {
      expect(SplashScreen.totalDuration.inMilliseconds,
          greaterThanOrEqualTo(1000));
      expect(SplashScreen.totalDuration.inMilliseconds,
          lessThanOrEqualTo(1500));
    });

    testWidgets('combined mark renders, name appears, home enters',
        (tester) async {
      await tester.pumpWidget(_splashApp(_splashRouter()));
      await tester.pump();
      // Exactly one mark, no side-by-side second mark.
      expect(find.byKey(const ValueKey('dfMonogram')), findsOneWidget);
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('dfSplashName')))
            .opacity,
        0.0,
      );
      await tester.pump(const Duration(milliseconds: 1100));
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('dfSplashName')))
            .opacity,
        greaterThan(0.0),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('home-screen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lock-first ordering still holds with the new mark',
        (tester) async {
      final gateOpen = ValueNotifier<bool>(false);
      addTearDown(gateOpen.dispose);
      await tester.pumpWidget(
        _splashApp(_splashRouter(), gateOpen: gateOpen),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.text('home-screen'), findsNothing);
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('dfSplashName')))
            .opacity,
        0.0,
      );
      gateOpen.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('dfSplashName')))
            .opacity,
        greaterThan(0.0),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('home-screen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('v27.31 tab replay', () {
    tearDown(() {
      currentTabIndexNotifier.value = 0;
    });

    double opacityOf(WidgetTester tester, String text) {
      final ancestor = find.ancestor(
        of: find.text(text),
        matching: find.byType(Opacity),
      );
      return tester.widget<Opacity>(ancestor.first).opacity;
    }

    Widget replayApp() {
      return MaterialApp(
        home: Scaffold(
          body: TabReplayScope(
            tabIndex: 0,
            child: StaggeredScope(
              child: Column(
                children: [
                  for (var i = 0; i < 5; i++)
                    StaggeredItem(
                      index: i,
                      child: Text('tab-item-$i'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('tab re-selection replays the stagger', (tester) async {
      currentTabIndexNotifier.value = 0;
      await tester.pumpWidget(replayApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      // Timer fires after the frame of the advancing pump, so one
      // extra frame is needed before the value lands (same pattern
      // as the v27.30 stagger tests).
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacityOf(tester, 'tab-item-0'), 1.0);
      // Leave the tab and come back: the entrance must replay.
      currentTabIndexNotifier.value = 1;
      await tester.pump();
      currentTabIndexNotifier.value = 0;
      await tester.pump();
      // Replaying: item 0 starts hidden again.
      expect(opacityOf(tester, 'tab-item-0'), lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 1000));
      // Timer fires after the frame of the advancing pump, so one
      // extra frame is needed before the value lands (same pattern
      // as the v27.30 stagger tests).
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacityOf(tester, 'tab-item-0'), 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('100 rapid re-entries replay every time', (tester) async {
      currentTabIndexNotifier.value = 0;
      await tester.pumpWidget(replayApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      // Timer fires after the frame of the advancing pump, so one
      // extra frame is needed before the value lands (same pattern
      // as the v27.30 stagger tests).
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacityOf(tester, 'tab-item-0'), 1.0);
      for (var n = 0; n < 100; n++) {
        currentTabIndexNotifier.value = 1;
        await tester.pump();
        currentTabIndexNotifier.value = 0;
        await tester.pump();
        // Every single re-entry restarts the entrance.
        expect(opacityOf(tester, 'tab-item-0'), lessThan(1.0));
        await tester.pump(const Duration(milliseconds: 1000));
        await tester.pump(const Duration(milliseconds: 400));
        expect(opacityOf(tester, 'tab-item-0'), 1.0);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('data refresh on the same generation does not replay',
        (tester) async {
      currentTabIndexNotifier.value = 0;
      await tester.pumpWidget(replayApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      // Timer fires after the frame of the advancing pump, so one
      // extra frame is needed before the value lands (same pattern
      // as the v27.30 stagger tests).
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacityOf(tester, 'tab-item-0'), 1.0);
      // A plain rebuild (same tab, same generation) must NOT restart.
      await tester.pumpWidget(replayApp());
      await tester.pump();
      expect(opacityOf(tester, 'tab-item-0'), 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduce-motion still shows items immediately',
        (tester) async {
      currentTabIndexNotifier.value = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: TabReplayScope(
              tabIndex: 0,
              child: StaggeredScope(
                child: Column(
                  children: [
                    for (var i = 0; i < 5; i++)
                      StaggeredItem(
                        index: i,
                        child: Text('rm-item-$i'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('rm-item-0'), findsOneWidget);
      expect(find.text('rm-item-4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('v27.31 hub separate cards + staggered screens', () {
    late Directory tmp;
    late DatabaseService db;

    setUp(() async {
      tmp = Directory(
          '/tmp/df_v2731_${DateTime.now().microsecondsSinceEpoch}');
      tmp.createSync(recursive: true);
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
    });

    tearDown(() async {
      await Hive.close();
      tmp.deleteSync(recursive: true);
      currentTabIndexNotifier.value = 0;
    });

    testWidgets('hub renders 11 separate cards, tap opens detail',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await _pumpDbScreen(tester, const ProfileScreen(), db: db);
      // One distinct card per section — not one container of rows.
      const sections = [
        'quick',
        'appearance',
        'autoNav',
        'notifications',
        'language',
        'timeFormat',
        'workPrefs',
        'salary',
        'data',
        'about',
        'developer',
      ];
      for (final s in sections) {
        expect(
          find.byKey(ValueKey('hubCard-$s')),
          findsOneWidget,
          reason: 'missing separate hub card for $s',
        );
      }
      // Tapping a card still opens its detail screen.
      await tester.ensureVisible(find.text('عن DeliveryFlow'));
      await tester.pump();
      await tester.tap(find.text('عن DeliveryFlow'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.text('01557887719'), findsOneWidget);
    });

    testWidgets('weekly schedule day cards stagger in', (tester) async {
      await _pumpDbScreen(tester, const ScheduleScreen(), db: db);
      expect(find.byType(StaggeredItem), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('report section cards stagger in', (tester) async {
      await _pumpDbScreen(tester, const ReportScreen(), db: db);
      expect(find.byType(StaggeredItem), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
