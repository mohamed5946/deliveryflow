import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import '../database/database_service.dart';
import '../database/models.dart';
import '../logging/app_log_service.dart';
import '../providers.dart';
import 'mart_learner.dart';
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
  DeliveryTrackingService(
    this._db, {
    AppLogService? log,
    UserSettings Function()? readSettings,
    Future<void> Function(UserSettings Function(UserSettings) apply)?
        updateSettings,
  })  : _log = log,
        _readSettings = readSettings,
        _updateSettings = updateSettings {
    // Listen for live updates from the background isolate.
    FlutterForegroundTask.addTaskDataCallback(_onBackgroundData);
  }

  final DatabaseService _db;

  /// v27.2: optional diagnostics log (null in tests — no-ops).
  final AppLogService? _log;

  /// v27.8: settings access for the learned mart location. Reads go
  /// through the SettingsNotifier's live state and writes through its
  /// update() so a concurrent profile edit can never clobber the
  /// learned mart (or vice versa). Null in tests — the service then
  /// talks to the database directly.
  final UserSettings Function()? _readSettings;
  final Future<void> Function(UserSettings Function(UserSettings) apply)?
      _updateSettings;

  final RouteSnapService _snap = RouteSnapService();

  final _snapshotController = StreamController<TrackingSnapshot>.broadcast();
  Stream<TrackingSnapshot> get snapshots => _snapshotController.stream;

  String? _trackingOrderId;
  String? _trackingDateKey;
  TrackingSegment? _segment;
  DateTime? _segmentStart;
  Timer? _uiTimer;

  /// v27.8: guards re-entrant auto-arrival application (the live-data
  /// callback and the 5s file tick can both notice a frozen leg).
  bool _processingAuto = false;

  /// Arrival events from the progress file already mirrored into the
  /// diagnostics log by this service instance ('type|leg|at' keys).
  final Set<String> _mirroredArrivalEvents = {};

  bool get isTracking => _trackingOrderId != null;

  /// The order id currently tracked by this service instance (null when
  /// idle). Used to stop tracking when the tracked order is deleted.
  String? get trackingOrderId => _trackingOrderId;

  void _onBackgroundData(Object data) {
    if (data is! Map) return;
    final orderId = data['orderId'] as String?;
    if (orderId == null || orderId != _trackingOrderId) return;
    // v27.8: the background isolate auto-confirmed an arrival — apply
    // the frozen leg now (the app is alive, so this is immediate).
    if (data['autoArrival'] is String) {
      final dateKey = _trackingDateKey;
      if (dateKey != null) {
        unawaited(processAutoArrivals(dateKey: dateKey, entryId: orderId));
      }
      return;
    }
    final km = (data['km'] as num?)?.toDouble() ?? 0;
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
    double? destLat,
    double? destLng,
  }) async {
    // Guard: never start on top of a leaked/stale service (e.g. after a
    // crash) — the plugin throws ServiceAlreadyStartedException.
    await _stopBackgroundTracking();

    // v27.8: the learned mart (the return leg's arrival target) rides
    // along in the init data, next to the destination when known.
    final settings = _readSettings?.call() ?? _db.settings;

    // Save init data for the background isolate.
    await FlutterForegroundTask.saveData(
      key: 'tracking_init',
      value: json.encode({
        'orderId': orderId,
        'segment': segment == TrackingSegment.outgoing
            ? 'outgoing'
            : 'returning',
        'destLat': destLat,
        'destLng': destLng,
        'martLat': settings.martLat,
        'martLng': settings.martLng,
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
    // v27.8: keep the diagnostics log current with the isolate's
    // arrival events, and apply a frozen leg even if the live-data
    // message was missed (e.g. main isolate was briefly dead).
    if (progress != null) {
      _mirrorArrivalEvents(progress);
      final frozen = progress['finalizedLegs'];
      final dateKey = _trackingDateKey;
      if (frozen is Map && frozen.isNotEmpty && dateKey != null) {
        unawaited(processAutoArrivals(dateKey: dateKey, entryId: orderId));
      }
    }
  }

  /// Mirrors the background isolate's arrival events (prompt shown,
  /// declined, auto-confirmed, geofence armed…) into the diagnostics
  /// log — each event exactly once per service instance.
  void _mirrorArrivalEvents(Map<String, dynamic> progress) {
    final events = progress['events'];
    if (events is! List) return;
    final orderId = progress['orderId'];
    for (final e in events) {
      if (e is! Map) continue;
      final type = e['type']?.toString() ?? '';
      final leg = e['leg']?.toString() ?? '';
      final at = e['at'];
      if (!_mirroredArrivalEvents.add('$type|$leg|$at')) continue;
      switch (type) {
        case 'prompt_shown':
          _log?.info(
            AppLogCategory.notifications,
            'Arrival prompt shown ($leg) for entry $orderId',
          );
        case 'declined':
          _log?.info(
            AppLogCategory.notifications,
            'Arrival prompt declined ($leg) for entry $orderId — '
            'auto-confirm suppressed until the area is re-entered',
          );
        case 'auto_confirmed':
          _log?.info(
            AppLogCategory.tracking,
            'Arrival auto-confirmed ($leg) for entry $orderId',
          );
        case 'geofence_armed':
          _log?.info(
            AppLogCategory.tracking,
            'Arrival geofence armed ($leg) for entry $orderId',
          );
        case 'prompt_cancelled':
          _log?.info(
            AppLogCategory.tracking,
            'Arrival prompt cancelled ($leg) for entry $orderId — '
            'left the arrival area before confirming',
          );
      }
    }
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
    double? destLat,
    double? destLng,
  }) async {
    _trackingDateKey = dateKey;
    try {
      final ok = await ensurePermissions();
      if (!ok) throw StateError('Location permission not granted');
      await _startBackgroundTracking(
        orderId: entryId,
        segment: TrackingSegment.outgoing,
        destLat: destLat,
        destLng: destLng,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.updateOrderEntry(
        dateKey: dateKey,
        entryId: entryId,
        status: 1,
        pickupTimeMillis: now,
      );
      _log?.info(
        AppLogCategory.tracking,
        'Tracking started (outgoing) for entry $entryId on $dateKey',
      );
    } catch (e) {
      _log?.error(
        AppLogCategory.tracking,
        'Tracking start FAILED (outgoing) for entry $entryId on $dateKey',
        error: e,
      );
      rethrow;
    }
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
    _trackingDateKey = dateKey;
    if (kmOut < 0) throw ArgumentError('Distance cannot be negative');
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.updateOrderEntry(
      dateKey: dateKey,
      entryId: entryId,
      status: 1,
      pickupTimeMillis: now,
      kmOut: kmOut,
    );
    _log?.info(
      AppLogCategory.tracking,
      'Manual outgoing started for entry $entryId on $dateKey '
      '(kmOut $kmOut)',
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
    _trackingDateKey = dateKey;
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
    _log?.info(
      AppLogCategory.tracking,
      'Outgoing leg finalized for entry $entryId: gps=${kmOut}km, '
      'osrm=${snapped?.distanceKm}km, chosen=${finalKmOut}km',
    );
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

    // v27.8: the trip's start point is a mart observation (trips
    // start at the mart) — feed the mart learner.
    if (outLat.isNotEmpty && outLng.isNotEmpty) {
      await _applyMartObservation(outLat.first, outLng.first);
    }

    // Start return leg (verified — throws loudly on failure so the UI
    // can offer a retry instead of silently losing the return trip).
    try {
      await startReturnLeg(entryId: entryId);
    } catch (e) {
      _log?.error(
        AppLogCategory.tracking,
        'Return-leg tracking start FAILED for entry $entryId '
        '(outgoing leg was saved)',
        error: e,
      );
      rethrow;
    }
    return finalKmOut;
  }

  /// Courier arrived back at the mart and pressed "وصلت للمارت".
  Future<void> markArrivedAtMart({
    required String dateKey,
    required String entryId,
  }) async {
    _trackingDateKey = dateKey;
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
    _log?.info(
      AppLogCategory.tracking,
      'Return leg finalized for entry $entryId: gps=${kmBack}km, '
      'osrm=${snapped?.distanceKm}km, chosen=${finalKmBack}km',
    );
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

    // v27.8: a confirmed return endpoint is a mart observation.
    if (backLat.isNotEmpty && backLng.isNotEmpty) {
      await _applyMartObservation(backLat.last, backLng.last);
    }
  }

  // --------------------------------------------------- v27.8 arrivals --

  OrderEntry? _entryFor(String dateKey, String entryId) {
    final record = _db.orderRecord(dateKey);
    if (record == null) return null;
    for (final e in record.entries) {
      if (e.id == entryId) return e;
    }
    return null;
  }

  /// Applies any legs the background isolate auto-confirmed (frozen
  /// in the progress file) through the SAME finalization transitions
  /// as the manual «وصلت للعميل» / «وصلت للمارت» buttons — OSRM snap,
  /// sanity guard, Hive update, mart observation. Runs when the live
  /// isolate reports an auto-arrival, on the 5s progress tick, and
  /// when the order screen recovers a session. Idempotent: a leg is
  /// applied only while the entry's status still precedes it.
  /// Returns true when at least one leg was applied.
  Future<bool> processAutoArrivals({
    required String dateKey,
    required String entryId,
  }) async {
    if (_processingAuto) return false;
    final progress = await _readProgress(entryId);
    if (progress == null) return false;
    _mirrorArrivalEvents(progress);
    final frozen = progress['finalizedLegs'];
    if (frozen is! Map || frozen.isEmpty) return false;
    _processingAuto = true;
    try {
      var applied = false;
      var entry = _entryFor(dateKey, entryId);
      if (entry == null) return false;

      final outFrozen = frozen['outgoing'];
      if (outFrozen is Map && entry.status == 1) {
        await _applyAutoDelivered(
          dateKey: dateKey,
          entryId: entryId,
          frozen: Map<String, dynamic>.from(outFrozen),
          progress: progress,
        );
        applied = true;
        entry = _entryFor(dateKey, entryId);
      }

      final backFrozen = frozen['returning'];
      if (backFrozen is Map && entry != null && entry.status == 2) {
        await _applyAutoArrivedAtMart(
          dateKey: dateKey,
          entryId: entryId,
          frozen: Map<String, dynamic>.from(backFrozen),
        );
        applied = true;
      }
      return applied;
    } finally {
      _processingAuto = false;
    }
  }

  /// The auto-confirmed outgoing leg, finalized exactly like
  /// [markDelivered] — except the background service KEEPS RUNNING
  /// (the isolate already rolled into the return leg), so nothing is
  /// stopped, deleted or restarted here.
  Future<void> _applyAutoDelivered({
    required String dateKey,
    required String entryId,
    required Map<String, dynamic> frozen,
    required Map<String, dynamic> progress,
  }) async {
    final kmOut = (frozen['km'] as num?)?.toDouble() ?? 0;
    final startedAt = (frozen['startedAt'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final endedAt = (frozen['endedAt'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final durationSec =
        ((endedAt - startedAt) / 1000).round().clamp(0, 1 << 31);
    final outLat = ((frozen['lat'] as List?) ?? [])
        .map((e) => (e as num).toDouble())
        .toList();
    final outLng = ((frozen['lng'] as List?) ?? [])
        .map((e) => (e as num).toDouble())
        .toList();

    final snapped = await _snap.snapRoute(lat: outLat, lng: outLng);
    final finalKmOut =
        _saneFinalKm(gpsKm: kmOut, snappedKm: snapped?.distanceKm);
    _log?.info(
      AppLogCategory.tracking,
      'Outgoing leg finalized for entry $entryId: gps=${kmOut}km, '
      'osrm=${snapped?.distanceKm}km, chosen=${finalKmOut}km '
      '(auto-arrival)',
    );
    final roadLat =
        snapped?.geometry.map((p) => p.latitude).toList() ??
            const <double>[];
    final roadLng =
        snapped?.geometry.map((p) => p.longitude).toList() ??
            const <double>[];

    await _db.updateOrderEntry(
      dateKey: dateKey,
      entryId: entryId,
      status: 2,
      deliveredTimeMillis: endedAt,
      gpsKmOut: _round2(finalKmOut),
      outgoingDurationSec: durationSec,
      routeOutLat: outLat,
      routeOutLng: outLng,
      roadOutLat: roadLat,
      roadOutLng: roadLng,
    );

    if (outLat.isNotEmpty && outLng.isNotEmpty) {
      await _applyMartObservation(outLat.first, outLng.first);
    }

    // The isolate is already tracking the return leg — adopt it so
    // live snapshots keep flowing with the right segment/start.
    _trackingOrderId = entryId;
    _trackingDateKey = dateKey;
    _segment = TrackingSegment.returning;
    _segmentStart = DateTime.fromMillisecondsSinceEpoch(
      (progress['startedAt'] as num?)?.toInt() ?? endedAt,
    );
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _emitSnapshotFromFile();
    });
  }

  /// The auto-confirmed return leg, finalized exactly like
  /// [markArrivedAtMart]. The isolate already stopped the service
  /// after freezing the leg; stopping again here is a guarded no-op.
  Future<void> _applyAutoArrivedAtMart({
    required String dateKey,
    required String entryId,
    required Map<String, dynamic> frozen,
  }) async {
    final kmBack = (frozen['km'] as num?)?.toDouble() ?? 0;
    final startedAt = (frozen['startedAt'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final endedAt = (frozen['endedAt'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final durationSec =
        ((endedAt - startedAt) / 1000).round().clamp(0, 1 << 31);
    final backLat = ((frozen['lat'] as List?) ?? [])
        .map((e) => (e as num).toDouble())
        .toList();
    final backLng = ((frozen['lng'] as List?) ?? [])
        .map((e) => (e as num).toDouble())
        .toList();

    await _stopBackgroundTracking();
    await _deleteProgress(entryId);

    final snapped = await _snap.snapRoute(lat: backLat, lng: backLng);
    final finalKmBack =
        _saneFinalKm(gpsKm: kmBack, snappedKm: snapped?.distanceKm);
    _log?.info(
      AppLogCategory.tracking,
      'Return leg finalized for entry $entryId: gps=${kmBack}km, '
      'osrm=${snapped?.distanceKm}km, chosen=${finalKmBack}km '
      '(auto-arrival)',
    );
    final roadLat =
        snapped?.geometry.map((p) => p.latitude).toList() ??
            const <double>[];
    final roadLng =
        snapped?.geometry.map((p) => p.longitude).toList() ??
            const <double>[];

    await _db.updateOrderEntry(
      dateKey: dateKey,
      entryId: entryId,
      status: 3,
      martArrivedTimeMillis: endedAt,
      gpsKmBack: _round2(finalKmBack),
      returnDurationSec: durationSec,
      timestampMillis: endedAt,
      routeBackLat: backLat,
      routeBackLng: backLng,
      roadBackLat: roadLat,
      roadBackLng: roadLng,
    );

    if (backLat.isNotEmpty && backLng.isNotEmpty) {
      await _applyMartObservation(backLat.last, backLng.last);
    }
  }

  /// Feeds one mart observation (a trip start point or a confirmed
  /// return endpoint) into the mart learner and persists the result
  /// through the settings pipeline. Never throws — a learning hiccup
  /// must not break order finalization.
  Future<void> _applyMartObservation(double lat, double lng) async {
    try {
      final current = _readSettings?.call() ?? _db.settings;
      final outcome = MartLearner.observe(
        MartLearnerState(
          martLat: current.martLat,
          martLng: current.martLng,
          martCount: current.martObservationCount,
          candidateLat: current.martCandidateLat,
          candidateLng: current.martCandidateLng,
          candidateCount: current.martCandidateCount,
        ),
        lat,
        lng,
      );
      if (!outcome.changed) return;
      final st = outcome.state;
      UserSettings apply(UserSettings s) => s
        ..martLat = st.martLat
        ..martLng = st.martLng
        ..martObservationCount = st.martCount
        ..martCandidateLat = st.candidateLat
        ..martCandidateLng = st.candidateLng
        ..martCandidateCount = st.candidateCount;
      if (_updateSettings != null) {
        await _updateSettings(apply);
      } else {
        final s = _db.settings;
        apply(s);
        await _db.saveSettings(s);
      }
      if (outcome.learned) {
        _log?.info(
          AppLogCategory.settings,
          'Mart location learned: ${st.martLat}, ${st.martLng} '
          '(${st.martCount} observations)',
        );
      } else if (outcome.replaced) {
        _log?.info(
          AppLogCategory.settings,
          'Mart location replaced by a new cluster: '
          '${st.martLat}, ${st.martLng} (${st.martCount} observations)',
        );
      } else if (outcome.refined) {
        _log?.info(
          AppLogCategory.settings,
          'Mart location refined (${st.martCount} observations)',
        );
      }
    } catch (e) {
      _log?.warn(
        AppLogCategory.settings,
        'Mart observation could not be recorded',
        error: e,
      );
    }
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
  final svc = DeliveryTrackingService(
    db,
    log: ref.watch(appLogServiceProvider),
    // v27.8: mart learning reads/writes through the settings
    // notifier's live state so it can never fight a profile edit.
    readSettings: () => ref.read(settingsProvider),
    updateSettings: (apply) =>
        ref.read(settingsProvider.notifier).update(apply),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

/// Emits live snapshots while an order is being tracked.
final trackingSnapshotProvider = StreamProvider<TrackingSnapshot>((ref) {
  return ref.watch(deliveryTrackingServiceProvider).snapshots;
});
