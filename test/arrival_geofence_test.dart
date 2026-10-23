import 'package:deliveryflow/core/tracking/arrival_geofence.dart';
import 'package:flutter_test/flutter_test.dart';

/// v27.8: the arrival state machine behind the «هل وصلت؟» prompt.
/// Coordinates are picked around a target in Cairo: +0.0005° latitude
/// ≈ 55 m (inside the 75 m arrival radius), +0.0012° ≈ 133 m
/// (between the radii), +0.0025° ≈ 278 m (outside the 200 m re-arm
/// radius).
void main() {
  const targetLat = 30.0;
  const targetLng = 30.98;
  const insideLat = 30.0005;
  const midLat = 30.0012;
  const outsideLat = 30.0025;

  final t0 = DateTime(2026, 10, 23, 12, 0, 0);

  ArrivalGeofence armed() =>
      ArrivalGeofence(targetLat: targetLat, targetLng: targetLng);

  group('ArrivalGeofence', () {
    test('no target: positions never prompt', () {
      final g = ArrivalGeofence();
      expect(g.hasTarget, isFalse);
      expect(g.onPosition(targetLat, targetLng, t0), ArrivalSignal.none);
      expect(g.phase, ArrivalPhase.outside);
    });

    test('entering the radius prompts exactly once', () {
      final g = armed();
      expect(g.onPosition(outsideLat, targetLng, t0), ArrivalSignal.none);
      expect(
        g.onPosition(insideLat, targetLng, t0),
        ArrivalSignal.promptStarted,
      );
      expect(g.phase, ArrivalPhase.prompted);
      expect(g.promptId, t0.millisecondsSinceEpoch);
      // Still inside: no second prompt.
      expect(
        g.onPosition(insideLat, targetLng,
            t0.add(const Duration(seconds: 3))),
        ArrivalSignal.none,
      );
    });

    test('countdown expiry auto-confirms', () {
      final g = armed();
      g.onPosition(insideLat, targetLng, t0);
      expect(g.checkTimeout(t0.add(const Duration(seconds: 9))), isFalse);
      expect(g.phase, ArrivalPhase.prompted);
      expect(g.checkTimeout(t0.add(const Duration(seconds: 10))), isTrue);
      expect(g.phase, ArrivalPhase.confirmed);
      // Terminal: no re-prompt, no second confirm.
      expect(
        g.onPosition(insideLat, targetLng,
            t0.add(const Duration(seconds: 30))),
        ArrivalSignal.none,
      );
      expect(g.checkTimeout(t0.add(const Duration(seconds: 40))), isFalse);
    });

    test('decline suppresses until the wide radius is exited and '
        're-entered', () {
      final g = armed();
      g.onPosition(insideLat, targetLng, t0);
      expect(g.onDecline(), isTrue);
      expect(g.phase, ArrivalPhase.suppressed);
      // Moving around inside / between the radii: still suppressed.
      expect(
        g.onPosition(insideLat, targetLng,
            t0.add(const Duration(seconds: 20))),
        ArrivalSignal.none,
      );
      expect(
        g.onPosition(midLat, targetLng, t0.add(const Duration(seconds: 30))),
        ArrivalSignal.none,
      );
      expect(g.phase, ArrivalPhase.suppressed);
      // Exit the wide radius: re-armed.
      expect(
        g.onPosition(outsideLat, targetLng,
            t0.add(const Duration(seconds: 40))),
        ArrivalSignal.none,
      );
      expect(g.phase, ArrivalPhase.outside);
      // Re-enter: prompt again, with a fresh prompt id.
      final t1 = t0.add(const Duration(minutes: 1));
      expect(g.onPosition(insideLat, targetLng, t1),
          ArrivalSignal.promptStarted);
      expect(g.promptId, t1.millisecondsSinceEpoch);
    });

    test('leaving the area while prompted cancels the prompt', () {
      final g = armed();
      g.onPosition(insideLat, targetLng, t0);
      expect(
        g.onPosition(outsideLat, targetLng,
            t0.add(const Duration(seconds: 4))),
        ArrivalSignal.promptCancelledLeftArea,
      );
      expect(g.phase, ArrivalPhase.outside);
      expect(g.checkTimeout(t0.add(const Duration(seconds: 30))), isFalse);
    });

    test('decline outside a prompt is a no-op', () {
      final g = armed();
      expect(g.onDecline(), isFalse);
      expect(g.phase, ArrivalPhase.outside);
    });
  });
}
