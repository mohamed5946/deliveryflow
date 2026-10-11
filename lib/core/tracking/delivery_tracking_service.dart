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

/// Raw progress written by the background isolate's JSON file.
/// Read directly by the live trip map so it works even when the main
/// isolate was restarted mid-trip.
class LiveTripProgress {
  final String orderId;
  final String segment; // 'outgoing' | 'returning'
  final double km;
  final int startedAtMillis;
  final List<double> lat;
  final List<double> lng;

  const LiveTripProgress({
    required this.orderId,
    required this.segment,
    required this.km,
    required this.startedAtMillis,
    required this.lat,
    required this.lng,
  });

  int get pointCount =>
      lat.length < lng.length ? lat.length : lng.length;
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

  /// The order id currently tracked by this service instance (null when
  /// idle). Used to stop tracking when the tracked order is deleted.
  String? get trackingOrderId => _trackingOrderId;

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
    // Guard: never start on top of a leaked/stale service (e.g. after a
    // crash) — the plugin throws ServiceAlreadyStartedException.
    await _stopBackgroundTracking();

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
    try {
      await FlutterForegroundTask.startService(
        notificationTitle: 'DeliveryFlow — $label',
        notificationText: 'يتم حساب مسافة التوصيل في الخلفية…',
        callback: trackingTaskEntryPoint,
      );
    } catch (_) {
      throw StateError('تعذر تشغيل التتبع في الخلفية');
    }

    // Verify the service actually came up — a silent no-start is what
    // burned us before (zero GPS fixes were ever requested because the
    // service never started). Poll briefly: the native side flips its
    // running state asynchronously after startService returns.
    var running = false;
    for (var i = 0; i < 10; i++) {
      if (await FlutterForegroundTask.isRunningService) {
        running = true;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (!running) {
      throw StateError('تعذر تشغيل التتبع في الخلفية');
    }

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
      // Poll until the background isolate actually stops (up to ~6s).
      // A fixed delay is not enough on slow devices: restarting the
      // service while the old one is still alive throws
      // ServiceAlreadyStartedException and kills the return leg.
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!await FlutterForegroundTask.isRunningService) break;
      }
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    }
    _uiTimer?.cancel();
    _uiTimer = null;
    _trackingOrderId = null;
    _segment = null;
    _segmentStart = null;
  }

  /// Re-attaches to an in-progress background tracking session, e.g.
  /// after the app was killed/swiped away and reopened mid-trip. The
  /// background isolate keeps writing its progress file independently;
  /// this restores the main-isolate bookkeeping so live snapshots flow
  /// again. Returns true when a session for [entryId] was recovered.
  Future<bool> recoverTracking(String entryId) async {
    if (_trackingOrderId != null) return true;
    final running = await FlutterForegroundTask.isRunningService;
    final progress = await _readProgress(entryId);
    if (!running || progress == null) return false;
    if (progress['orderId'] != entryId) return false;
    _trackingOrderId = entryId;
    _segment =
        (progress['segment'] as String?) == 'returning'
            ? TrackingSegment.returning
            : TrackingSegment.outgoing;
    _segmentStart = DateTime.fromMillisecondsSinceEpoch(
      (progress['startedAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _emitSnapshotFromFile(),
    );
    return true;
  }

  /// Live progress written by the background isolate for [orderId],
  /// or null when nothing is being tracked for it.
  Future<LiveTripProgress?> readLiveProgress(String orderId) async {
    final p = await _readProgress(orderId);
    if (p == null || p['orderId'] != orderId) return null;
    final lat =
        ((p['lat'] as List?) ?? [])
            .map((e) => (e as num).toDouble())
            .toList();
    final lng =
        ((p['lng'] as List?) ?? [])
            .map((e) => (e as num).toDouble())
            .toList();
    return LiveTripProgress(
      orderId: orderId,
      segment: (p['segment'] as String?) ?? '',
      km: (p['km'] as num?)?.toDouble() ?? 0,
      startedAtMillis:
          (p['startedAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      lat: lat,
      lng: lng,
    );
  }

  /// Courier picked up the order from the mart and pressed "بدأ التوصيل".
  ///
  /// Background tracking is started AND verified BEFORE the order is
  /// marked as tracking in the DB — an order must never sit in
  /// "tracking" state with no tracking actually running.
  Future<void> startOutgoing({
    required String dateKey,
    required String entryId,
  }) async {
    final ok = await ensurePermissions();
    if (!ok) throw StateError('Location permission not granted');
    await _startBackgroundTracking(
      orderId: entryId,
      segment: TrackingSegment.outgoing,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.updateOrderEntry(
      dateKey: dateKey,
      entryId: entryId,
      status: 1,
      pickupTimeMillis: now,
    );
  }

  /// Starts the outgoing leg in MANUAL mode (no background tracking).
  /// [kmOut] may be 0 when the courier doesn't know the distance yet —
  /// they can fill it later via the manual-edit affordance on the trip
  /// screen. The order is never blocked on GPS.
  Future<void> startManualOutgoing({
    required String dateKey,
    required String entryId,
    double kmOut = 0,
  }) async {
    if (kmOut < 0) throw ArgumentError('Distance cannot be negative');
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.updateOrderEntry(
      dateKey: dateKey,
      entryId: entryId,
      status: 1,
      pickupTimeMillis: now,
      kmOut: kmOut,
    );
  }

  /// Restarts tracking for [entryId]'s current leg without modifying the
  /// order's DB state. Used to resume after the system killed the service
  /// mid-trip (the handler reloads partial progress from its file).
  Future<void> resumeTracking({
    required String entryId,
    required TrackingSegment segment,
  }) async {
    await _startBackgroundTracking(
      orderId: entryId,
      segment: segment,
    );
  }

  /// Starts (or restarts) the return-leg background tracking, verified.
  /// Used by [markDelivered] and by the UI retry after a failed start.
  Future<void> startReturnLeg({required String entryId}) async {
    await _startBackgroundTracking(
      orderId: entryId,
      segment: TrackingSegment.returning,
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

    // Snap the ACTUALLY traveled trail to real roads (map matching).
    // Sanity guard: the live GPS sum is the anchor — only accept the
    // snapped value if it's within a sane band around it, otherwise a
    // bad match could wildly inflate the distance.
    final snapped = await _snap.snapRoute(lat: outLat, lng: outLng);
    final finalKmOut = _saneFinalKm(gpsKm: kmOut, snappedKm: snapped?.distanceKm);
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

    // Start return leg (verified — throws loudly on failure so the UI
    // can offer a retry instead of silently losing the return trip).
    await startReturnLeg(entryId: entryId);
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
        _saneFinalKm(gpsKm: kmBack, snappedKm: snapped?.distanceKm);
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

  /// Picks the final distance for a leg. The live GPS sum is the anchor
  /// (it measures what was actually traveled). A snapped road distance
  /// is only accepted when it sits within a sane band around the GPS
  /// sum — this guarantees a bad map-match can never inflate (or
  /// collapse) the recorded distance.
  double _saneFinalKm({required double gpsKm, double? snappedKm}) {
    if (snappedKm == null || snappedKm <= 0) return gpsKm;
    if (gpsKm <= 0) return snappedKm;
    if (snappedKm >= gpsKm * 0.5 && snappedKm <= gpsKm * 2.5) {
      return snappedKm;
    }
    return gpsKm;
  }

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
