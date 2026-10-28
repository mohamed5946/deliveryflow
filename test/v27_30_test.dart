import 'dart:io';

import 'package:deliveryflow/core/app_lock/app_lock_service.dart';
import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/theme/staggered_entrance.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/onboarding/df_monogram.dart';
import 'package:deliveryflow/features/onboarding/splash_screen.dart';
import 'package:deliveryflow/features/profile/profile_screen.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

/// v27.30: DF-monogram splash entry + profile detail-row split-half fix.

Future<void> _pumpProfile(
  WidgetTester tester, {
  required DatabaseService db,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(NotificationService()),
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
        home: const ProfileScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Widget _splashApp(GoRouter router,
    {bool reduceMotion = false, ValueNotifier<bool>? gateOpen}) {
  return ProviderScope(
    overrides: [
      if (gateOpen != null) appLockGateOpenProvider.overrideWithValue(gateOpen),
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
      builder: reduceMotion
          ? (context, child) => MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: child!,
              )
          : null,
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

void main() {
  group('v27.30 splash stages', () {
    test('stages run in order: drawing, sweeping, name, exiting', () {
      // SUPERSEDED by v27.32: draw -> diagonal sweep -> name.
      expect(dfSplashStageFor(0.0), DfSplashStage.drawing);
      expect(dfSplashStageFor(0.39), DfSplashStage.drawing);
      expect(dfSplashStageFor(0.40), DfSplashStage.sweeping);
      expect(dfSplashStageFor(0.79), DfSplashStage.sweeping);
      expect(dfSplashStageFor(0.80), DfSplashStage.name);
      expect(dfSplashStageFor(0.99), DfSplashStage.name);
      expect(dfSplashStageFor(1.0), DfSplashStage.exiting);
    });

    test('total entry time is inside the 1-1.5s budget', () {
      // SUPERSEDED by v27.32: exactly 2500ms (draw 1000 + sweep
      // 1000 + name fade 500).
      expect(SplashScreen.totalDuration.inMilliseconds, 2500);
    });

    testWidgets('monogram draws, name appears, then home enters',
        (tester) async {
      await tester.pumpWidget(_splashApp(_splashRouter()));
      await tester.pump();
      // Exactly one entry sequence: one monogram, no loading bar/image.
      expect(find.byKey(const ValueKey('dfMonogram')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      // Name starts hidden and fades in after the fill.
      expect(
        tester.widget<Opacity>(find.byKey(const ValueKey('dfSplashName'))),
        isNotNull,
      );
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('dfSplashName')))
            .opacity,
        0.0,
      );
      await tester.pump(const Duration(milliseconds: 2100));
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('dfSplashName')))
            .opacity,
        greaterThan(0.0),
      );
      // Sequence completes and navigates to home on its own.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('home-screen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduce-motion: static mark, immediate entry', (tester) async {
      await tester.pumpWidget(
        _splashApp(_splashRouter(), reduceMotion: true),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('home-screen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locked: no animation runs until unlock, then it plays',
        (tester) async {
      final gateOpen = ValueNotifier<bool>(false);
      addTearDown(gateOpen.dispose);
      await tester.pumpWidget(
        _splashApp(_splashRouter(), gateOpen: gateOpen),
      );
      await tester.pump();
      // Lock-first: time passes, but nothing animates and no entry.
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.text('home-screen'), findsNothing);
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('dfSplashName')))
            .opacity,
        0.0,
      );
      // Fingerprint accepted -> gate opens -> animation starts now.
      gateOpen.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2100));
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('dfSplashName')))
            .opacity,
        greaterThan(0.0),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('home-screen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('v27.30 staggered list entrance', () {
    Widget staggerApp({bool reduceMotion = false}) {
      return MaterialApp(
        builder: reduceMotion
            ? (context, child) => MediaQuery(
                  data: const MediaQueryData(disableAnimations: true),
                  child: child!,
                )
            : null,
        home: Scaffold(
          body: StaggeredScope(
            child: Column(
              children: [
                for (var i = 0; i < 20; i++)
                  StaggeredItem(
                    index: i,
                    child: Text('item-$i'),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    double opacityOf(WidgetTester tester, String text) {
      final ancestor = find.ancestor(
        of: find.text(text),
        matching: find.byType(Opacity),
      );
      return tester.widget<Opacity>(ancestor.first).opacity;
    }

    test('delay is capped: item 19 does not wait 19 * 80ms', () {
      expect(StaggeredItem.delayFor(0), Duration.zero);
      expect(StaggeredItem.delayFor(3), const Duration(milliseconds: 240));
      expect(StaggeredItem.delayFor(7), const Duration(milliseconds: 560));
      expect(StaggeredItem.delayFor(19), const Duration(milliseconds: 560));
    });

    testWidgets('items stagger in order on entry', (tester) async {
      await tester.pumpWidget(staggerApp());
      await tester.pump();
      // Nothing visible at t=0.
      expect(opacityOf(tester, 'item-0'), 0.0);
      expect(opacityOf(tester, 'item-3'), 0.0);
      // Item 0's timer (0ms) fired; one more frame puts it mid-flight,
      // while item 3's timer (240ms) has not fired yet.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 50));
      expect(opacityOf(tester, 'item-0'), greaterThan(0.0));
      expect(opacityOf(tester, 'item-3'), 0.0);
      // Item 0 done; item 3 (started at 240ms) still mid-flight
      // (one extra frame after its timer fires for the value to show).
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 50));
      expect(opacityOf(tester, 'item-0'), 1.0);
      expect(opacityOf(tester, 'item-3'), lessThan(1.0));
      expect(opacityOf(tester, 'item-3'), greaterThan(0.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('long-list tail appears without cumulative delay',
        (tester) async {
      await tester.pumpWidget(staggerApp());
      await tester.pump();
      // Capped tail (560ms delay + 300ms) is fully in after the
      // timers fire plus one animation length; uncapped it would
      // need 19*80+300 = 1820ms.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacityOf(tester, 'item-19'), 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('re-entry replays the stagger', (tester) async {
      await tester.pumpWidget(staggerApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacityOf(tester, 'item-0'), 1.0);
      // Fresh scope = fresh entry: items start hidden again.
      // (A real unmount first: pumpWidget with an identical tree
      // reuses state, so it would NOT count as re-entry.)
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(staggerApp());
      await tester.pump();
      expect(opacityOf(tester, 'item-0'), 0.0);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacityOf(tester, 'item-0'), 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduce-motion shows items immediately', (tester) async {
      await tester.pumpWidget(staggerApp(reduceMotion: true));
      await tester.pump();
      // No animation wrappers in reduce-motion: items render directly.
      expect(find.text('item-0'), findsOneWidget);
      expect(find.text('item-19'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('v27.30 profile rows: split halves', () {
    late Directory tmp;
    late DatabaseService db;

    setUp(() async {
      tmp = Directory('/tmp/df_v2730_${DateTime.now().microsecondsSinceEpoch}');
      tmp.createSync(recursive: true);
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
    });

    tearDown(() async {
      await Hive.close();
      tmp.deleteSync(recursive: true);
    });

    testWidgets('about detail: label at start edge, value at end edge',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await _pumpProfile(tester, db: db);
      await tester.ensureVisible(find.text('عن DeliveryFlow'));
      await tester.pump();
      await tester.tap(find.text('عن DeliveryFlow'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);

      // RTL (ar locale): start edge is the RIGHT, end edge the LEFT.
      // Contact row: short value must sit at the far end, not mid-row.
      final labelRect = tester.getRect(find.text('للتواصل'));
      final valueRect = tester.getRect(find.text('01557887719'));
      // Single line, no stacking.
      expect(valueRect.height, lessThan(40));
      expect(labelRect.height, lessThan(40));
      // Clear separation: label and value do not meet mid-row; the
      // value's far edge is well past the screen middle.
      expect(valueRect.left, lessThan(200));
      expect(labelRect.right, greaterThan(200));
      expect(labelRect.left, greaterThan(valueRect.right));
      // The row is split into two halves: label on the start half,
      // value on the end half (test screen is 360pt wide, middle 180).
      expect(labelRect.right, greaterThan(200));
      expect(valueRect.left, lessThan(200));

      // Long Latin value still truncates on one line, no overflow.
      expect(find.text('mohamed5946.github.io/portfolio'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
