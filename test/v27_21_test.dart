import 'package:deliveryflow/core/logging/frame_timing_collector.dart';
import 'package:deliveryflow/core/map/cached_tile_provider.dart';
import 'package:deliveryflow/features/daily_orders/order_detail_screen.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:deliveryflow/theme/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// v27.21 performance regression tests:
/// (a) GlassCard blur is cached behind a RepaintBoundary,
/// (b) displayed polylines are downsampled to <=500 points keeping
///     first/last (stored lists are never touched — the function
///     takes a list and returns a new one),
/// (c) the frame-timing collector computes average FPS from
///     synthetic timings and tracks the worst frame.
void main() {
  group('RepaintBoundary around GlassCard blur', () {
    testWidgets('GlassCard BackdropFilter sits under a RepaintBoundary',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: GlassCard(
              child: Text('hello'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('hello'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });

    testWidgets('GlassNavBar blur sits under a RepaintBoundary',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: GlassNavBar(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              icons: const [Icons.home_rounded, Icons.person_rounded],
              selectedIcons: const [
                Icons.home_rounded,
                Icons.person_rounded,
              ],
              labels: const ['Home', 'Me'],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });
  });

  group('downsamplePolyline (display only)', () {
    List<LatLng> line(int n) =>
        List.generate(n, (i) => LatLng(30.0 + i * 0.001, 31.0));

    test('short lists pass through unchanged', () {
      final pts = line(10);
      expect(downsamplePolyline(pts, 500), same(pts));
    });

    test('long lists cap at 500 and keep first and last', () {
      final pts = line(1200);
      final out = downsamplePolyline(pts, 500);
      expect(out.length, 500);
      expect(out.first, pts.first);
      expect(out.last, pts.last);
      // Input list itself is untouched (stored data never modified).
      expect(pts.length, 1200);
    });

    test('exactly 500 stays at 500, 501 shrinks to 500', () {
      expect(downsamplePolyline(line(500), 500).length, 500);
      expect(downsamplePolyline(line(501), 500).length, 500);
    });
  });

  group('FrameTimingCollector', () {
    test('average FPS from synthetic timings, worst frame tracked', () {
      final c = FrameTimingCollector();
      // 60 frames at 16ms (~62fps) + 60 frames at 20ms (50fps):
      // mean 18ms -> 55fps floor.
      c.recordTestTimings([
        for (var i = 0; i < 60; i++) const Duration(milliseconds: 16),
        for (var i = 0; i < 60; i++) const Duration(milliseconds: 20),
      ]);
      expect(c.frameCount, 120);
      expect(c.averageFps, 55);
      expect(c.worstFrameMs, 20);
    });

    test('window caps at 120 frames, oldest dropped', () {
      final c = FrameTimingCollector();
      c.recordTestTimings([
        for (var i = 0; i < 200; i++) const Duration(milliseconds: 10),
      ]);
      expect(c.frameCount, 120);
      expect(c.averageFps, 100);
    });

    test('empty collector reads 0', () {
      final c = FrameTimingCollector();
      expect(c.frameCount, 0);
      expect(c.averageFps, 0);
      expect(c.worstFrameMs, 0);
    });
  });

  group('CachedTileProvider', () {
    test('cache path is a pure function of z/x/y', () {
      expect(
        CachedTileProvider.cacheFilePath(
          basePath: '/tmp/tiles',
          z: 14,
          x: 1234,
          y: 5678,
        ),
        '/tmp/tiles/14/1234/5678.png',
      );
    });
  });
}
