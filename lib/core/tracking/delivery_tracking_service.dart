import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import '../database/database_service.dart';
import '../providers.dart';
import 'route_snap_service.dart';
import 'tracking_task_handler.dart';

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
/// Tracking runs in a BACKGROUND isolate (via flutter_foreground_task),
/// so it keeps recording even when the app is swiped away or the phone
/// is locked. Progress is shared via a JSON file + live data port.
///
/// Flow:
/// 1. [startOutgoing] — courier pressed "بدأ التوصيل" at the mart.
/// 2. [markDelivered] — courier pressed "وصلت للعميل".
/// 3. [markArrivedAtMart] — courier pressed "وصلت للمارت".
class DeliveryTrackingService {
  DeliveryTrackingService(this._db) {
    // Listen for live updates from the background isolate.
    FlutterForegroundTask.addTaskDataCallback(_onBackgroundData);
  }

  final DatabaseService _db;
  final RouteSnapService _snap = RouteSnapService();

  final _snapshotController = StreamController<TrackingSnapshot>.broadcast();
  Stream<TrackingSnapshot> get snapshots => _snapshotController.stream;

  String? _trackingOrderId;
  TrackingSegment? _segment;
  DateTime? _segmentStart;
  Timer? _uiTimer;

  bool get isTracking => _trackingOrderId != null;

  void _onBackgroundData(Object data) {
    if (data is! Map) return;
    final orderId = data['orderId'] as String?;
    final km = (data['km'] as num?)?.toDouble() ?? 0;
    if (orderId == null || orderId != _trackingOrderId) return;
    final segment = _segment;
    final start = _segmentStart;
    if (segment == null || start == null) return;
    _snapshotController.add(TrackingSnapshot(
      orderId: orderId,
      segment: segment,
      kmSoFar: km,
      elapsed: DateTime.now().difference(start),
      startedAt: start,
    ));
  }

  /// Requests all location permissions needed for tracking.
  Future<bool> ensurePermissions() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return false;
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

  Future<File> _progressFile(String orderId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/tracking_$orderId.json');
  }

  /// Reads the accumulated progress written by the background isolate.
  Future<Map<String, dynamic>?> _readProgress(String orderId) async {
    try {
      final file = await _progressFile(orderId);
      if (!await file.exists()) return null;
      return json.decode(await file.readAsString())
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteProgress(String orderId) async {
    try {
      final file = await _progressFile(orderId);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _startBackgroundTracking({
    required String orderId,
    required TrackingSegment segment,
  }) async {
    // Save init data for the background isolate.
    await FlutterForegroundTask.saveData(
      key: 'tracking_init',
      value: json.encode({
        'orderId': orderId,
        'segment': segment == TrackingSegment.outgoing
            ? 'outgoing'
            : 'returning',
      }),
    );

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
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    final label =
        segment == TrackingSegment.outgoing ? 'إلى العميل' : 'عودة للمارت';
    await FlutterForegroundTask.startService(
      notificationTitle: 'DeliveryFlow — $label',
      notificationText: 'يتم حساب مسافة التوصيل في الخلفية…',
      callback: trackingTaskEntryPoint,
    );

    _trackingOrderId = orderId;
    _segment = segment;
    _segmentStart = DateTime.now();

    // Throttled UI ticks for elapsed-time display.
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _emitSnapshotFromFile();
    });
  }

  Future<void> _emitSnapshotFromFile() async {
    final orderId = _trackingOrderId;
    final segment = _segment;
    final start = _segmentStart;
    if (orderId == null || segment == null || start == null) return;
    final progress = await _readProgress(orderId);
    final km = (progress?['km'] as num?)?.toDouble() ?? 0;
    _snapshotController.add(TrackingSnapshot(
      orderId: orderId,
      segment: segment,
      kmSoFar: km,
      elapsed: DateTime.now().difference(start),
      startedAt: start,
    ));
  }

  Future<void> _stopBackgroundTracking() async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask('stop');
      await Future.delayed(const Duration(seconds: 2));
      await FlutterForegroundTask.stopService();
    }
    _uiTimer?.cancel();
    _uiTimer = null;
    _trackingOrderId = null;
    _segment = null;
    _segmentStart = null;
  }

  /// Courier picked up the order from the mart and pressed "بدأ التوصيل".
  Future<void> startOutgoing({
    required String dateKey,
    required String entryId,
  }) async {
    final ok = await ensurePermissions();
    if (!ok) throw StateError('Location permission not granted');
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.updateOrderEntry(
      dateKey: dateKey,
      entryId: entryId,
      status: 1,
      pickupTimeMillis: now,
    );
    await _startBackgroundTracking(
      orderId: entryId,
      segment: TrackingSegment.outgoing,
    );
  }

  /// Courier arrived at the customer and pressed "وصلت للعميل".
  Future<double> markDelivered({
    required String dateKey,
    required String entryId,
  }) async {
    final progress = await _readProgress(entryId);
    final kmOut = (progress?['km'] as num?)?.toDouble() ?? 0;
    final startedAt =
        (progress?['startedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;
    final durationSec =
        DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(startedAt),
        ).inSeconds;
    final outLat = ((progress?['lat'] as List?) ?? [])
        .map((e) => (e as num).toDouble())
        .toList();
    final outLng = ((progress?['lng'] as List?) ?? [])
        .map((e) => (e as num).toDouble())
        .toList();

    await _stopBackgroundTracking();
    await _deleteProgress(entryId);

    // Snap to real roads for Google-Maps-like accuracy.
    final snapped = await _snap.snapRoute(lat: outLat, lng: outLng);
    final finalKmOut =
        snapped != null && snapped.distanceKm > 0 ? snapped.distanceKm : kmOut;
    final roadLat =
        snapped?.geometry.map((p) => p.latitude).toList() ??
            const <double>[];
    final roadLng =
        snapped?.geometry.map((p) => p.longitude).toList() ??
            const <double>[];

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
      roadOutLat: roadLat,
      roadOutLng: roadLng,
    );

    // Start return leg.
    await _startBackgroundTracking(
      orderId: entryId,
      segment: TrackingSegment.returning,
    );
    return finalKmOut;
  }

  /// Courier arrived back at the mart and pressed "وصلت للمارت".
  Future<void> markArrivedAtMart({
    required String dateKey,
    required String entryId,
  }) async {
    final progress = await _readProgress(entryId);
    final kmBack = (progress?['km'] as num?)?.toDouble() ?? 0;
    final startedAt =
        (progress?['startedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;
    final durationSec =
        DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(startedAt),
        ).inSeconds;
    final backLat = ((progress?['lat'] as List?) ?? [])
        .map((e) => (e as num).toDouble())
        .toList();
    final backLng = ((progress?['lng'] as List?) ?? [])
        .map((e) => (e as num).toDouble())
        .toList();

    await _stopBackgroundTracking();
    await _deleteProgress(entryId);

    final snapped = await _snap.snapRoute(lat: backLat, lng: backLng);
    final finalKmBack =
        snapped != null && snapped.distanceKm > 0 ? snapped.distanceKm : kmBack;
    final roadLat =
        snapped?.geometry.map((p) => p.latitude).toList() ??
            const <double>[];
    final roadLng =
        snapped?.geometry.map((p) => p.longitude).toList() ??
            const <double>[];

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
      roadBackLat: roadLat,
      roadBackLng: roadLng,
    );
  }

  /// Cancels tracking without saving (e.g. order deleted mid-trip).
  Future<void> cancelTracking() async {
    final orderId = _trackingOrderId;
    await _stopBackgroundTracking();
    if (orderId != null) await _deleteProgress(orderId);
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100;

  void dispose() {
    _snapshotController.close();
    _uiTimer?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onBackgroundData);
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
