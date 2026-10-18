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
import '../features/onboarding/splash_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/registration/registration_screen.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/weekly_reports/report_screen.dart';
import '../features/work_sessions/session_screen.dart';
import '../features/offline_maps/offline_maps_screen.dart';
import '../features/offline_maps/region_picker_screen.dart';

const _paths = ['/home', '/schedule', '/reports', '/history', '/profile'];

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
      return selected ? Icons.person_rounded : Icons.person_outlined;
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
      return l10n.navProfile;
    default:
      return '';
  }
}

/// Tab-switch transition: the 5 main tabs live in a go_router
/// [StatefulShellRoute.indexedStack], so branch switches are instant by
/// default. This wrapper plays a quick fade + subtle rise every time the
/// tab index changes, and also masks the one-time hitch of a lazily-built
/// branch. The [child] (the navigation shell) keeps a stable identity, so
/// each tab's navigator state is preserved.
class _TabTransition extends StatefulWidget {
  final int index;
  final Widget child;

  const _TabTransition({required this.index, required this.child});

  @override
  State<_TabTransition> createState() => _TabTransitionState();
}

class _TabTransitionState extends State<_TabTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _c.value = 1.0; // first build: visible immediately, no animation
  }

  @override
  void didUpdateWidget(_TabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _c.forward(from: 0.0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

GoRouter buildRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final settings = ref.read(settingsProvider);
      final registered = settings.registered;
      final done = settings.onboardingDone;
      // Defensive: a geo: URI must never become a route. The engine no
      // longer forwards VIEW intent URIs (flutter_deeplinking_enabled
      // is false in the manifest), but if one ever slips through, send
      // it to splash instead of the error page — geo: intents are
      // handled exclusively through the native MethodChannel path
      // (see lib/core/deep_link/geo_share_service.dart).
      if (state.uri.toString().startsWith('geo:')) return '/splash';
      final loc = state.matchedLocation;
      // Registration gate comes before everything, including splash.
      if (!registered && loc != '/register') return '/register';
      if (registered && loc == '/register') return '/splash';
      // Splash always shows first; it navigates to /home itself,
      // where the rules below take over.
      if (loc == '/splash' || loc == '/register') return null;
      if (!done && loc != '/onboarding') return '/onboarding';
      if (done && loc == '/onboarding') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegistrationScreen(),
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
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
                // Top padding: header content on the tab screens must sit
                // well BELOW the phone's status bar (time/battery/icons)
                // with comfortable breathing space, like the mockup.
                // Bottom padding keeps list content from hiding under
                // the floating bar; the background still bleeds behind
                // on all edges (no black bands).
                Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 20,
                    bottom: 96,
                  ),
                  child: _TabTransition(
                    index: navigationShell.currentIndex,
                    child: navigationShell,
                  ),
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
                path: '/profile',
                builder: (context, state) => const ProfileScreen()),
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
      GoRoute(
        path: '/offline-maps',
        builder: (context, state) => const OfflineMapsScreen(),
      ),
      GoRoute(
        path: '/offline-maps/pick',
        builder: (context, state) => const RegionPickerScreen(),
      ),
    ],
  );
}
