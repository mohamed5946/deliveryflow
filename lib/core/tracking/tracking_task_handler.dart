import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

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
///   "lat": [...], "lng": [...]
/// }
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
        _startedAt = DateTime.now().millisecondsSinceEpoch;
      } catch (_) {}
    }
    if (_orderId.isEmpty) return;

    // Load any existing progress (e.g. after service restart).
    await _loadProgress();

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

  void _onPosition(Position pos) {
    if (pos.accuracy > _maxAccuracyM) return;
    final prev = _lastPos;
    _lastPos = pos;
    if (prev == null) {
      _recordRoutePoint(pos);
      return;
    }
    final stepM = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      pos.latitude,
      pos.longitude,
    );
    if (stepM < _minStepM) return;
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
    } catch (_) {}
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
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
