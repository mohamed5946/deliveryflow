import 'package:flutter/material.dart';
import 'package:deliveryflow/core/app_lock/app_lock_service.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/design_system.dart';
import 'df_monogram.dart';

/// v27.31 splash/entry: the COMBINED DF mark — one bold D whose outline
/// draws itself in a thin WHITE stroke, then fills solid WHITE, with a
/// BLUE stylized F appearing inside its bowl (exactly the reference
/// video's mark) — then "DeliveryFlow" appears, then the app enters
/// with a smooth fade/slide. Replaces the v27.30 side-by-side letters.
///
/// SPEED IS A HARD REQUIREMENT: the whole sequence is 1250ms — inside
/// the 1–1.5s budget — never blocks on network, and under OS
/// reduce-motion it shows the static filled mark and enters immediately.
///
/// LOCK-FIRST ORDERING (v27.30, Mohamed's explicit spec): the
/// animation must NEVER start while the app lock is showing. The
/// sequence with the lock on is: lock screen FIRST → fingerprint
/// accepted → ONLY THEN does this animation start and play. The gate
/// publishes its status via [appLockGateOpenProvider]; this screen
/// waits for it and never delays or bypasses the lock. With no lock
/// active, the animation plays normally on launch.
///
/// This replaces the old 1600ms motorcycle-icon + loading-bar splash
/// entirely: exactly one entry sequence, never two stacked intros.
/// The running motorcycle is gone from the ENTRY; motorcycle courier
/// branding is untouched INSIDE the app (home header, About, etc.).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// Total entry time. Kept public so tests can assert the budget.
  static const totalDuration = Duration(milliseconds: 1250);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _draw;
  late final Animation<double> _fill;
  late final Animation<double> _name;
  late final Animation<double> _exit;
  bool _navigated = false;
  bool _started = false;
  ValueNotifier<bool>? _gateOpen;

  void _goHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    context.go('/home');
  }

  /// Starts the entry once — and only once — the gate is open.
  void _maybeStart() {
    if (_started || !mounted) return;
    if (!(_gateOpen?.value ?? true)) return;
    _started = true;
    // Reduce-motion: skip the sequence, enter immediately.
    if (MediaQuery.disableAnimationsOf(context)) {
      _goHome();
    } else {
      _controller.forward();
    }
  }

  void _onGateChanged() => _maybeStart();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SplashScreen.totalDuration,
    );
    _draw = _controller.drive(
      CurveTween(curve: const Interval(0.0, 0.56, curve: Curves.easeOut)),
    );
    _fill = _controller.drive(
      CurveTween(curve: const Interval(0.56, 0.80, curve: Curves.easeInOut)),
    );
    _name = _controller.drive(
      CurveTween(curve: const Interval(0.72, 0.92, curve: Curves.easeOut)),
    );
    _exit = _controller.drive(
      CurveTween(curve: const Interval(0.92, 1.0, curve: Curves.easeInOut)),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _goHome();
    });
    // Lock-first: wait for the gate before starting anything. The
    // gate syncs this notifier in its own initState, which runs
    // before this route mounts, so a locked cold start reads false
    // here and the animation genuinely does not run behind the lock.
    _gateOpen = ref.read(appLockGateOpenProvider);
    _gateOpen!.addListener(_onGateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  @override
  void dispose() {
    _gateOpen?.removeListener(_onGateChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Dark navy background: the white stroke/D-fill and the blue
    // F-fill both read clearly against it at every stage.
    const background = Color(0xFF0B1D3A);
    return Scaffold(
      backgroundColor: background,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final draw = reduceMotion ? 1.0 : _draw.value;
          final fill = reduceMotion ? 1.0 : _fill.value;
          final nameOpacity = reduceMotion ? 1.0 : _name.value;
          final exit = reduceMotion ? 0.0 : _exit.value;
          return Opacity(
            opacity: 1.0 - exit,
            child: Transform.translate(
              offset: Offset(0, -16 * exit),
              child: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DfMonogram(
                        key: const ValueKey('dfMonogram'),
                        drawProgress: draw,
                        fillProgress: fill,
                        fillBlue: LiquidPalette.primaryBlue,
                      ),
                      const SizedBox(height: 24),
                      Opacity(
                        key: const ValueKey('dfSplashName'),
                        opacity: nameOpacity,
                        child: Text(
                          'DeliveryFlow',
                          style: text.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Opacity(
                        opacity: nameOpacity,
                        child: Text(
                          l10n.workSmarterTagline,
                          style: text.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
