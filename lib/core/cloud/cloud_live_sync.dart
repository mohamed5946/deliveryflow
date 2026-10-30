// v27.36 — Continuous foreground auto-sync (no FCM, no background push).
//
// Until v27.36 DeliveryFlow had ZERO snapshot listeners: sync was
// manual only (download-on-login, the Sync button, adjustment lines
// pulled on report open), so a manager edit never reached a driver
// while the app was running. This service closes that gap while the
// app is OPEN and signed in:
//
//   - Own summaries / orders / adjustments: Firestore snapshot
//     listeners. Incoming summaries apply through the SAME safe
//     merge as the manual sync (see cloud_download_apply.dart):
//     the pending upload queue flushes FIRST, newer updatedAtMillis
//     wins, manager-edited stamps survive, local days are never
//     deleted, and an incoming snapshot never overwrites a pending
//     local change (a queued upload goes up before any download
//     applies, and the merge keeps the newer local record).
//   - Manager dashboard: users stream + one summaries stream per
//     user (per-user subcollections — never a collection-group
//     query, which these rules reject even for managers). Changes
//     surface as [dataChanged]; the dashboard refetches through its
//     existing refresh signal.
//   - Upload direction: local day edits (via DatabaseService's day
//     change stream) upload promptly — summary + order record —
//     with queue + retry on failure. Start-up also reconciles:
//     local days NEWER than their cloud doc upload (manager edits
//     are never clobbered: a local day is uploaded only when its
//     updatedAtMillis beats the cloud doc's, and days carrying a
//     cloud override are skipped — their values came from cloud).
//   - Failures are LOUD: every listener error and every failed
//     upload emits a [LiveSyncFailure] with the exact reason (one
//     per failure episode — a repeat of the same error does not
//     re-emit until a success clears it). The UI shows these as
//     dialogs with the exact reason; nothing fails silently.
//   - Foreground only: if the OS kills the app in background, sync
//     pauses and resumes on reopen (listeners re-attach on start).
//     This is stated honestly — it is NOT background push.
//
// Layering: this file lives in core and never imports features. The
// Hive-apply step is injected ([applyDownload]) by the UI layer,
// which wires it to applyCloudDownload.
import 'dart:async';

import '../database/database_service.dart';
import '../database/models.dart';
import '../date_time/week_calendar.dart';
import '../logging/app_log_service.dart';
import 'cloud_backend.dart';
import 'cloud_services.dart';
import 'cloud_types.dart';
import 'retention_logic.dart';

/// One live-sync failure episode, surfaced loudly by the UI dialog.
/// [source] names the stream ('summaries', 'orders', 'adjustments',
/// 'users', 'upload', 'start', 'apply'); [reason] is the exact
/// error text, never paraphrased away.
class LiveSyncFailure {
  const LiveSyncFailure({required this.source, required this.reason});

  final String source;
  final String reason;

  @override
  String toString() => '$source: $reason';
}

/// Build one local day's upload payload (summary + order JSON) from
/// the app's own weekly-report math — the same formula the migration
/// builder uses, for ONE day. Returns null when the day has no
/// countable record (nothing sound to upload).
({CloudDaySummary summary, Map<String, dynamic> orderJson})?
    buildUploadDayData({
  required DatabaseService db,
  required UserSettings settings,
  required String uid,
  required String dateKey,
}) {
  final record = db.orderRecord(dateKey);
  if (record == null) return null;
  final weekStart =
      WeekCalendar.weekStart(WeekCalendar.parseDateKey(dateKey));
  final report = db.buildWeeklyReport(weekStart);
  for (final day in report.days) {
    if (day.dateKey != dateKey) continue;
    if (day.orders == null) return null;
    final summary = buildDaySummary(
      uid: uid,
      dateKey: dateKey,
      ordersCount: day.orders!,
      totalKm: day.kmTotal,
      orderPrice: settings.orderPrice ?? 0,
      dailyFixedPay: settings.dailyFixedPay ?? 0,
      distanceBonus: day.distanceBonus,
      manualBonus: day.manualBonus,
      flatBonus: day.flatBonus,
      updatedAtMillis: record.updatedAtMillis,
    );
    return (
      summary: summary,
      orderJson: <String, dynamic>{
        'dateKey': dateKey,
        'completedOrders': record.completedOrders,
        'totalKm': record.totalKm,
      },
    );
  }
  return null;
}

class CloudLiveSync {
  CloudLiveSync({
    required CloudBackend backend,
    required CloudSyncService sync,
    required DatabaseService db,
    required Future<int> Function(CloudDownload download) applyDownload,
    AppLogService? log,
    this.snapshotDebounce = const Duration(milliseconds: 300),
    this.changeDebounce = const Duration(seconds: 1),
  })  : _backend = backend,
        _sync = sync,
        _db = db,
        _applyDownload = applyDownload,
        _log = log;

  final CloudBackend _backend;
  final CloudSyncService _sync;
  final DatabaseService _db;
  final Future<int> Function(CloudDownload) _applyDownload;
  final AppLogService? _log;

  /// Coalescing windows (test seams: tests pass Duration.zero).
  final Duration snapshotDebounce;
  final Duration changeDebounce;

  CloudAccount? _account;

  bool get isRunning => _account != null;

  String? get runningUid => _account?.uid;

  final _failureController =
      StreamController<LiveSyncFailure>.broadcast();

  /// Loud failures with exact reasons (one per episode).
  Stream<LiveSyncFailure> get failures => _failureController.stream;

  final _dataChangedController = StreamController<void>.broadcast();

  /// Fired when applied cloud data or manager data changed: the UI
  /// bumps its data version (and the management refresh signal) so
  /// visible screens refetch at once.
  Stream<void> get dataChanged => _dataChangedController.stream;

  StreamSubscription<List<CloudDaySummary>>? _summariesSub;
  StreamSubscription<Map<String, Map<String, dynamic>>>? _ordersSub;
  StreamSubscription<List<CloudAdjustment>>? _adjustmentsSub;
  StreamSubscription<List<CloudAccount>>? _usersSub;
  final Map<String, StreamSubscription<List<CloudDaySummary>>>
      _managerSummarySubs = {};
  StreamSubscription<String>? _dayChangeSub;
  Timer? _applyTimer;
  Timer? _uploadTimer;

  List<CloudDaySummary> _latestSummaries = const [];
  Map<String, Map<String, dynamic>> _latestOrders = const {};
  final Set<String> _pendingUploadDays = {};
  final Map<String, String> _lastFailureBySource = {};
  bool _stopped = false;

  /// Serializes start/stop/restart so a sign-out racing a
  /// sign-in (or two rapid sign-ins) can never interleave listener
  /// attach/detach into a half-attached state: each lifecycle call
  /// waits for the previous one to finish.
  Future<void> _lifecycle = Future.value();

  /// Attach listeners for [account] (sign-in or session restore).
  /// Safe to call when already running for the same account (no-op)
  /// or a different one (stops first). Runs the start-time
  /// reconcile + initial download-apply, then attaches listeners.
  Future<void> start(CloudAccount account) {
    _lifecycle = _lifecycle.then((_) => _startInner(account));
    return _lifecycle;
  }

  /// Detach everything (sign-out). Idempotent.
  Future<void> stop() {
    _lifecycle = _lifecycle.then((_) => _stopInner());
    return _lifecycle;
  }

  /// Re-attach for [account] (dialog Retry path).
  Future<void> restart(CloudAccount account) {
    _lifecycle = _lifecycle.then((_) async {
      await _stopInner();
      await _startInner(account);
    });
    return _lifecycle;
  }

  Future<void> _startInner(CloudAccount account) async {
    if (_account?.uid == account.uid && _summariesSub != null) return;
    await _stopInner();
    _stopped = false;
    _account = account;
    _log?.info(
      AppLogCategory.system,
      'Live sync: attaching for ${account.uid}',
    );
    // 1. Pending local uploads go up FIRST — never lost to a
    // download (same order as the manual sync).
    try {
      await _sync.flushQueue();
    } catch (e) {
      _emitFailure('upload', e);
    }
    // 2. Reconcile: local days newer than cloud upload now.
    await _reconcileLocalDays(account);
    if (_stopped) return;
    // 3. Initial download-apply: manager edits made while the app
    // was closed land immediately, same as download-on-login.
    try {
      final download =
          await _sync.downloadUserData(account.uid, _relevantDateKeys());
      if (_stopped) return;
      final changed = await _applyDownload(download);
      if (changed > 0) _dataChangedController.add(null);
    } catch (e) {
      _emitFailure('start', e);
    }
    if (_stopped) return;
    // 4. Attach listeners.
    _attachOwnListeners(account);
    if (account.isManager) await _attachManagerListeners();
    // 5. Local edits upload promptly from here on.
    _dayChangeSub = _db.dayChanges.listen((dateKey) {
      _pendingUploadDays.add(dateKey);
      _uploadTimer?.cancel();
      _uploadTimer = Timer(changeDebounce, _flushPendingUploadDays);
    });
    _log?.info(
      AppLogCategory.system,
      'Live sync: attached (${account.isManager ? 'manager' : 'driver'})',
    );
  }

  /// Detach everything (sign-out). Idempotent; late async work
  /// after a stop is ignored via [_stopped].
  Future<void> _stopInner() async {
    _stopped = true;
    _account = null;
    _applyTimer?.cancel();
    _uploadTimer?.cancel();
    _applyTimer = null;
    _uploadTimer = null;
    await _summariesSub?.cancel();
    await _ordersSub?.cancel();
    await _adjustmentsSub?.cancel();
    await _usersSub?.cancel();
    for (final sub in _managerSummarySubs.values) {
      await sub.cancel();
    }
    await _dayChangeSub?.cancel();
    _summariesSub = null;
    _ordersSub = null;
    _adjustmentsSub = null;
    _usersSub = null;
    _managerSummarySubs.clear();
    _dayChangeSub = null;
    _latestSummaries = const [];
    _latestOrders = const {};
    _pendingUploadDays.clear();
    _lastFailureBySource.clear();
    _log?.info(AppLogCategory.system, 'Live sync: detached');
  }

  /// App returned to foreground: retry anything queued (the
  /// listeners themselves reconnect through the Firestore SDK).
  Future<void> onAppResumed() async {
    if (_account == null) return;
    try {
      await _sync.flushQueue();
      if (_sync.hasPending && _sync.lastQueueError != null) {
        _emitFailure('upload', _sync.lastQueueError!);
      }
    } catch (e) {
      _emitFailure('upload', e);
    }
  }

  /// Dates worth downloading: every local date + the current week
  /// (a manager may have edited a current-week day this device
  /// never recorded locally).
  List<String> _relevantDateKeys() {
    final keys = <String>{
      for (final record in _db.allOrderRecords) record.dateKey,
      for (final day in WeekCalendar.weekDays(DateTime.now()))
        WeekCalendar.dateKey(day),
    }.toList()
      ..sort();
    return keys;
  }

  /// Upload local days that are NEWER than their cloud doc. A day
  /// carrying a cloud override is skipped (its values came from
  /// cloud — nothing local to push), and expired days are skipped
  /// (retention: never resurrect a TTL-deleted doc). Best-effort:
  /// a failed day stays queued for retry and never blocks the rest.
  Future<void> _reconcileLocalDays(CloudAccount account) async {
    for (final record in _db.allOrderRecords) {
      if (_stopped) return;
      if (record.cloudOverrideApplied) continue;
      if (isDetailExpired(record.dateKey, DateTime.now())) continue;
      try {
        final cloud =
            await _backend.fetchDaySummary(account.uid, record.dateKey);
        if (cloud == null ||
            record.updatedAtMillis > cloud.updatedAtMillis) {
          await _uploadDay(account.uid, record.dateKey);
        }
      } catch (e) {
        _log?.warn(
          AppLogCategory.system,
          'Live sync reconcile skipped ${record.dateKey}',
          detail: e.toString(),
        );
      }
    }
  }

  /// Upload one day (summary + order record). Returns false when
  /// the immediate attempt failed (the day stays queued for retry
  /// and the exact reason is emitted loudly).
  Future<bool> _uploadDay(String uid, String dateKey) async {
    final data = buildUploadDayData(
      db: _db,
      settings: _db.settings,
      uid: uid,
      dateKey: dateKey,
    );
    if (data == null) return false;
    await _sync.queueDaySummary(data.summary);
    if (_sync.lastQueueError != null) {
      _emitFailure('upload', _sync.lastQueueError!);
      return false;
    }
    await _sync.queueOrderRecord(uid, dateKey, data.orderJson);
    if (_sync.lastQueueError != null) {
      _emitFailure('upload', _sync.lastQueueError!);
      return false;
    }
    return true;
  }

  /// Upload debounced local edits + retry anything queued.
  Future<void> _flushPendingUploadDays() async {
    final account = _account;
    if (account == null) return;
    final days = _pendingUploadDays.toList();
    _pendingUploadDays.clear();
    for (final dateKey in days) {
      if (isDetailExpired(dateKey, DateTime.now())) continue;
      await _uploadDay(account.uid, dateKey);
    }
    try {
      await _sync.flushQueue();
      if (_sync.hasPending && _sync.lastQueueError != null) {
        _emitFailure('upload', _sync.lastQueueError!);
      }
    } catch (e) {
      _emitFailure('upload', e);
    }
  }

  void _attachOwnListeners(CloudAccount account) {
    try {
      _summariesSub =
          _backend.watchUserSummaries(account.uid).listen((data) {
        _latestSummaries = data;
        _clearFailure('summaries');
        _scheduleApply();
      }, onError: (Object e) => _emitFailure('summaries', e));
    } catch (e) {
      _emitFailure('summaries', e);
    }
    try {
      _ordersSub = _backend.watchUserOrders(account.uid).listen((data) {
        _latestOrders = data;
        _clearFailure('orders');
        _scheduleApply();
      }, onError: (Object e) => _emitFailure('orders', e));
    } catch (e) {
      _emitFailure('orders', e);
    }
    try {
      _adjustmentsSub =
          _backend.watchUserAdjustments(account.uid).listen((_) {
        _clearFailure('adjustments');
        _log?.info(
          AppLogCategory.system,
          'Live sync: adjustments changed',
        );
        _dataChangedController.add(null);
      }, onError: (Object e) => _emitFailure('adjustments', e));
    } catch (e) {
      _emitFailure('adjustments', e);
    }
  }

  Future<void> _attachManagerListeners() async {
    try {
      final users = await _backend.listUsers();
      if (_stopped) return;
      _syncManagerSummarySubs(users.map((u) => u.uid).toSet());
    } catch (e) {
      _emitFailure('users', e);
    }
    try {
      _usersSub = _backend.watchUsers().listen((users) {
        _clearFailure('users');
        _syncManagerSummarySubs(users.map((u) => u.uid).toSet());
        _dataChangedController.add(null);
      }, onError: (Object e) => _emitFailure('users', e));
    } catch (e) {
      _emitFailure('users', e);
    }
  }

  /// Attach per-user summary streams for exactly [uids]: new users
  /// attach live, removed users cancel. Each event refreshes the
  /// dashboard through [dataChanged] (the dashboard refetches with
  /// its existing .get() reads — no extra rules needed).
  void _syncManagerSummarySubs(Set<String> uids) {
    for (final uid in _managerSummarySubs.keys
        .where((u) => !uids.contains(u))
        .toList()) {
      _managerSummarySubs.remove(uid)?.cancel();
    }
    for (final uid in uids) {
      if (_managerSummarySubs.containsKey(uid)) continue;
      try {
        _managerSummarySubs[uid] =
            _backend.watchUserSummaries(uid).listen((_) {
          _clearFailure('summaries:$uid');
          _dataChangedController.add(null);
        }, onError: (Object e) => _emitFailure('summaries:$uid', e));
      } catch (e) {
        _emitFailure('summaries:$uid', e);
      }
    }
  }

  /// Coalesced snapshot apply: flush the queue FIRST (a queued
  /// upload must never be lost to a download), then apply the
  /// latest snapshot state through the same safe merge as manual
  /// sync. No-op when nothing visibly changed.
  void _scheduleApply() {
    _applyTimer?.cancel();
    _applyTimer = Timer(snapshotDebounce, _applyLatestSnapshot);
  }

  Future<void> _applyLatestSnapshot() async {
    final account = _account;
    if (account == null) return;
    try {
      await _sync.flushQueue();
      if (_stopped) return;
      final changed = await _applyDownload(
        CloudDownload(
          summaries: _latestSummaries,
          ordersByDateKey: _latestOrders,
        ),
      );
      if (changed > 0) {
        _log?.info(
          AppLogCategory.system,
          'Live sync: applied $changed day(s) from cloud',
        );
        _dataChangedController.add(null);
      }
    } catch (e) {
      _emitFailure('apply', e);
    }
  }

  void _emitFailure(String source, Object error) {
    final reason = error.toString();
    if (_lastFailureBySource[source] == reason) return;
    _lastFailureBySource[source] = reason;
    _log?.error(
      AppLogCategory.system,
      'Live sync failure [$source]',
      detail: reason,
    );
    if (!_failureController.isClosed) {
      _failureController.add(LiveSyncFailure(source: source, reason: reason));
    }
  }

  void _clearFailure(String source) => _lastFailureBySource.remove(source);
}
