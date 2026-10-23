import 'dart:math' as math;

/// v27.8: pure arrival-geofence state machine for ONE delivery leg.
///
/// The background tracking isolate feeds it GPS positions; when the
/// courier enters [arrivalRadiusM] of the leg's target, the machine
/// asks for an arrival prompt («هل وصلت؟») and starts the confirmation
/// countdown. If the courier does not decline within [confirmAfter],
/// [checkTimeout] confirms the arrival. A decline suppresses
/// re-prompting until the courier leaves the wider [rearmRadiusM] and
/// comes back. Leaving the wide radius while a prompt is up cancels
/// the prompt — driving PAST the destination must never auto-confirm.
///
/// No platform calls in here (haversine is computed locally) so the
/// whole machine is unit-testable with fake positions and times.
enum ArrivalPhase { outside, prompted, suppressed, confirmed }

enum ArrivalSignal {
  none,

  /// Entered the arrival radius — show the prompt + start countdown.
  promptStarted,

  /// Left the wide radius while prompted — cancel the prompt.
  promptCancelledLeftArea,
}

class ArrivalGeofence {
  ArrivalGeofence({
    this.targetLat,
    this.targetLng,
    this.arrivalRadiusM = 75,
    this.rearmRadiusM = 200,
    this.confirmAfter = const Duration(seconds: 10),
  });

  final double? targetLat;
  final double? targetLng;
  final double arrivalRadiusM;
  final double rearmRadiusM;
  final Duration confirmAfter;

  ArrivalPhase phase = ArrivalPhase.outside;
  DateTime? promptedAt;
  double? lastDistanceM;

  bool get hasTarget => targetLat != null && targetLng != null;

  /// Identity of the live prompt (its start instant). A «لا» response
  /// is only honoured when it carries this id, so a stale tap from an
  /// earlier prompt can never cancel a later one.
  int? get promptId => promptedAt?.millisecondsSinceEpoch;

  static double distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusM = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusM * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  /// Feed one GPS position. Returns [ArrivalSignal.promptStarted]
  /// exactly once per entry into the arrival radius.
  ArrivalSignal onPosition(double lat, double lng, DateTime now) {
    if (!hasTarget || phase == ArrivalPhase.confirmed) {
      return ArrivalSignal.none;
    }
    final d = distanceMeters(lat, lng, targetLat!, targetLng!);
    lastDistanceM = d;
    switch (phase) {
      case ArrivalPhase.outside:
        if (d <= arrivalRadiusM) {
          phase = ArrivalPhase.prompted;
          promptedAt = now;
          return ArrivalSignal.promptStarted;
        }
      case ArrivalPhase.prompted:
        if (d > rearmRadiusM) {
          phase = ArrivalPhase.outside;
          promptedAt = null;
          return ArrivalSignal.promptCancelledLeftArea;
        }
      case ArrivalPhase.suppressed:
        if (d > rearmRadiusM) phase = ArrivalPhase.outside;
      case ArrivalPhase.confirmed:
        break;
    }
    return ArrivalSignal.none;
  }

  /// The courier tapped «لا». Suppresses re-prompting until the
  /// position exits [rearmRadiusM] (handled in [onPosition]).
  bool onDecline() {
    if (phase != ArrivalPhase.prompted) return false;
    phase = ArrivalPhase.suppressed;
    promptedAt = null;
    return true;
  }

  /// True (once) when the confirmation countdown has expired with no
  /// decline — the arrival is auto-confirmed.
  bool checkTimeout(DateTime now) {
    if (phase != ArrivalPhase.prompted || promptedAt == null) return false;
    if (now.difference(promptedAt!) < confirmAfter) return false;
    phase = ArrivalPhase.confirmed;
    return true;
  }

  /// Back to a pristine state (a new leg begins).
  void reset() {
    phase = ArrivalPhase.outside;
    promptedAt = null;
    lastDistanceM = null;
  }
}
