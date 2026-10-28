import 'dart:ui' as ui;

import 'package:deliveryflow/theme/app_theme.dart';
import 'package:deliveryflow/theme/theme_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _testImage(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 100, 100),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  return picture.toImage(100, 100);
}

/// Pumps a minimal app whose overlay watches the provider controller,
/// and returns that controller.
Future<ThemeRevealController> _pumpOverlayApp(WidgetTester tester) async {
  late ThemeRevealController controller;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              controller = ref.read(themeRevealControllerProvider);
              return const ThemeRevealOverlay();
            },
          ),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  group('v27.25 circular-reveal theme switch', () {
    test('max radius covers the farthest corner from the origin', () {
      expect(
        themeRevealMaxRadius(const Size(400, 800), const Offset(100, 200)),
        closeTo(670.82, 0.01),
      );
      expect(
        themeRevealMaxRadius(const Size(400, 800), Offset.zero),
        closeTo(894.43, 0.01),
      );
    });

    test('clipper reclips when centre or radius changes', () {
      const a = CircleRevealClipper(center: Offset(10, 10), radius: 5);
      const b = CircleRevealClipper(center: Offset(10, 10), radius: 6);
      const c = CircleRevealClipper(center: Offset(11, 10), radius: 5);
      expect(a.shouldReclip(b), isTrue);
      expect(a.shouldReclip(c), isTrue);
      expect(a.shouldReclip(a), isFalse);
    });

    test('controller: second begin while busy is ignored', () {
      final controller = ThemeRevealController();
      expect(
        controller.begin(origin: const Offset(10, 20), isToDark: true),
        isTrue,
      );
      expect(controller.busy, isTrue);
      expect(controller.origin, const Offset(10, 20));
      expect(controller.isToDark, isTrue);
      // Second tap inside the animation window: ignored, first wins.
      expect(
        controller.begin(origin: const Offset(99, 99), isToDark: false),
        isFalse,
      );
      expect(controller.origin, const Offset(10, 20));
      expect(controller.isToDark, isTrue);
      controller.reset();
      expect(controller.busy, isFalse);
      expect(controller.oldImage, isNull);
      expect(controller.newImage, isNull);
    });

    test('system mode still resolves to ThemeMode.system (native OS '
        'brightness following is untouched)', () {
      expect(AppTheme.themeModeFromInt(0), ThemeMode.system);
      expect(AppTheme.themeModeFromInt(1), ThemeMode.light);
      expect(AppTheme.themeModeFromInt(2), ThemeMode.dark);
    });

    testWidgets('reveal persists only after the animation finishes, '
        'with the circle growing for to-dark', (tester) async {
      final controller = await _pumpOverlayApp(tester);
      var persistCount = 0;
      var overrideSets = 0;
      var overrideClears = 0;
      final future = performThemeReveal(
        controller: controller,
        origin: const Offset(50, 50),
        isToDark: true,
        targetTheme: ThemeData.dark(),
        animationsDisabled: false,
        capture: () async => _testImage(const Color(0xFFFFFFFF)),
        setOverride: (_) => overrideSets++,
        clearOverride: () => overrideClears++,
        persist: () async => persistCount++,
      );
      await tester.pump();
      await tester.pump();
      // Before the animation finishes, nothing is persisted.
      expect(persistCount, 0);
      expect(controller.phase, ThemeRevealPhase.animating);
      expect(controller.isToDark, isTrue);
      expect(find.byType(ClipPath), findsOneWidget);
      expect(find.byType(RawImage), findsNWidgets(2));
      await tester.pumpAndSettle();
      await future;
      expect(persistCount, 1);
      expect(overrideSets, 1);
      expect(overrideClears, 1);
      expect(controller.phase, ThemeRevealPhase.idle);
    });

    testWidgets('reveal to light runs reversed and a second tap during '
        'the run persists only once', (tester) async {
      final controller = await _pumpOverlayApp(tester);
      var persistCount = 0;
      final future = performThemeReveal(
        controller: controller,
        origin: const Offset(30, 30),
        isToDark: false,
        targetTheme: ThemeData.light(),
        animationsDisabled: false,
        capture: () async => _testImage(const Color(0xFF000000)),
        setOverride: (_) {},
        clearOverride: () {},
        persist: () async => persistCount++,
      );
      // Second tap while busy: ignored, first choice wins.
      final second = performThemeReveal(
        controller: controller,
        origin: const Offset(1, 1),
        isToDark: true,
        targetTheme: ThemeData.dark(),
        animationsDisabled: false,
        capture: () async => _testImage(const Color(0xFF000000)),
        setOverride: (_) {},
        clearOverride: () {},
        persist: () async => persistCount++,
      );
      await tester.pump();
      await tester.pump();
      expect(controller.isToDark, isFalse);
      expect(controller.origin, const Offset(30, 30));
      expect(controller.phase, ThemeRevealPhase.animating);
      await tester.pumpAndSettle();
      await future;
      await second;
      expect(persistCount, 1);
      expect(controller.phase, ThemeRevealPhase.idle);
    });

    test('reduce animations: choice persists immediately, no capture, '
        'no override', () async {
      final controller = ThemeRevealController();
      var persistCount = 0;
      var captures = 0;
      await performThemeReveal(
        controller: controller,
        origin: const Offset(0, 0),
        isToDark: true,
        targetTheme: ThemeData.dark(),
        animationsDisabled: true,
        capture: () async {
          captures++;
          return _testImage(const Color(0xFF000000));
        },
        setOverride: (_) => fail('override must not be set'),
        clearOverride: () => fail('override must not be cleared'),
        persist: () async => persistCount++,
      );
      expect(persistCount, 1);
      expect(captures, 0);
      expect(controller.phase, ThemeRevealPhase.idle);
    });

    test('capture failure falls back to an instant persisted change',
        () async {
      final controller = ThemeRevealController();
      var persistCount = 0;
      await performThemeReveal(
        controller: controller,
        origin: const Offset(0, 0),
        isToDark: true,
        targetTheme: ThemeData.dark(),
        animationsDisabled: false,
        capture: () async => null,
        setOverride: (_) => fail('override must not be set'),
        clearOverride: () {},
        persist: () async => persistCount++,
      );
      expect(persistCount, 1);
      expect(controller.phase, ThemeRevealPhase.idle);
    });

    testWidgets('overlay shows the old screenshot while holding and a '
        'clipped pair while animating', (tester) async {
      final controller = await _pumpOverlayApp(tester);
      expect(find.byType(RawImage), findsNothing);
      controller.begin(origin: const Offset(40, 40), isToDark: true);
      controller.showOld(await _testImage(const Color(0xFFFFFFFF)));
      await tester.pump();
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.byType(ClipPath), findsNothing);
      controller.startAnimation(await _testImage(const Color(0xFF000000)));
      await tester.pump();
      expect(find.byType(ClipPath), findsOneWidget);
      expect(find.byType(RawImage), findsNWidgets(2));
    });
  });
}
