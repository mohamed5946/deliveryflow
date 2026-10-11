import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../theme/design_system.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/daily_orders/order_entry_screen.dart';
import '../features/history/history_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/weekly_reports/report_screen.dart';
import '../features/work_sessions/session_screen.dart';

const _paths = ['/home', '/schedule', '/reports', '/history', '/settings'];

IconData _iconFor(int index, bool selected) {
  switch (index) {
    case 0:
      return selected ? Icons.home_rounded : Icons.home_outlined;
    case 1:
      return selected
          ? Icons.calendar_month_rounded
          : Icons.calendar_month_outlined;
    case 2:
      return selected ? Icons.bar_chart_rounded : Icons.bar_chart_outlined;
    case 3:
      return selected ? Icons.history_rounded : Icons.history_outlined;
    case 4:
      return selected ? Icons.settings_rounded : Icons.settings_outlined;
    default:
      return Icons.circle;
  }
}

String _labelFor(AppLocalizations l10n, int index) {
  switch (index) {
    case 0:
      return l10n.navHome;
    case 1:
      return l10n.navSchedule;
    case 2:
      return l10n.navReports;
    case 3:
      return l10n.navHistory;
    case 4:
      return l10n.navSettings;
    default:
      return '';
  }
}

GoRouter buildRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final done =
          ref.read(settingsProvider.select((s) => s.onboardingDone));
      final onOnboarding = state.matchedLocation == '/onboarding';
      if (!done && !onOnboarding) return '/onboarding';
      if (done && onOnboarding) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            backgroundColor: Colors.transparent,
            // True floating bar: the nav bar is an overlay above the
            // content (not in the bottomNavigationBar slot), and the
            // aurora background extends edge-to-edge behind it — no
            // black rectangle where the old bar used to be.
            extendBody: true,
            body: Stack(
              children: [
                const AuroraBackground(),
                // Bottom padding keeps list content from hiding under
                // the floating bar; the background still bleeds behind.
                Padding(
                  padding: const EdgeInsets.only(bottom: 96),
                  child: navigationShell,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: GlassNavBar(
                    selectedIndex: navigationShell.currentIndex,
                    onDestinationSelected: (i) =>
                        navigationShell.goBranch(i),
                    icons: [
                      for (var i = 0; i < _paths.length; i++)
                        _iconFor(i, false),
                    ],
                    selectedIcons: [
                      for (var i = 0; i < _paths.length; i++)
                        _iconFor(i, true),
                    ],
                    labels: [
                      for (var i = 0; i < _paths.length; i++)
                        _labelFor(l10n, i),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/home',
                builder: (context, state) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/schedule',
                builder: (context, state) => const ScheduleScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/reports',
                builder: (context, state) => const ReportScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/history',
                builder: (context, state) => const HistoryScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen()),
          ]),
        ],
      ),
      GoRoute(
        path: '/orders',
        builder: (context, state) {
          final dateKey = state.uri.queryParameters['date'];
          return OrderEntryScreen(dateKey: dateKey);
        },
      ),
      GoRoute(
        path: '/hours',
        builder: (context, state) {
          final dateKey = state.uri.queryParameters['date'];
          return SessionScreen(dateKey: dateKey);
        },
      ),
    ],
  );
}
