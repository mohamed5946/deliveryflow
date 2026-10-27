import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// v27.22's Insights feature was removed in v27.23 (Mohamed did not
/// like the tab). The stats tests for the deleted screen are gone
/// with it; only the wiring assertions (5 tabs, no insights) remain.
void main() {
  group('v27.22 wiring scans (insights removed in v27.23)', () {
    test('route list: exactly the original 5 paths, no /insights', () {
      final router = File('lib/app/router.dart').readAsStringSync();
      expect(router, contains("'/home'"));
      expect(router, contains("'/schedule'"));
      expect(router, contains("'/reports'"));
      expect(router, contains("'/history'"));
      expect(router, contains("'/profile'"));
      expect(router, isNot(contains("'/insights'")));
      expect(router, isNot(contains('GlassDashboardScreen')));
      // Home still renders the untouched DashboardScreen.
      expect(router, contains('DashboardScreen()'));
    });

    test('insights screen files are deleted', () {
      expect(
          File('lib/features/dashboard/glass_dashboard_screen.dart')
              .existsSync(),
          isFalse);
      expect(
          File('lib/features/dashboard/glass_dashboard_stats.dart')
              .existsSync(),
          isFalse);
    });

    test('home screen file untouched by this change (no insights refs)',
        () {
      final home =
          File('lib/features/dashboard/dashboard_screen.dart')
              .readAsStringSync();
      expect(home, isNot(contains('GlassDashboardScreen')));
      expect(home, isNot(contains('navInsights')));
    });
  });
}
