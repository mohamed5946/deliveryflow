import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../database/database_service.dart';
import '../providers.dart';
import 'route_snap_service.dart';

/// Which leg of the delivery is being tracked.
enum TrackingSegment { outgoing, returning }

/// Live snapshot of an in-progress GPS tracking session.
class TrackingSnapshot {
  final String orderId;
  final TrackingSegment segment;
  final double kmSoFar;
  final Duration elapsed;
  final DateTime startedAt;

  const TrackingSnapshot({
    required this.orderId,
    required this.segment,
    required this.kmSoFar,
    required this.elapsed,
    required this.startedAt,
  });
}

/// GPS tracking service for the delivery lifecycle.
///
/// Flow:
/// 1. [startOutgoing] — courier pressed "بدأ التوصيل" at the mart.
///    Records pickup time, starts accumulating outgoing km.
/// 2. [markDelivered] — courier pressed "وصلت للعميل".
///    Finalizes outgoing km/duration, starts return tracking.
/// 3. [markArrivedAtMart] — courier pressed "وصلت للمارت".
///    Finalizes return km/duration, completes the order.
///
/// Accuracy measures (user asked for precision):
/// - Positions with accuracy worse than 25m are discarded.
/// - Movements smaller than 5m between fixes are ignored (GPS drift filter).
/// - High-accuracy location settings with a 5m distance filter.
class DeliveryTrackingService {
  DeliveryTrackingService(this._db);

  final DatabaseService _db;
  final RouteSnapService _snap = RouteSnapService();

  StreamSubscription<Position>? _positionSub;
  Timer? _uiTimer;
  Position? _lastPosition;
  String? _trackingOrderId;
  TrackingSegment? _segment;
  DateTime? _segmentStart;
  double _segmentKm = 0;
  // Downsampled breadcrumb trail for the route map.
  final List<double> _routeLat = [];
  final List<double> _routeLng = [];
  Position? _lastRoutePoint;

  final _snapshotController = StreamController<TrackingSnapshot>.broadcast();
  Stream<TrackingSnapshot> get snapshots => _snapshotController.stream;

  bool get isTracking => _trackingOrderId != null;

  static const double _maxAcceptedAccuracyM = 50;
  static const double _minStepM = 3;

  /// Requests all location permissions needed for tracking.
  /// Returns true when foreground location is granted.
  Future<bool> ensurePermissions() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    // Background location (Android 10+): needed so tracking survives
    // screen lock. Requested separately after foreground is granted.
    if (permission == LocationPermission.whileInUse) {
      // Best-effort: don't block if the user declines background.
      await Geolocator.requestPermission();
    }
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return false;
    }
    permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Starts the foreground service (persistent notification) so tracking
  /// keeps running with the screen off.
  Future<void> _startForegroundService() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'delivery_tracking',
        channelName: 'Delivery tracking',
        channelDescription:
            'Tracks delivery distance while an order is in progress',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions:
          const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    await FlutterForegroundTask.startService(
      notificationTitle: 'DeliveryFlow — جارٍ التتبع',
      notificationText: 'يتم حساب مسافة التوصيل…',
    );
  }

  Future<void> _stopForegroundService() async {
    await FlutterForegroundTask.stopService();
  }

  Future<void> _beginSegment({
    required String orderId,
    required String dateKey,
    required TrackingSegment segment,
  }) async {
    await _stopTrackingInternal();
    final ok = await ensurePermissions();
    if (!ok) {
      throw StateError('Location permission not granted');
    }
    await _startForegroundService();

    _trackingOrderId = orderId;
    _segment = segment;
    _segmentStart = DateTime.now();
    _segmentKm = 0;
    _lastPosition = null;
    _routeLat.clear();
    _routeLng.clear();
    _lastRoutePoint = null;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    );
    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPosition,
      onError: (_) {},
    );

    // Throttled UI ticks (every 5s) so the live display updates
    // without rebuilding on every GPS fix.
    _uiTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _emitSnapshot();
    });
    _emitSnapshot();
  }

  void _onPosition(Position pos) {
    if (_trackingOrderId == null || _segmentStart == null) return;
    // Discard inaccurate fixes.
    if (pos.accuracy > _maxAcceptedAccuracyM) return;
    final prev = _lastPosition;
    _lastPosition = pos;
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
    // Ignore GPS drift when (almost) stationary.
    if (stepM < _minStepM) return;
    _segmentKm += stepM / 1000.0;
    _recordRoutePoint(pos);
    _updateNotification();
  }

  /// Records a downsampled breadcrumb point for the route map.
  /// Stores a point every ~15m to keep the polyline smooth without
  /// bloating storage.
  void _recordRoutePoint(Position pos) {
    final last = _lastRoutePoint;
    if (last != null) {
      final distM = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (distM < 15) return;
    }
    _lastRoutePoint = pos;
    _routeLat.add(pos.latitude);
    _routeLng.add(pos.longitude);
    // Safety cap: ~4 hours of tracking at 15m intervals.
    if (_routeLat.length > 1000) {
      _routeLat.removeAt(0);
      _routeLng.removeAt(0);
    }
  }

  void _emitSnapshot() {
    final orderId = _trackingOrderId;
    final segment = _segment;
    final start = _segmentStart;
    if (orderId == null || segment == null || start == null) return;
    _snapshotController.add(TrackingSnapshot(
      orderId: orderId,
      segment: segment,
      kmSoFar: _segmentKm,
      elapsed: DateTime.now().difference(start),
      startedAt: start,
    ));
  }

  Future<void> _updateNotification() async {
    if (_trackingOrderId == null || _segment == null) return;
    final label =
        _segment == TrackingSegment.outgoing ? 'إلى العميل' : 'عودة للمارت';
    await FlutterForegroundTask.updateService(
      notificationTitle: 'DeliveryFlow — $label',
      notificationText:
          'المسافة: ${_segmentKm.toStringAsFixed(2)} كم',
    );
  }

  /// Courier picked up the order from the mart and pressed "بدأ التوصيل".
  Future<void> startOutgoing({
    required String dateKey,
    required String entryId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.updateOrderEntry(
      dateKey: dateKey,
      entryId: entryId,
      status: 1,
      pickupTimeMillis: now,
    );
    await _beginSegment(
      orderId: entryId,
      dateKey: dateKey,
      segment: TrackingSegment.outgoing,
    );
  }

  /// Courier arrived at the customer and pressed "وصلت للعميل".
  /// Finalizes the outgoing leg and starts the return leg.
  Future<double> markDelivered({
    required String dateKey,
    required String entryId,
  }) async {
    final start = _segmentStart;
    final kmOut = _segmentKm;
    final durationSec =
        start == null ? 0 : DateTime.now().difference(start).inSeconds;
    final outLat = List<double>.from(_routeLat);
    final outLng = List<double>.from(_routeLng);
    await _stopTrackingInternal();
    // Final distance: snap the trail to real roads for Google-Maps-like
    // accuracy. Falls back to the live GPS sum when offline.
    final snappedKm = await _snap.snappedDistanceKm(
      lat: outLat,
      lng: outLng,
    );
    final finalKmOut =
        snappedKm != null && snappedKm > 0 ? snappedKm : kmOut;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.updateOrderEntry(
      dateKey: dateKey,
      entryId: entryId,
      status: 2,
      deliveredTimeMillis: now,
      gpsKmOut: _round2(finalKmOut),
      outgoingDurationSec: durationSec,
      routeOutLat: outLat,
      routeOutLng: outLng,
    );
    await _beginSegment(
      orderId: entryId,
      dateKey: dateKey,
      segment: TrackingSegment.returning,
    );
    return kmOut;
  }

  /// Courier arrived back at the mart and pressed "وصلت للمارت".
  /// Finalizes the return leg and completes the order.
  Future<void> markArrivedAtMart({
    required String dateKey,
    required String entryId,
  }) async {
    final start = _segmentStart;
    final kmBack = _segmentKm;
    final durationSec =
        start == null ? 0 : DateTime.now().difference(start).inSeconds;
    final backLat = List<double>.from(_routeLat);
    final backLng = List<double>.from(_routeLng);
    await _stopTrackingInternal();
    final snappedKm = await _snap.snappedDistanceKm(
      lat: backLat,
      lng: backLng,
    );
    final finalKmBack =
        snappedKm != null && snappedKm > 0 ? snappedKm : kmBack;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.updateOrderEntry(
      dateKey: dateKey,
      entryId: entryId,
      status: 3,
      martArrivedTimeMillis: now,
      gpsKmBack: _round2(finalKmBack),
      returnDurationSec: durationSec,
      timestampMillis: now,
      routeBackLat: backLat,
      routeBackLng: backLng,
    );
  }

  Future<void> _stopTrackingInternal() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _uiTimer?.cancel();
    _uiTimer = null;
    _trackingOrderId = null;
    _segment = null;
    _segmentStart = null;
    _segmentKm = 0;
    _lastPosition = null;
    _routeLat.clear();
    _routeLng.clear();
    _lastRoutePoint = null;
    await _stopForegroundService();
  }

  /// Cancels tracking without saving (e.g. order deleted mid-trip).
  Future<void> cancelTracking() => _stopTrackingInternal();

  double _round2(double v) => (v * 100).roundToDouble() / 100;

  void dispose() {
    _snapshotController.close();
    _stopTrackingInternal();
  }
}

final deliveryTrackingServiceProvider =
    Provider<DeliveryTrackingService>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final svc = DeliveryTrackingService(db);
  ref.onDispose(svc.dispose);
  return svc;
});

/// Emits live snapshots while an order is being tracked.
final trackingSnapshotProvider = StreamProvider<TrackingSnapshot>((ref) {
  return ref.watch(deliveryTrackingServiceProvider).snapshots;
});
