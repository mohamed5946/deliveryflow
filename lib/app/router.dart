import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/update/app_update.dart';
import '../core/update/app_update_flow.dart';
import 'first_run_redirect.dart';
import '../theme/design_system.dart';
import '../theme/staggered_entrance.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/daily_orders/order_entry_screen.dart';
import '../features/cloud/cloud_account_screen.dart';
import '../features/cloud/cloud_live_sync_bootstrapper.dart';
import '../features/cloud/management_driver_screen.dart';
import '../features/cloud/management_payout_screen.dart';
import '../features/cloud/management_screen.dart';
import '../features/cloud/manager_edit_day_screen.dart';
import '../features/history/history_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/profile/diagnostics_log_screen.dart';
import '../features/profile/mart_picker_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/registration/registration_screen.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/weekly_reports/report_screen.dart';
import '../features/work_sessions/session_screen.dart';

const _paths = [
  '/home',
  '/schedule',
  '/reports',
  '/history',
  '/profile',
];

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

/// The app router — created exactly ONCE for the app's lifetime.
///
/// v27 fix: this used to be built by a `buildRouter(ref)` call inside
/// `DeliveryFlowApp.build` while watching settingsProvider, so EVERY
/// settings change (theme, language, any toggle) constructed a brand-new
/// GoRouter whose initialLocation is /splash — the app appeared to close
/// and reopen from scratch on every toggle. The router is now stable;
/// theme/locale are MaterialApp concerns and apply live around it.
///
/// The redirect gate depends only on `registered` / `onboardingDone`,
/// so it re-evaluates through [GoRouter.refreshListenable] whenever one
/// of those two flips — without recreating the router or resetting the
/// current location.
final routerProvider = Provider<GoRouter>((ref) {
  final gateRefresh = ValueNotifier<int>(0);
  ref.listen(
    settingsProvider.select((s) => (s.registered, s.onboardingDone)),
    (_, __) => gateRefresh.value++,
  );
  ref.onDispose(gateRefresh.dispose);
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: gateRefresh,
    redirect: (context, state) {
      final settings = ref.read(settingsProvider);
      return resolveFirstRunRedirect(
        registered: settings.registered,
        onboardingDone: settings.onboardingDone,
        uriString: state.uri.toString(),
        matchedLocation: state.matchedLocation,
      );
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
          // v27.31: publish the selected tab for staggered-list replay.
          // Post-frame so TabReplayScope listeners never setState during
          // this build; the value check avoids redundant notifications.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (currentTabIndexNotifier.value != navigationShell.currentIndex) {
              currentTabIndexNotifier.value = navigationShell.currentIndex;
            }
          });
          // v27: keep the floating bar clear of the system gesture /
          // 3-button navigation area. The app is edge-to-edge with
          // transparent system bars, so without this offset the system
          // bar overlaps the app bar on gesture-nav phones. When there
          // is no system inset (hidden bars), the offset is 0 and the
          // bar rests at the very bottom edge, exactly as before.
          final bottomInset = MediaQuery.of(context).viewPadding.bottom;
          return Scaffold(
            backgroundColor: Colors.transparent,
            // True floating bar: the nav bar is an overlay above the
            // content (not in the bottomNavigationBar slot), and the
            // aurora background extends edge-to-edge behind it — no
            // black rectangle where the old bar used to be.
            extendBody: true,
            body: Stack(
              children: [
                // v27.37: automatic update check, once per session.
                // Renders nothing; lives under the shell Navigator so
                // it can push the Software Update screen. Foreground
                // only — no background work while the app is closed.
                Consumer(
                  builder: (context, ref, _) => AppUpdateLaunchCheck(
                    flow: AppUpdateFlow(
                      service: AppUpdateService(
                        log: ref.watch(appLogServiceProvider),
                      ),
                    ),
                  ),
                ),
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
                    bottom: 96 + bottomInset,
                  ),
                  child: _TabTransition(
                    index: navigationShell.currentIndex,
                    child: navigationShell,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomInset,
                  // v27.24 liquid trial: nav bar opts in only when the
                  // setting is ON; OFF renders the exact old glass.
                  // exact literal shape of the nav-bar liquid opt-in
                  child: Consumer(
                    builder: (context, ref, _) => GlassNavBar(
                      liquid: ref.watch(settingsProvider /* nav opt-in */
                          .select((s) => s.liquidGlassEnabled)),
                      selectedIndex: navigationShell.currentIndex,
                      onDestinationSelected: (i) {
                        // v27.31: sync the tab index eagerly on tap
                        // (post-frame sync in the builder covers
                        // programmatic goBranch/go navigation too).
                        currentTabIndexNotifier.value = i;
                        navigationShell.goBranch(i);
                      },
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
                ),
                // v27.36: continuous foreground auto-sync. Renders
                // nothing; owns the CloudLiveSync lifecycle for the
                // whole app session and surfaces its failures loudly.
                const CloudLiveSyncBootstrapper(),
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
        path: '/diagnostics-log',
        builder: (context, state) => const DiagnosticsLogScreen(),
      ),
      GoRoute(
        path: '/cloud-account',
        builder: (context, state) => const CloudAccountScreen(),
      ),
      GoRoute(
        path: '/management',
        builder: (context, state) => const ManagementScreen(),
      ),
      GoRoute(
        path: '/management/driver',
        builder: (context, state) {
          final uid = state.uri.queryParameters['uid'] ?? '';
          final date = state.uri.queryParameters['date'] ?? '';
          return ManagementDriverScreen(uid: uid, dateKey: date);
        },
      ),
      GoRoute(
        path: '/management/driver/edit',
        builder: (context, state) {
          final uid = state.uri.queryParameters['uid'] ?? '';
          final date = state.uri.queryParameters['date'] ?? '';
          return ManagerEditDayScreen(uid: uid, dateKey: date);
        },
      ),
      GoRoute(
        path: '/management/payout',
        builder: (context, state) {
          final uid = state.uri.queryParameters['uid'] ?? '';
          final date = state.uri.queryParameters['date'] ?? '';
          return ManagementPayoutScreen(uid: uid, dateKey: date);
        },
      ),
      GoRoute(
        path: '/mart-picker',
        builder: (context, state) => const MartPickerScreen(),
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
  ref.onDispose(router.dispose);
  return router;
});
