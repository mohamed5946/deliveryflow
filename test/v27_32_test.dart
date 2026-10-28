import 'package:deliveryflow/core/app_lock/app_lock_service.dart';
import 'package:deliveryflow/features/onboarding/df_monogram.dart';
import 'package:deliveryflow/features/onboarding/splash_screen.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// v27.32: splash rebuilt to match the reference video's actual
/// motion (v27.31's instant outline -> solid switch + popping F was
/// judged "very very very bad compared to the video"):
/// thin outline with glowing tip dot + anchor dots -> diagonal sweep
/// (bottom-left to top-right) progressively revealing the solid white
/// D and the blue F together -> final mark on near-black -> name
/// fade -> home. TOTAL exactly 2500ms (Mohamed's correction,
/// superseding the 2000ms note): draw 1000 + sweep 1000 + name 500.

Widget _splashApp(GoRouter router,
    {ValueNotifier<bool>? gateOpen, bool reduceMotion = false}) {
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
  group('v27.32 diagonal-sweep splash', () {
    test('stages run in order: drawing, sweeping, name, exiting', () {
      expect(dfSplashStageFor(0.0), DfSplashStage.drawing);
      expect(dfSplashStageFor(0.39), DfSplashStage.drawing);
      expect(dfSplashStageFor(0.40), DfSplashStage.sweeping);
      expect(dfSplashStageFor(0.79), DfSplashStage.sweeping);
      expect(dfSplashStageFor(0.80), DfSplashStage.name);
      expect(dfSplashStageFor(0.99), DfSplashStage.name);
      expect(dfSplashStageFor(1.0), DfSplashStage.exiting);
    });

    test('total entry duration is EXACTLY 2500ms', () {
      expect(SplashScreen.totalDuration, const Duration(milliseconds: 2500));
      expect(SplashScreen.totalDuration.inMilliseconds, 2500);
    });

    test('F sits geometrically inside the D bowl (strict margins)', () {
      final d = monogramDPath().getBounds();
      final f = monogramFPath().getBounds();
      expect(d.isEmpty, isFalse);
      expect(f.isEmpty, isFalse);
      expect(f.left, greaterThan(d.left + 4));
      expect(f.right, lessThan(d.right - 4));
      expect(f.top, greaterThan(d.top + 4));
      expect(f.bottom, lessThan(d.bottom - 4));
    });

    test('anchor dots sit on the D path bounds', () {
      final d = monogramDPath().getBounds();
      for (final a in monogramAnchorPoints()) {
        expect(a.dx, greaterThanOrEqualTo(d.left));
        expect(a.dx, lessThanOrEqualTo(d.right));
        expect(a.dy, greaterThanOrEqualTo(d.top));
        expect(a.dy, lessThanOrEqualTo(d.bottom));
      }
    });

    test('sweep travels bottom-left to top-right', () {
      expect(sweepFrontFor(0.0), -160);
      expect(sweepFrontFor(1.0), 160);
      expect(sweepFrontFor(0.5), 0);
      expect(sweepFrontFor(0.25), lessThan(sweepFrontFor(0.75)));
    });

    test('F is revealed ONLY via the sweep, progressively', () {
      // Bottom-left end of the F stem: x - y == -56.
      const fBottom = Offset(62, 118);
      // Top-right end of the F top bar: x - y == 62.
      const fTop = Offset(112, 50);
      // Before the sweep, no part of the F is revealed.
      expect(sweepReveals(0.0, fBottom), isFalse);
      expect(sweepReveals(0.0, fTop), isFalse);
      // Mid-sweep the bottom-left part has emerged but the
      // top-right part has not: the F is never a pop-in.
      expect(sweepReveals(0.5, fBottom), isTrue);
      expect(sweepReveals(0.5, fTop), isFalse);
      // After the sweep completes, the whole F is revealed.
      expect(sweepReveals(1.0, fBottom), isTrue);
      expect(sweepReveals(1.0, fTop), isTrue);
    });

    testWidgets('mark renders at every sweep stage without error',
        (tester) async {
      for (final sweep in [0.0, 0.5, 1.0]) {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: DfMonogram(
                  drawProgress: 1.0,
                  sweepProgress: 0.5,
                  fillBlue: Colors.blue,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(DfMonogram), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Rebuild with this stage's sweep value too.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: DfMonogram(
                  drawProgress: 1.0,
                  sweepProgress: sweep,
                  fillBlue: Colors.blue,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('splash: near-black bg, name fades in, home at 2500ms',
        (tester) async {
      await tester.pumpWidget(_splashApp(_splashRouter()));
      await tester.pump();
      expect(find.byKey(const ValueKey('dfMonogram')), findsOneWidget);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        const Color(0xFF0A0A0A),
      );
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('dfSplashName')))
            .opacity,
        0.0,
      );
      // Draw (1000ms) + sweep (1000ms) done; name fade is running.
      await tester.pump(const Duration(milliseconds: 2100));
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('dfSplashName')))
            .opacity,
        greaterThan(0.0),
      );
      // Exactly at the 2500ms total, home enters.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('home-screen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lock-first ordering holds with the new animation',
        (tester) async {
      final gateOpen = ValueNotifier<bool>(false);
      addTearDown(gateOpen.dispose);
      await tester.pumpWidget(
        _splashApp(_splashRouter(), gateOpen: gateOpen),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3000));
      expect(find.text('home-screen'), findsNothing);
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('dfSplashName')))
            .opacity,
        0.0,
      );
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

    testWidgets('reduce-motion: static final mark, immediate entry',
        (tester) async {
      await tester.pumpWidget(
        _splashApp(_splashRouter(), reduceMotion: true),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('home-screen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
