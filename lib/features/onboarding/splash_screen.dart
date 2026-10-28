import 'package:flutter/material.dart';
import 'package:deliveryflow/core/app_lock/app_lock_service.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/design_system.dart';
import 'df_monogram.dart';

/// v27.32 splash/entry: the COMBINED DF mark rebuilt to match the
/// reference video's actual motion (v27.31's instant outline -> solid
/// switch with a popping F was judged "very very very bad compared
/// to the video"): a THIN WHITE outline draws itself with a glowing
/// tip dot and anchor dots, then a DIAGONAL wipe sweeps bottom-left
/// to top-right progressively revealing the solid WHITE D with the
/// BLUE stylized F inside its bowl — the F emerges via the same
/// sweep, never as a separate pop-in — on a NEAR-BLACK background,
/// then "DeliveryFlow" fades in, then the app enters.
///
/// TOTAL ENTRY is exactly 2500ms (Mohamed's correction, superseding
/// the 2000ms note and v27.30's 1.25s budget): draw 1000ms + sweep
/// 1000ms + name fade 500ms. The sequence never blocks on network,
/// and under OS reduce-motion it shows the static filled mark and
/// enters immediately.
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

  /// Total entry time: EXACTLY 2500ms (draw 1000 + sweep 1000 +
  /// name fade 500). Kept public so tests can assert the budget.
  static const totalDuration = Duration(milliseconds: 2500);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _draw;
  late final Animation<double> _sweep;
  late final Animation<double> _name;
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
      CurveTween(curve: const Interval(0.0, 0.40, curve: Curves.easeOut)),
    );
    _sweep = _controller.drive(
      CurveTween(curve: const Interval(0.40, 0.80, curve: Curves.easeInOut)),
    );
    _name = _controller.drive(
      CurveTween(curve: const Interval(0.80, 1.0, curve: Curves.easeOut)),
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
    // Near-black background, matching the reference video, so the
    // white D reads exactly like the video at every stage.
    const background = Color(0xFF0A0A0A);
    return Scaffold(
      backgroundColor: background,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final draw = reduceMotion ? 1.0 : _draw.value;
          final sweep = reduceMotion ? 1.0 : _sweep.value;
          final nameOpacity = reduceMotion ? 1.0 : _name.value;
          return SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DfMonogram(
                    key: const ValueKey('dfMonogram'),
                    drawProgress: draw,
                    sweepProgress: sweep,
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
          );
        },
      ),
    );
  }
}
