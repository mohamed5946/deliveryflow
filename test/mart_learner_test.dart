import 'package:deliveryflow/core/tracking/mart_learner.dart';
import 'package:flutter_test/flutter_test.dart';

/// v27.8: mart learning from trip observations. Points around A are
/// ~55 m apart (inside the 120 m cluster radius); B is ~2 km away.
void main() {
  const aLat = 30.0;
  const aLng = 30.98;
  const aNearLat = 30.0005;
  const bLat = 30.02;
  const bLng = 30.99;
  const bNearLat = 30.0205;

  group('MartLearner', () {
    test('a single observation only starts a candidate', () {
      final out = MartLearner.observe(MartLearnerState.empty(), aLat, aLng);
      expect(out.changed, isTrue);
      expect(out.state.hasMart, isFalse);
      expect(out.state.candidateLat, aLat);
      expect(out.state.candidateLng, aLng);
      expect(out.state.candidateCount, 1);
      expect(out.learned, isFalse);
    });

    test('two nearby observations save the cluster centre as the mart',
        () {
      var state = MartLearner.observe(MartLearnerState.empty(), aLat, aLng)
          .state;
      final out = MartLearner.observe(state, aNearLat, aLng);
      expect(out.learned, isTrue);
      expect(out.state.hasMart, isTrue);
      expect(out.state.martCount, 2);
      expect(out.state.martLat, closeTo((aLat + aNearLat) / 2, 1e-9));
      expect(out.state.martLng, closeTo(aLng, 1e-9));
      // Candidate is consumed by the promotion.
      expect(out.state.hasCandidate, isFalse);
      state = out.state;
      expect(state.hasMart, isTrue);
    });

    test('two far-apart observations never save a mart', () {
      var state = MartLearner.observe(MartLearnerState.empty(), aLat, aLng)
          .state;
      final out = MartLearner.observe(state, bLat, bLng);
      expect(out.state.hasMart, isFalse);
      // The candidate restarts at the newest observation.
      expect(out.state.candidateLat, bLat);
      expect(out.state.candidateCount, 1);
    });

    test('an observation near the saved mart refines it (running mean)',
        () {
      var state = MartLearnerState.empty();
      state = MartLearner.observe(state, aLat, aLng).state;
      state = MartLearner.observe(state, aNearLat, aLng).state;
      final martBefore = state.martLat!;
      final out = MartLearner.observe(state, aNearLat, aLng);
      expect(out.refined, isTrue);
      expect(out.learned, isFalse);
      expect(out.state.martCount, 3);
      expect(
        out.state.martLat,
        closeTo((martBefore * 2 + aNearLat) / 3, 1e-9),
      );
    });

    test('a far cluster reaching the threshold replaces the mart', () {
      var state = MartLearnerState.empty();
      state = MartLearner.observe(state, aLat, aLng).state;
      state = MartLearner.observe(state, aNearLat, aLng).state;
      expect(state.hasMart, isTrue);
      // One far observation: mart untouched, candidate starts at B.
      var out = MartLearner.observe(state, bLat, bLng);
      expect(out.state.hasMart, isTrue);
      expect(out.state.martLat, state.martLat);
      expect(out.state.candidateCount, 1);
      // Second nearby B observation: promotion replaces the mart.
      out = MartLearner.observe(out.state, bNearLat, bLng);
      expect(out.replaced, isTrue);
      expect(out.learned, isFalse);
      expect(out.state.martLat, closeTo((bLat + bNearLat) / 2, 1e-9));
      expect(out.state.martCount, 2);
    });

    test('observing never mutates the input state', () {
      final state = MartLearnerState.empty();
      MartLearner.observe(state, aLat, aLng);
      expect(state.candidateCount, 0);
      expect(state.hasMart, isFalse);
    });
  });
}
