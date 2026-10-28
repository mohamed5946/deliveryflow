import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// v27.25: animated circular-reveal theme switch, mirroring the Study
/// Assistant v2.13 behaviour (circle grows out of the tapped button when
/// switching to dark, shrinks back into it when switching to light, and
/// the reveal covers the whole screen including the bottom nav bar).
///
/// DeliveryFlow does NOT use the animated_theme_switcher package for this,
/// deliberately: that package owns the app's ThemeData, which would break
/// DeliveryFlow's settings-driven theme (colour presets, system mode that
/// must follow OS brightness mid-session, and the router). Instead the
/// reveal is screenshot-based and leaves every existing theme path
/// untouched:
///
///   1. The tapped row's global centre is the reveal origin.
///   2. The current screen is captured (old theme) and shown opaque, so
///      no frame of the new theme can flash through.
///   3. An in-memory theme override (NOT persisted) switches the live app
///      to the target theme for one frame, the new screen is captured,
///      and the override is cleared again.
///   4. The overlay animates: to dark, the new-theme screenshot grows as
///      a circle out of the button over the old screenshot; to light,
///      the old-theme screenshot shrinks back into the button over the
///      new screenshot.
///   5. ONLY when the animation finishes is the choice persisted to
///      settings (persisting mid-animation would break the clip, and the
///      live app would visibly jump themes under the overlay).
///
/// A second tap while an animation is running is ignored, exactly like
/// the SA behaviour: the first choice is the one that persists.
/// When the OS reports animations disabled (accessibility / reduce
/// motion), the animation is skipped and the choice persists immediately.
/// DeliveryFlow has no in-app reduce-animation setting; the OS flag is
/// the reduce-motion signal.

/// In-memory theme override, applied for a single frame while the new
/// theme screenshot is captured. Null in normal operation.
final themeOverrideProvider = StateProvider<ThemeData?>((ref) => null);

/// Global key of the RepaintBoundary wrapped around the whole app content
/// (see DeliveryFlowApp's builder). The reveal screenshots are taken here
/// so they include the bottom nav bar.
final themeRevealBoundaryKey = GlobalKey();

/// Phases of a reveal. [holding] shows the old screenshot opaque while
/// the new screenshot is captured; [animating] runs the circle clip.
enum ThemeRevealPhase { idle, holding, animating }

/// State machine for one reveal. Owned by a Riverpod provider so the
/// overlay widget and the tap handler share it.
class ThemeRevealController extends ChangeNotifier {
  ThemeRevealPhase _phase = ThemeRevealPhase.idle;
  ui.Image? _oldImage;
  ui.Image? _newImage;
  Offset _origin = Offset.zero;
  bool _isToDark = true;

  /// Invoked by the overlay when its animation completes. Wired by
  /// [performThemeReveal]; null otherwise.
  Future<void> Function()? onAnimationFinished;

  ThemeRevealPhase get phase => _phase;
  bool get busy => _phase != ThemeRevealPhase.idle;
  ui.Image? get oldImage => _oldImage;
  ui.Image? get newImage => _newImage;
  Offset get origin => _origin;
  bool get isToDark => _isToDark;

  /// Starts a reveal. Returns false when one is already running (the
  /// second tap is ignored; the first choice wins).
  bool begin({required Offset origin, required bool isToDark}) {
    if (busy) return false;
    _origin = origin;
    _isToDark = isToDark;
    _phase = ThemeRevealPhase.holding;
    notifyListeners();
    return true;
  }

  void showOld(ui.Image image) {
    _oldImage = image;
    notifyListeners();
  }

  void startAnimation(ui.Image newImage) {
    _newImage = newImage;
    _phase = ThemeRevealPhase.animating;
    notifyListeners();
  }

  /// Drops the overlay and releases the screenshots. Called only after
  /// the choice has been persisted (or after a failed capture fallback).
  void reset() {
    _phase = ThemeRevealPhase.idle;
    _oldImage = null;
    _newImage = null;
    onAnimationFinished = null;
    notifyListeners();
  }
}

final themeRevealControllerProvider =
    ChangeNotifierProvider<ThemeRevealController>(
        (ref) => ThemeRevealController());

/// Captures the whole app content (including the bottom nav bar) as an
/// image. Returns null when the boundary is not mounted (e.g. tests
/// without the full app), in which case callers fall back to an instant
/// theme change.
Future<ui.Image?> captureThemeRevealImage(double pixelRatio) async {
  final context = themeRevealBoundaryKey.currentContext;
  if (context == null) return null;
  final boundary = context.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  try {
    return await boundary.toImage(pixelRatio: pixelRatio);
  } catch (_) {
    return null;
  }
}

/// Maximum radius a circle centred at [origin] needs to cover a screen
/// of [size] (distance to the farthest corner).
double themeRevealMaxRadius(Size size, Offset origin) {
  final dx = math.max(origin.dx, size.width - origin.dx);
  final dy = math.max(origin.dy, size.height - origin.dy);
  return math.sqrt(dx * dx + dy * dy);
}

/// Circular clip for the reveal overlay.
class CircleRevealClipper extends CustomClipper<Path> {
  const CircleRevealClipper({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) => Path()
    ..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(CircleRevealClipper oldClipper) =>
      center != oldClipper.center || radius != oldClipper.radius;
}

/// Runs one animated theme change. The returned future completes after
/// the choice has been persisted (or immediately for the skip/fallback
/// paths), so callers can await it in tests.
///
/// [capture] captures the current screen; [setOverride]/[clearOverride]
/// drive the in-memory theme; [persist] saves the choice to settings
/// (awaited BEFORE the overlay is dropped, so the live app never flashes
/// the old theme).
Future<void> performThemeReveal({
  required ThemeRevealController controller,
  required Offset origin,
  required bool isToDark,
  required ThemeData targetTheme,
  required bool animationsDisabled,
  required Future<ui.Image?> Function() capture,
  required void Function(ThemeData theme) setOverride,
  required VoidCallback clearOverride,
  required Future<void> Function() persist,
}) async {
  if (animationsDisabled) {
    await persist();
    return;
  }
  if (!controller.begin(origin: origin, isToDark: isToDark)) return;
  final completer = Completer<void>();
  void finishNow() {
    if (!completer.isCompleted) completer.complete();
  }

  try {
    final old = await capture();
    if (old == null) {
      // No screenshot available: fall back to an instant change.
      controller.reset();
      await persist();
      return;
    }
    controller.showOld(old);
    setOverride(targetTheme);
    // Let exactly one frame render with the new theme, then capture it.
    await WidgetsBinding.instance.endOfFrame;
    final fresh = await capture();
    clearOverride();
    if (fresh == null) {
      controller.reset();
      await persist();
      return;
    }
    controller.onAnimationFinished = () async {
      try {
        await persist();
      } catch (_) {
        // A failed save must never leave the overlay stuck: the live
        // theme simply stays on the old choice (settings unchanged).
      }
      controller.reset();
      finishNow();
    };
    controller.startAnimation(fresh);
  } catch (_) {
    clearOverride();
    controller.reset();
    finishNow();
  }
  return completer.future;
}

/// Overlay widget: renders the reveal on top of the whole app. Idle
/// renders nothing. Placed in MaterialApp's builder so it covers the
/// bottom nav bar too. Touches are absorbed while visible so no stray
/// tap can hit the old-theme app mid-animation.
class ThemeRevealOverlay extends ConsumerStatefulWidget {
  const ThemeRevealOverlay({super.key});

  /// Duration of the reveal, matching the SA 300 ms window.
  static const Duration duration = Duration(milliseconds: 300);

  @override
  ConsumerState<ThemeRevealOverlay> createState() =>
      _ThemeRevealOverlayState();
}

class _ThemeRevealOverlayState extends ConsumerState<ThemeRevealOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _animationStarted = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: ThemeRevealOverlay.duration,
    )..addStatusListener((status) {
        // Jumping the value to an endpoint synchronously fires a
        // spurious completed/dismissed status before the ticker starts
        // (reverse(from: 1.0) is the classic case); ignore events that
        // fire inside the start call itself — genuine completion always
        // arrives later, after ticks.
        if (_starting) return;
        // (The controller keeps its terminal status after the run, so
        // without this guard a later reset would re-fire the callback.)
        if (ref.read(themeRevealControllerProvider).phase !=
            ThemeRevealPhase.animating) {
          return;
        }
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          ref.read(themeRevealControllerProvider).onAnimationFinished
              ?.call();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _driveAnimation(ThemeRevealController reveal) {
    if (reveal.phase == ThemeRevealPhase.animating &&
        !_animationStarted) {
      _animationStarted = true;
      _starting = true;
      try {
        if (reveal.isToDark) {
          _controller.forward(from: 0.0);
        } else {
          _controller.reverse(from: 1.0);
        }
      } finally {
        _starting = false;
      }
    } else if (reveal.phase == ThemeRevealPhase.idle) {
      _animationStarted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reveal = ref.watch(themeRevealControllerProvider);
    ref.listen<ThemeRevealController>(
      themeRevealControllerProvider,
      (_, next) => _driveAnimation(next),
    );
    // The listener above fires on phase changes; also drive from the
    // current value so a rebuild that already sees [animating] starts
    // the animation even if the notification was consumed elsewhere.
    _driveAnimation(reveal);
    if (reveal.phase == ThemeRevealPhase.idle) {
      return const SizedBox.shrink();
    }
    final oldImage = reveal.oldImage;
    if (oldImage == null) return const SizedBox.shrink();
    if (reveal.phase == ThemeRevealPhase.holding) {
      return AbsorbPointer(
        absorbing: true,
        child: RepaintBoundary(
          child: RawImage(image: oldImage, fit: BoxFit.cover),
        ),
      );
    }
    final newImage = reveal.newImage;
    if (newImage == null) return const SizedBox.shrink();
    // To dark: new screenshot grows as a circle over the old one.
    // To light: old screenshot shrinks into the button over the new one.
    final base = reveal.isToDark ? oldImage : newImage;
    final top = reveal.isToDark ? newImage : oldImage;
    return AbsorbPointer(
      absorbing: true,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final size = MediaQuery.sizeOf(context);
            final radius = _controller.value *
                themeRevealMaxRadius(size, reveal.origin);
            return Stack(
              fit: StackFit.expand,
              children: [
                RawImage(image: base, fit: BoxFit.cover),
                ClipPath(
                  clipper: CircleRevealClipper(
                    center: reveal.origin,
                    radius: radius,
                  ),
                  child: RawImage(image: top, fit: BoxFit.cover),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
