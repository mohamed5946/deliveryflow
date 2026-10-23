import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import 'arrival_geofence.dart';
import 'arrival_notifications.dart';

/// Background GPS tracking task handler.
///
/// Runs in a separate Dart isolate via flutter_foreground_task, so GPS
/// tracking continues even when the app is swiped away or the phone
/// is locked. Accumulates distance + route points and persists them to
/// a JSON file that the main isolate reads on demand.
///
/// File: tracking_ORDERID.json in app docs dir
/// {
///   "orderId": "...", "segment": "outgoing"|"returning",
///   "km": 1.23, "startedAt": 1234567890,
///   "lat": [...], "lng": [...],
///   "destLat": ..., "destLng": ..., "martLat": ..., "martLng": ...,
///   "finalizedLegs": {"outgoing": {km, startedAt, endedAt, lat, lng}},
///   "events": [{"type": "prompt_shown", "leg": "outgoing", "at": ...}]
/// }
///
/// v27.8: automatic arrival detection. The init data also carries the
/// destination (outgoing target) and the learned mart (return target).
/// Entering the arrival radius posts a «هل وصلت؟» prompt with a «لا»
/// action; when the 10-second countdown expires unanswered, the leg
/// is frozen into "finalizedLegs" and — for the outgoing leg — the
/// return leg starts right here in the isolate. The MAIN isolate
/// later applies the frozen legs through the exact same finalization
/// path as the manual buttons (Hive writes stay main-isolate-only).
@pragma('vm:entry-point')
class TrackingTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _sub;
  Position? _lastPos;
  Position? _lastRoutePoint;
  String _orderId = '';
  String _segment = '';
  double _km = 0;
  int _startedAt = 0;
  final List<double> _lat = [];
  final List<double> _lng = [];
  Timer? _saveTimer;

  // --- v27.8 arrival detection ---
  double? _destLat;
  double? _destLng;
  double? _martLat;
  double? _martLng;
  ArrivalGeofence? _geofence;
  final ArrivalPromptPoster _poster = ArrivalPromptPoster();
  Timer? _countdownTimer;
  Timer? _declinePollTimer;
  final Map<String, Map<String, dynamic>> _finalizedLegs = {};
  final List<Map<String, dynamic>> _events = [];

  static const double _maxAccuracyM = 50;
  static const double _minStepM = 3;
  static const double _routeStepM = 5;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final data =
        await FlutterForegroundTask.getData<String>(key: 'tracking_init');
    if (data != null) {
      try {
        final init = json.decode(data) as Map<String, dynamic>;
        _orderId = init['orderId'] as String? ?? '';
        _segment = init['segment'] as String? ?? '';
        _destLat = (init['destLat'] as num?)?.toDouble();
        _destLng = (init['destLng'] as num?)?.toDouble();
        _martLat = (init['martLat'] as num?)?.toDouble();
        _martLng = (init['martLng'] as num?)?.toDouble();
        _startedAt = DateTime.now().millisecondsSinceEpoch;
      } catch (_) {}
    }
    if (_orderId.isEmpty) {
      // No order to track (e.g. stale restart): don't sit idle with a
      // notification — shut down.
      FlutterForegroundTask.stopService();
      return;
    }

    // Load any existing progress (e.g. after service restart). The
    // file is the authority for the CURRENT leg: an auto-confirmed
    // outgoing leg flips the segment in the file without a restart.
    await _loadProgress();

    if (_finalizedLegs.containsKey('returning')) {
      // The trip already auto-completed before this restart; the main
      // isolate applies the frozen legs from the progress file.
      await _saveProgress();
      FlutterForegroundTask.stopService();
      return;
    }

    _armGeofence();
    await _poster.init();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPosition,
      onError: (_) {},
    );

    // Persist every 10s so main isolate can pick up progress anytime.
    _saveTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _saveProgress(),
    );
  }

  /// (Re)creates the geofence for the current leg from its target:
  /// the destination for outgoing, the learned mart for returning.
  void _armGeofence() {
    final target = _segment == 'returning'
        ? (lat: _martLat, lng: _martLng)
        : (lat: _destLat, lng: _destLng);
    _geofence = ArrivalGeofence(
      targetLat: target.lat,
      targetLng: target.lng,
    );
    if (_geofence!.hasTarget && !_finalizedLegs.containsKey(_segment)) {
      _addEvent('geofence_armed', _segment);
    }
  }

  void _addEvent(String type, String leg) {
    _events.add({
      'type': type,
      'leg': leg,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    if (_events.length > 60) _events.removeAt(0);
  }

  void _onPosition(Position pos) {
    if (pos.accuracy > _maxAccuracyM) return;
    final prev = _lastPos;
    _lastPos = pos;
    if (prev != null) {
      final stepM = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (stepM >= _minStepM) {
        _km += stepM / 1000.0;
        _recordRoutePoint(pos);

        // Live update to main isolate (if alive) + notification.
        FlutterForegroundTask.sendDataToMain({
          'orderId': _orderId,
          'km': _km,
          'points': _lat.length,
        });
        final label =
            _segment == 'outgoing' ? 'إلى العميل' : 'عودة للمارت';
        FlutterForegroundTask.updateService(
          notificationTitle: 'DeliveryFlow — $label',
          notificationText:
              'المسافة: ${_km.toStringAsFixed(2)} كم • يعمل في الخلفية',
        );
      }
    } else {
      _recordRoutePoint(pos);
    }
    _checkGeofence(pos);
  }

  // ------------------------------------------------------------ arrival --

  void _checkGeofence(Position pos) {
    final geo = _geofence;
    if (geo == null || !geo.hasTarget) return;
    if (_finalizedLegs.containsKey(_segment)) return;
    final signal = geo.onPosition(pos.latitude, pos.longitude, DateTime.now());
    switch (signal) {
      case ArrivalSignal.promptStarted:
        _onPromptStarted();
      case ArrivalSignal.promptCancelledLeftArea:
        _cancelPromptTimers();
        _poster.cancelLeg(_segment);
        _addEvent('prompt_cancelled', _segment);
        _saveProgress();
      case ArrivalSignal.none:
        break;
    }
  }

  Future<void> _onPromptStarted() async {
    final geo = _geofence;
    if (geo == null || geo.promptId == null) return;
    final leg = _segment;
    _addEvent('prompt_shown', leg);
    FlutterForegroundTask.sendDataToMain({
      'orderId': _orderId,
      'arrivalEvent': 'prompt_shown',
      'leg': leg,
    });
    // A «لا» recorded for an older prompt must never cancel this one;
    // the promptId check would reject it anyway, but start clean.
    await clearArrivalResponse(_orderId);
    await _poster.showPrompt(
      orderId: _orderId,
      leg: leg,
      promptId: geo.promptId!,
    );
    _saveProgress();

    _cancelPromptTimers();
    _countdownTimer = Timer(geo.confirmAfter, _onCountdownExpired);
    _declinePollTimer = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) => _pollDecline(),
    );
  }

  Future<void> _pollDecline() async {
    final geo = _geofence;
    if (geo == null || geo.phase != ArrivalPhase.prompted) return;
    final response = await readArrivalResponse(_orderId);
    if (response == null) return;
    if (response['action'] != 'no') return;
    if (response['leg'] != _segment) return;
    if (response['promptId'] != geo.promptId) return;
    if (!geo.onDecline()) return;
    final leg = _segment;
    _cancelPromptTimers();
    await _poster.cancelLeg(leg);
    await clearArrivalResponse(_orderId);
    _addEvent('declined', leg);
    FlutterForegroundTask.sendDataToMain({
      'orderId': _orderId,
      'arrivalEvent': 'declined',
      'leg': leg,
    });
    _saveProgress();
  }

  void _onCountdownExpired() {
    final geo = _geofence;
    if (geo == null) return;
    if (!geo.checkTimeout(DateTime.now())) return;
    _autoConfirmArrival();
  }

  /// The countdown expired with no «لا»: freeze this leg exactly as
  /// it stands, then either roll straight into the return leg
  /// (outgoing) or end the trip (returning). The main isolate applies
  /// the frozen leg through the manual finalization path.
  Future<void> _autoConfirmArrival() async {
    final leg = _segment;
    if (_finalizedLegs.containsKey(leg)) return;
    _cancelPromptTimers();
    await _poster.cancelLeg(leg);
    final now = DateTime.now().millisecondsSinceEpoch;
    _finalizedLegs[leg] = {
      'km': _km,
      'startedAt': _startedAt,
      'endedAt': now,
      'lat': List<double>.of(_lat),
      'lng': List<double>.of(_lng),
    };
    _addEvent('auto_confirmed', leg);
    FlutterForegroundTask.sendDataToMain({
      'orderId': _orderId,
      'autoArrival': leg,
      'arrivalEvent': 'auto_confirmed',
      'leg': leg,
    });

    if (leg == 'outgoing') {
      // Roll into the return leg in-place: fresh accumulation, the
      // mart geofence (when learned) takes over from here.
      _segment = 'returning';
      _km = 0;
      _lat.clear();
      _lng.clear();
      _lastPos = null;
      _lastRoutePoint = null;
      _startedAt = now;
      _armGeofence();
      FlutterForegroundTask.updateService(
        notificationTitle: 'DeliveryFlow — عودة للمارت',
        notificationText: 'يتم حساب مسافة التوصيل في الخلفية…',
      );
      await _saveProgress();
    } else {
      await _saveProgress();
      await _sub?.cancel();
      _saveTimer?.cancel();
      FlutterForegroundTask.stopService();
    }
  }

  void _cancelPromptTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _declinePollTimer?.cancel();
    _declinePollTimer = null;
  }

  // ------------------------------------------------------------- routes --

  void _recordRoutePoint(Position pos) {
    final last = _lastRoutePoint;
    if (last != null) {
      final d = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (d < _routeStepM) return;
    }
    _lastRoutePoint = pos;
    _lat.add(pos.latitude);
    _lng.add(pos.longitude);
    if (_lat.length > 3000) {
      _lat.removeAt(0);
      _lng.removeAt(0);
    }
  }

  Future<File> _progressFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/tracking_$_orderId.json');
  }

  Future<void> _saveProgress() async {
    try {
      final file = await _progressFile();
      await file.writeAsString(json.encode({
        'orderId': _orderId,
        'segment': _segment,
        'km': _km,
        'startedAt': _startedAt,
        'lat': _lat,
        'lng': _lng,
        'destLat': _destLat,
        'destLng': _destLng,
        'martLat': _martLat,
        'martLng': _martLng,
        'finalizedLegs': _finalizedLegs,
        'events': _events,
      }));
    } catch (_) {}
  }

  Future<void> _loadProgress() async {
    try {
      final file = await _progressFile();
      if (!await file.exists()) return;
      final data =
          json.decode(await file.readAsString()) as Map<String, dynamic>;
      if (data['orderId'] != _orderId) return;
      // The file tracks the CURRENT leg (an auto-confirmed outgoing
      // leg flips it without a service restart).
      final fileSegment = data['segment'] as String?;
      if (fileSegment != null && fileSegment.isNotEmpty) {
        _segment = fileSegment;
      }
      _km = (data['km'] as num?)?.toDouble() ?? 0;
      _startedAt = (data['startedAt'] as num?)?.toInt() ?? _startedAt;
      final lat = (data['lat'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [];
      final lng = (data['lng'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [];
      _lat.addAll(lat);
      _lng.addAll(lng);
      // Targets: the progress file echoes them, so a restarted
      // isolate keeps its geofences even if init data was re-saved
      // for another leg.
      _destLat = (data['destLat'] as num?)?.toDouble() ?? _destLat;
      _destLng = (data['destLng'] as num?)?.toDouble() ?? _destLng;
      _martLat = (data['martLat'] as num?)?.toDouble() ?? _martLat;
      _martLng = (data['martLng'] as num?)?.toDouble() ?? _martLng;
      final frozen = data['finalizedLegs'];
      if (frozen is Map) {
        for (final e in frozen.entries) {
          if (e.value is Map) {
            _finalizedLegs[e.key.toString()] =
                Map<String, dynamic>.from(e.value as Map);
          }
        }
      }
      final events = data['events'];
      if (events is List) {
        for (final e in events) {
          if (e is Map) _events.add(Map<String, dynamic>.from(e));
        }
      }
    } catch (_) {}
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _cancelPromptTimers();
    await _poster.cancelAll();
    await _saveProgress();
    await _sub?.cancel();
    _saveTimer?.cancel();
  }

  @override
  void onReceiveData(Object data) {
    // Main isolate can send a 'stop' command.
    if (data == 'stop') {
      FlutterForegroundTask.stopService();
    }
  }
}

/// Top-level entry point registered with the foreground service.
/// Must be a top-level function with the vm:entry-point pragma.
@pragma('vm:entry-point')
void trackingTaskEntryPoint() {
  FlutterForegroundTask.setTaskHandler(TrackingTaskHandler());
}
