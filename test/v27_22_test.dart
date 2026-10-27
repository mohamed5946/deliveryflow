import 'dart:io';

import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/features/dashboard/glass_dashboard_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('glass dashboard stats (real-data math, no demo numbers)', () {
    test('paid day earns daily fixed pay; unpaid day does not', () {
      expect(paidDayForOrders(0), isFalse);
      expect(paidDayForOrders(3), isTrue);
    });

    test('day earnings = orders*price + fixed (paid days only) + bonuses',
        () {
      expect(
        dayEarnings(
          orders: 4,
          orderPrice: 25,
          dailyFixedPay: 100,
          distanceBonus: 10,
          manualBonus: 5,
          flatBonus: 20,
        ),
        235,
      );
      // Zero-order day: no fixed pay, bonuses still count if present.
      expect(
        dayEarnings(
          orders: 0,
          orderPrice: 25,
          dailyFixedPay: 100,
          distanceBonus: 0,
          manualBonus: 0,
          flatBonus: 0,
        ),
        0,
      );
    });

    test('breakdown earnings use the breakdown bonus fields', () {
      const day = DayBreakdown(
        dateKey: '2026-10-27',
        orders: 2,
        workMinutes: 120,
        plannedHours: 8,
        isWorkingDay: true,
        kmOut: 10,
        kmBack: 5,
        distanceBonus: 8,
        manualBonus: 0,
        flatBonus: 10,
      );
      expect(
        dayBreakdownEarnings(day, orderPrice: 25, dailyFixedPay: 100),
        168,
      );
    });

    test('recent orders are newest-first and capped', () {
      OrderEntry entry(String id, int ts) => OrderEntry(
            id: id,
            dateKey: '2026-10-27',
            timestampMillis: ts,
          );
      final out = recentOrders(
        [entry('a', 100), entry('b', 300), entry('c', 200)],
        limit: 2,
      );
      expect(out.map((e) => e.id).toList(), ['b', 'c']);
    });

    test('chart ceiling has headroom and never zero', () {
      expect(chartCeiling([0, 0]), 100);
      expect(chartCeiling([100, 250]), 300);
    });
  });

  group('v27.22 wiring scans', () {
    test('route list: old 5 paths unchanged, /insights appended', () {
      final router = File('lib/app/router.dart').readAsStringSync();
      expect(router, contains("'/home'"));
      expect(router, contains("'/schedule'"));
      expect(router, contains("'/reports'"));
      expect(router, contains("'/history'"));
      expect(router, contains("'/profile'"));
      expect(router, contains("'/insights'"));
      expect(router, contains('GlassDashboardScreen'));
      // Home still renders the untouched DashboardScreen.
      expect(router, contains('DashboardScreen()'));
    });

    test('new screen: every BackdropFilter inside a RepaintBoundary', () {
      final src =
          File('lib/features/dashboard/glass_dashboard_screen.dart')
              .readAsStringSync();
      final blurCount =
          RegExp('BackdropFilter').allMatches(src).length;
      final boundaryCount =
          RegExp('RepaintBoundary').allMatches(src).length;
      expect(blurCount, greaterThan(0));
      expect(boundaryCount, greaterThanOrEqualTo(blurCount));
    });

    test('home screen file untouched by this change (no insights refs)',
        () {
      final home =
          File('lib/features/dashboard/dashboard_screen.dart')
              .readAsStringSync();
      expect(home, isNot(contains('GlassDashboardScreen')));
      expect(home, isNot(contains('navInsights')));
    });

    test('no fake/demo numbers in the new screen', () {
      final src =
          File('lib/features/dashboard/glass_dashboard_screen.dart')
              .readAsStringSync();
      expect(src, isNot(contains('demo')));
      expect(src, isNot(contains('fake')));
      expect(src, isNot(contains('placeholder')));
    });
  });
}
