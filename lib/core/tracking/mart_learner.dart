import 'arrival_geofence.dart';

/// v27.8: pure mart-location learning state.
///
/// Every delivery trip starts at the mart and (on a confirmed return)
/// ends there, so trip start points and return endpoints are mart
/// observations. Observations that cluster within
/// [MartLearner.clusterRadiusM] of each other [MartLearner.minObservations]
/// times save their centre as the mart; later nearby observations keep
/// refining it as a running mean. A far-away cluster that itself
/// reaches the threshold replaces the saved mart (the courier's mart
/// moved). Pure logic — persistence lives in UserSettings (Hive fields
/// 39–45) and is applied by the main isolate only.
///
/// v27.9: a mart pinned by hand on the map picker ([MartLearnerState.manual])
/// is FROZEN — observations are ignored entirely while it is set (no
/// refine, no replace, no candidate growth), so the saved point can
/// never drift away from where the courier put the pin.
class MartLearnerState {
  double? martLat;
  double? martLng;
  int martCount;
  double? candidateLat;
  double? candidateLng;
  int candidateCount;

  /// True when the saved mart was set manually on the map picker.
  bool manual;

  MartLearnerState({
    this.martLat,
    this.martLng,
    this.martCount = 0,
    this.candidateLat,
    this.candidateLng,
    this.candidateCount = 0,
    this.manual = false,
  });

  factory MartLearnerState.empty() => MartLearnerState();

  bool get hasMart => martLat != null && martLng != null;
  bool get hasCandidate => candidateLat != null && candidateLng != null;
}

class MartObservationOutcome {
  /// The new state (the input state is never mutated).
  final MartLearnerState state;

  /// Anything changed (candidate moved, mart learned/refined/replaced)
  /// — persist the new state when true.
  final bool changed;

  /// The mart was saved for the first time by this observation.
  final bool learned;

  /// A nearby observation refined the already-saved mart.
  final bool refined;

  /// A far cluster reached the threshold and replaced the saved mart.
  final bool replaced;

  const MartObservationOutcome({
    required this.state,
    this.changed = false,
    this.learned = false,
    this.refined = false,
    this.replaced = false,
  });
}

class MartLearner {
  static const double clusterRadiusM = 120;
  static const int minObservations = 2;

  static MartObservationOutcome observe(
      MartLearnerState s, double lat, double lng) {
    // v27.9: a manually pinned mart is frozen — ignore the observation
    // completely (no state change, nothing to persist).
    if (s.manual) return MartObservationOutcome(state: s);

    // Near the saved mart: fold into its running mean.
    if (s.hasMart &&
        ArrivalGeofence.distanceMeters(lat, lng, s.martLat!, s.martLng!) <=
            clusterRadiusM) {
      final n = s.martCount;
      return MartObservationOutcome(
        state: MartLearnerState(
          martLat: (s.martLat! * n + lat) / (n + 1),
          martLng: (s.martLng! * n + lng) / (n + 1),
          martCount: n + 1,
          candidateLat: s.candidateLat,
          candidateLng: s.candidateLng,
          candidateCount: s.candidateCount,
        ),
        changed: true,
        refined: true,
      );
    }

    // Near the pending candidate: grow the cluster; reaching the
    // threshold saves it as the mart.
    if (s.hasCandidate &&
        ArrivalGeofence.distanceMeters(
                lat, lng, s.candidateLat!, s.candidateLng!) <=
            clusterRadiusM) {
      final n = s.candidateCount;
      final meanLat = (s.candidateLat! * n + lat) / (n + 1);
      final meanLng = (s.candidateLng! * n + lng) / (n + 1);
      final count = n + 1;
      if (count >= minObservations) {
        return MartObservationOutcome(
          state: MartLearnerState(
            martLat: meanLat,
            martLng: meanLng,
            martCount: count,
            manual: s.manual,
          ),
          changed: true,
          learned: !s.hasMart,
          replaced: s.hasMart,
        );
      }
      return MartObservationOutcome(
        state: MartLearnerState(
          martLat: s.martLat,
          martLng: s.martLng,
          martCount: s.martCount,
          candidateLat: meanLat,
          candidateLng: meanLng,
          candidateCount: count,
          manual: s.manual,
        ),
        changed: true,
      );
    }

    // Far from everything known: (re)start the candidate cluster here.
    return MartObservationOutcome(
      state: MartLearnerState(
        martLat: s.martLat,
        martLng: s.martLng,
        martCount: s.martCount,
        candidateLat: lat,
        candidateLng: lng,
        candidateCount: 1,
        manual: s.manual,
      ),
      changed: true,
    );
  }
}
