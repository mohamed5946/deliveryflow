import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../date_time/week_calendar.dart';
import '../logging/app_log_service.dart';
import 'models.dart';
import 'schema_migrations.dart';

/// Local-first persistence layer built on Hive.
///
/// Boxes:
/// - `settings`   : single [UserSettings] under key `'user'`.
/// - `schedules`   : [WorkSchedule] keyed by week-start dateKey (unique per week).
/// - `orders`     : [DailyOrderRecord] keyed by dateKey (unique per day).
/// - `sessions`   : [WorkSession] with auto-increment int keys.
/// - `meta`       : schema version + misc flags.
class DatabaseService {
  /// v27.2: optional diagnostics log (constructor-injected from main;
  /// null in tests and headless use — all logging then no-ops).
  DatabaseService({AppLogService? log}) : _log = log;

  final AppLogService? _log;

  static const String _settingsBox = 'settings';
  static const String _schedulesBox = 'schedules';
  static const String _ordersBox = 'orders';
  static const String _sessionsBox = 'sessions';
  static const String _metaBox = 'meta';

  late final Box<UserSettings> _settings;
  late final Box<WorkSchedule> _schedules;
  late final Box<DailyOrderRecord> _orders;
  late final Box<WorkSession> _sessions;
  late final Box _meta;

  bool get isOpen => Hive.isBoxOpen(_settingsBox);

  static void registerAdapters() {
    void reg<T>(TypeAdapter<T> adapter) {
      if (!Hive.isAdapterRegistered(adapter.typeId)) {
        Hive.registerAdapter<T>(adapter);
      }
    }

    reg<UserSettings>(UserSettingsAdapter());
    reg<DailySchedule>(DailyScheduleAdapter());
    reg<WorkSchedule>(WorkScheduleAdapter());
    reg<DailyOrderRecord>(DailyOrderRecordAdapter());
    reg<OrderEntry>(OrderEntryAdapter());
    reg<BreakInterval>(BreakIntervalAdapter());
    reg<WorkSession>(WorkSessionAdapter());
  }

  Future<void> init({String? hivePath}) async {
    if (hivePath != null) {
      Hive.init(hivePath);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      Hive.init(dir.path);
    }
    registerAdapters();
    _settings = await Hive.openBox<UserSettings>(_settingsBox);
    _schedules = await Hive.openBox<WorkSchedule>(_schedulesBox);
    _orders = await Hive.openBox<DailyOrderRecord>(_ordersBox);
    _sessions = await Hive.openBox<WorkSession>(_sessionsBox);
    _meta = await Hive.openBox(_metaBox);
    await _migrateIfNeeded();
    if (!_settings.containsKey('user')) {
      await _settings.put('user', UserSettings());
    }
  }

  /// Schema upgrades live in [SchemaMigrations] (v27.2 split — schema
  /// evolution is its own responsibility); this only delegates and
  /// records what ran in the diagnostics log.
  Future<void> _migrateIfNeeded() async {
    final applied = await SchemaMigrations.applyIfNeeded(
      orders: _orders,
      settings: _settings,
      meta: _meta,
    );
    for (final tag in applied) {
      _log?.info(AppLogCategory.system, 'Schema migration applied: $tag');
    }
  }

  // ------------------------------------------------------------- settings --
  UserSettings get settings => _settings.get('user') ?? UserSettings();

  Future<void> saveSettings(UserSettings s) => _settings.put('user', s);

  // ------------------------------------------------------------ schedules --
  /// Saves a schedule; one schedule per week-start (updates in place).
  Future<void> saveSchedule(WorkSchedule schedule) =>
      _schedules.put(schedule.weekStartKey, schedule);

  WorkSchedule? scheduleForWeek(DateTime anyDayInWeek) =>
      _schedules.get(WeekCalendar.dateKey(WeekCalendar.weekStart(anyDayInWeek)));

  bool hasScheduleForWeek(DateTime anyDayInWeek) =>
      scheduleForWeek(anyDayInWeek) != null;

  // --------------------------------------------------------------- orders --
  /// Insert or update the unique daily record for [dateKey].
  Future<DailyOrderRecord> upsertOrderRecord({
    required String dateKey,
    required int completedOrders,
    String notes = '',
  }) async {
    if (completedOrders < 0) {
      throw ArgumentError('completedOrders cannot be negative');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = _orders.get(dateKey);
    if (existing != null) {
      existing.completedOrders = completedOrders;
      existing.notes = notes;
      existing.isConfirmed = true;
      existing.updatedAtMillis = now;
      await existing.save();
      return existing;
    }
    final record = DailyOrderRecord(
      id: 'ord_$dateKey',
      dateKey: dateKey,
      completedOrders: completedOrders,
      notes: notes,
      createdAtMillis: now,
      updatedAtMillis: now,
    );
    await _orders.put(dateKey, record);
    return record;
  }

  DailyOrderRecord? orderRecord(String dateKey) => _orders.get(dateKey);

  /// Per-order entries for a day (empty when none recorded).
  List<OrderEntry> orderEntries(String dateKey) =>
      List.unmodifiable(orderRecord(dateKey)?.entries ?? const <OrderEntry>[]);

  /// The user's own average riding speed (km/h), measured from his
  /// completed trip history — used to personalize ETA estimates.
  ///
  /// Only GPS-tracked legs whose implied speed falls in a sane riding
  /// window (10–80 km/h) count: that drops legs with long customer
  /// stops (which would drag the average down) and GPS glitches
  /// (which would spike it). Takes the newest [maxTrips] trips.
  ///
  /// Returns null when there is no usable history yet — the caller
  /// then falls back to the server's estimate.
  double? personalAvgSpeedKmh({int maxTrips = 20}) {
    final legs = <({int ts, double km, int sec})>[];
    for (final record in _orders.values) {
      for (final entry in record.entries) {
        if (!entry.isCompleted) continue;
        if (entry.gpsKmOut > 0 && entry.outgoingDurationSec > 0) {
          legs.add((
            ts: entry.timestampMillis,
            km: entry.gpsKmOut,
            sec: entry.outgoingDurationSec
          ));
        }
        if (entry.gpsKmBack > 0 && entry.returnDurationSec > 0) {
          legs.add((
            ts: entry.timestampMillis,
            km: entry.gpsKmBack,
            sec: entry.returnDurationSec
          ));
        }
      }
    }
    if (legs.isEmpty) return null;
    legs.sort((a, b) => b.ts.compareTo(a.ts));
    double distKm = 0;
    double timeHrs = 0;
    var used = 0;
    for (final leg in legs) {
      if (used >= maxTrips * 2) break;
      final kmh = leg.km / (leg.sec / 3600.0);
      if (kmh < 10 || kmh > 80) continue;
      distKm += leg.km;
      timeHrs += leg.sec / 3600.0;
      used++;
    }
    if (timeHrs <= 0) return null;
    return distKm / timeHrs;
  }

  /// Adds one order entry to the day's record (creating it if needed) and
  /// bumps the day's order count.
  Future<OrderEntry> addOrderEntry({
    required String dateKey,
    required int timestampMillis,
    double kmOut = 0,
    double kmBack = 0,
    String notes = '',
  }) async {
    if (kmOut < 0 || kmBack < 0) {
      throw ArgumentError('Distance cannot be negative');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    var record = _orders.get(dateKey);
    record ??= DailyOrderRecord(
      id: 'ord_$dateKey',
      dateKey: dateKey,
      completedOrders: 0,
      createdAtMillis: now,
      updatedAtMillis: now,
    );
    final entry = OrderEntry(
      id: 'oe_${now}_${record.entries.length}',
      dateKey: dateKey,
      timestampMillis: timestampMillis,
      kmOut: kmOut,
      kmBack: kmBack,
      notes: notes,
    );
    record.entries.add(entry);
    // v27: creating an entry does NOT count it. The day total only
    // increments when delivery actually starts (status 0 -> >=1 in
    // updateOrderEntry) — a pending order is not a completed order.
    record.isConfirmed = true;
    record.updatedAtMillis = now;
    await _orders.put(dateKey, record);
    return entry;
  }

  /// v27.1: adds [count] count-only entries to the day's record
  /// (creating it if needed) — the "تسجيل العدد فقط" bulk log. Each
  /// entry is born COMPLETED (status 3) and already counted, so the
  /// day's total bumps by [count] here at creation and the v27
  /// count-on-start transition increment never applies to them (they
  /// never sit at status 0). They carry no km, destination or phone;
  /// each renders as its own deletable row in the day's list.
  Future<List<OrderEntry>> addCountOnlyEntries({
    required String dateKey,
    required int count,
    int? timestampMillis,
  }) async {
    if (count < 0) {
      throw ArgumentError('count cannot be negative');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    var record = _orders.get(dateKey);
    record ??= DailyOrderRecord(
      id: 'ord_$dateKey',
      dateKey: dateKey,
      completedOrders: 0,
      createdAtMillis: now,
      updatedAtMillis: now,
    );
    if (count == 0) return const [];
    final base = record.entries.length;
    final created = <OrderEntry>[
      for (var i = 0; i < count; i++)
        OrderEntry(
          id: 'oe_${now}_c${base + i}',
          dateKey: dateKey,
          timestampMillis: timestampMillis ?? now,
          status: 3,
          countOnly: true,
        ),
    ];
    record.entries.addAll(created);
    record.completedOrders = record.completedOrders + count;
    record.isConfirmed = true;
    record.updatedAtMillis = now;
    await _orders.put(dateKey, record);
    _log?.info(
      AppLogCategory.orders,
      'Bulk count-only: +$count on $dateKey '
      '(day total now ${record.completedOrders})',
    );
    return created;
  }

  /// Updates one order entry's distance/notes/time.
  Future<void> updateOrderEntry({
    required String dateKey,
    required String entryId,
    int? timestampMillis,
    double? kmOut,
    double? kmBack,
    String? notes,
    String? phone,
    double? manualBonusEgp,
    int? status,
    int? pickupTimeMillis,
    int? deliveredTimeMillis,
    int? martArrivedTimeMillis,
    double? gpsKmOut,
    double? gpsKmBack,
    int? outgoingDurationSec,
    int? returnDurationSec,
    List<double>? routeOutLat,
    List<double>? routeOutLng,
    List<double>? routeBackLat,
    List<double>? routeBackLng,
    List<double>? roadOutLat,
    List<double>? roadOutLng,
    List<double>? roadBackLat,
    List<double>? roadBackLng,
  }) async {
    final record = _orders.get(dateKey);
    if (record == null) return;
    final idx = record.entries.indexWhere((e) => e.id == entryId);
    if (idx < 0) return;
    final entry = record.entries[idx];
    // v27 count-on-start: remember whether this entry was still pending
    // BEFORE the update, so the 0 -> >=1 transition can count it exactly
    // once (re-entering startOutgoing / resume never double-counts).
    final wasPending = entry.isPending;
    if (timestampMillis != null) entry.timestampMillis = timestampMillis;
    if (kmOut != null) {
      if (kmOut < 0) throw ArgumentError('Distance cannot be negative');
      entry.kmOut = kmOut;
    }
    if (kmBack != null) {
      if (kmBack < 0) throw ArgumentError('Distance cannot be negative');
      entry.kmBack = kmBack;
    }
    if (notes != null) entry.notes = notes;
    if (phone != null) entry.phone = phone;
    if (manualBonusEgp != null) {
      if (manualBonusEgp < 0) {
        throw ArgumentError('Manual bonus cannot be negative');
      }
      entry.manualBonusEgp = manualBonusEgp;
    }
    if (status != null) entry.status = status;
    if (pickupTimeMillis != null) entry.pickupTimeMillis = pickupTimeMillis;
    if (deliveredTimeMillis != null) {
      entry.deliveredTimeMillis = deliveredTimeMillis;
    }
    if (martArrivedTimeMillis != null) {
      entry.martArrivedTimeMillis = martArrivedTimeMillis;
    }
    if (gpsKmOut != null) entry.gpsKmOut = gpsKmOut;
    if (gpsKmBack != null) entry.gpsKmBack = gpsKmBack;
    if (outgoingDurationSec != null) {
      entry.outgoingDurationSec = outgoingDurationSec;
    }
    if (returnDurationSec != null) entry.returnDurationSec = returnDurationSec;
    if (routeOutLat != null) entry.routeOutLat = routeOutLat;
    if (routeOutLng != null) entry.routeOutLng = routeOutLng;
    if (routeBackLat != null) entry.routeBackLat = routeBackLat;
    if (routeBackLng != null) entry.routeBackLng = routeBackLng;
    if (roadOutLat != null) entry.roadOutLat = roadOutLat;
    if (roadOutLng != null) entry.roadOutLng = roadOutLng;
    if (roadBackLat != null) entry.roadBackLat = roadBackLat;
    if (roadBackLng != null) entry.roadBackLng = roadBackLng;
    if (wasPending && !entry.isPending) {
      // Delivery just started (بدأ التوصيل): count this order now.
      record.completedOrders = record.completedOrders + 1;
      _log?.info(
        AppLogCategory.orders,
        'Order counted on delivery start: entry $entryId on $dateKey '
        '(day total now ${record.completedOrders})',
      );
    }
    record.updatedAtMillis = DateTime.now().millisecondsSinceEpoch;
    await record.save();
  }

  /// Deletes one order entry. The day's counted total only drops when
  /// the deleted entry had been counted (delivery had started, v27);
  /// deleting a still-pending entry never changes the total.
  Future<void> deleteOrderEntry({
    required String dateKey,
    required String entryId,
  }) async {
    final record = _orders.get(dateKey);
    if (record == null) return;
    final idx = record.entries.indexWhere((e) => e.id == entryId);
    if (idx < 0) return;
    final wasCounted = record.entries[idx].status >= 1;
    record.entries.removeAt(idx);
    if (wasCounted) {
      record.completedOrders =
          (record.completedOrders - 1).clamp(0, 1 << 30);
    }
    record.updatedAtMillis = DateTime.now().millisecondsSinceEpoch;
    await record.save();
  }

  /// Permanently deletes a whole week's data: the daily order records
  /// (orders + all recorded route/road geometry, which also feeds the
  /// heatmap) and the work sessions of all 7 days starting at
  /// [weekStartKey]. Work schedules are kept. Used by History's
  /// "delete week" (storage saving).
  Future<void> deleteWeek(String weekStartKey) async {
    final start = WeekCalendar.parseDateKey(weekStartKey);
    for (var i = 0; i < 7; i++) {
      final key =
          WeekCalendar.dateKey(WeekCalendar.addDays(start, i));
      await _orders.delete(key);
      final sessionKeys = _sessions.toMap().entries
          .where((e) => e.value.dateKey == key)
          .map((e) => e.key)
          .toList();
      for (final k in sessionKeys) {
        await _sessions.delete(k);
      }
    }
  }

  /// Total driven km (out, back) for a day from detailed entries.
  (double, double) kmForDate(String dateKey) {
    final record = _orders.get(dateKey);
    if (record == null) return (0, 0);
    return (record.totalKmOut, record.totalKmBack);
  }

  /// Normalizes a phone number for comparison: strips spaces, dashes,
  /// and any other non-digit characters (keeps a leading `+`).
  static String _normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9+]'), '');

  bool _phoneMatchesPrefix(String phone, String prefix) {
    final raw = phone.trim();
    if (raw.isEmpty || prefix.isEmpty) return false;
    // Compare raw (as typed) and normalized (spaces/dashes stripped).
    return raw.startsWith(prefix) ||
        _normalizePhone(raw).startsWith(_normalizePhone(prefix));
  }

  /// All order entries whose saved phone number starts with [prefix],
  /// paired with their day's dateKey, newest first. Only orders with a
  /// non-empty phone are considered.
  List<({String dateKey, OrderEntry entry})> searchOrdersByPhone(
      String prefix) {
    final p = prefix.trim();
    if (p.isEmpty) return const [];
    final out = <({String dateKey, OrderEntry entry})>[];
    for (final record in _orders.values) {
      for (final entry in record.entries) {
        if (_phoneMatchesPrefix(entry.phone, p)) {
          out.add((dateKey: record.dateKey, entry: entry));
        }
      }
    }
    out.sort((a, b) => b.entry.timestampMillis
        .compareTo(a.entry.timestampMillis));
    return out;
  }

  /// Distinct saved phone numbers starting with [prefix], sorted.
  /// Backs the live suggestions of the customer search screen.
  List<String> distinctPhonesByPrefix(String prefix) {
    final p = prefix.trim();
    if (p.isEmpty) return const [];
    final phones = <String>{};
    for (final record in _orders.values) {
      for (final entry in record.entries) {
        final phone = entry.phone.trim();
        if (_phoneMatchesPrefix(phone, p)) phones.add(phone);
      }
    }
    final list = phones.toList()..sort();
    return list;
  }

  // ------------------------------------------------------------- sessions --
  Future<WorkSession> startSession(String dateKey, {String notes = ''}) async {
    final active = activeSession();
    if (active != null) {
      throw StateError('A work session is already active');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = WorkSession(
      id: 'ses_${now}_${_sessions.length}',
      dateKey: dateKey,
      startMillis: now,
      notes: notes,
      status: 0,
    );
    await _sessions.add(session);
    return session;
  }

  WorkSession? activeSession() {
    for (final s in _sessions.values) {
      if (s.isActive) return s;
    }
    return null;
  }

  Future<void> saveSession(WorkSession s) => s.save();

  Future<WorkSession> saveManualSession({
    required String dateKey,
    required int startMinutes,
    required int endMinutes,
    required int breakMinutes,
    String notes = '',
  }) async {
    if (endMinutes == startMinutes) {
      throw ArgumentError('End time must differ from start time');
    }
    var end = endMinutes;
    if (end <= startMinutes) end += 24 * 60;
    final gross = end - startMinutes;
    if (gross <= 0) throw ArgumentError('Invalid shift duration');
    if (breakMinutes < 0 || breakMinutes > gross) {
      throw ArgumentError('Invalid break duration');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = WorkSession(
      id: 'man_${dateKey}_$now',
      dateKey: dateKey,
      startMillis: now,
      endMillis: now,
      notes: notes,
      status: 2,
      manualStartMinutes: startMinutes,
      manualEndMinutes: endMinutes,
      manualBreakMinutes: breakMinutes,
      isManual: true,
    );
    await _sessions.add(session);
    return session;
  }

  List<WorkSession> sessionsForDate(String dateKey) =>
      _sessions.values.where((s) => s.dateKey == dateKey).toList();

  /// Net recorded minutes for a date from finished + active sessions.
  int recordedMinutesForDate(String dateKey) {
    var total = 0;
    for (final s in sessionsForDate(dateKey)) {
      if (s.status == 2 || s.isActive) total += s.netMinutes;
    }
    return total;
  }

  /// Effective worked minutes for one date: recorded session minutes, or —
  /// v26 auto-hours — the day's net planned minutes when at least one order
  /// was logged and no session was recorded. Same rule the weekly report
  /// applies per day (see [effectiveWorkMinutes]).
  int effectiveMinutesForDate(String dateKey) {
    final schedule = scheduleForWeek(WeekCalendar.parseDateKey(dateKey));
    DailySchedule? daySchedule;
    if (schedule != null) {
      for (final d in schedule.dailySchedules) {
        if (d.dateKey == dateKey) {
          daySchedule = d;
          break;
        }
      }
    }
    return effectiveWorkMinutes(
      recordedMinutes: recordedMinutesForDate(dateKey),
      orders: orderRecord(dateKey)?.completedOrders,
      schedule: daySchedule,
    );
  }

  // ---------------------------------------------------------------- counts --
  Map<String, int> recordCounts() => {
        'schedules': _schedules.length,
        'orderRecords': _orders.length,
        'sessions': _sessions.length,
      };

  // ---------------------------------------------------------------- export --
  String exportCsv() {
    final rows = <List<String>>[
      ['date', 'orders', 'work_minutes', 'km_out', 'km_back', 'notes']
    ];
    final keys = _orders.keys.cast<String>().toList()..sort();
    for (final k in keys) {
      final r = _orders.get(k)!;
      rows.add([
        r.dateKey,
        r.completedOrders.toString(),
        recordedMinutesForDate(r.dateKey).toString(),
        r.totalKmOut.toStringAsFixed(1),
        r.totalKmBack.toStringAsFixed(1),
        '"${r.notes.replaceAll('"', '""')}"',
      ]);
    }
    return rows.map((r) => r.join(',')).join('\n');
  }

  String backupJson() {
    final data = {
      'schemaVersion': kSchemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': settings.toJson(),
      'orders': _orders.values
          .map((r) => {
                'dateKey': r.dateKey,
                'completedOrders': r.completedOrders,
                'notes': r.notes,
                'isConfirmed': r.isConfirmed,
                'entries': r.entries.map((e) => e.toJson()).toList(),
              })
          .toList(),
      'schedules': _schedules.values
          .map((s) => {
                'weekStartKey': s.weekStartKey,
                'weekEndKey': s.weekEndKey,
                'days': s.dailySchedules
                    .map((d) => {
                          'dateKey': d.dateKey,
                          'isWorkingDay': d.isWorkingDay,
                          'startMinutes': d.startMinutes,
                          'endMinutes': d.endMinutes,
                          'breakDurationMinutes': d.breakDurationMinutes,
                          'notes': d.notes,
                        })
                    .toList(),
              })
          .toList(),
      'sessions': _sessions.values
          .map((s) => {
                'dateKey': s.dateKey,
                'startMillis': s.startMillis,
                'endMillis': s.endMillis,
                'status': s.status,
                'isManual': s.isManual,
                'manualStartMinutes': s.manualStartMinutes,
                'manualEndMinutes': s.manualEndMinutes,
                'manualBreakMinutes': s.manualBreakMinutes,
                'notes': s.notes,
                'breaks': s.breaks
                    .map((b) => {
                          'startMillis': b.startMillis,
                          'endMillis': b.endMillis,
                        })
                    .toList(),
              })
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> restoreFromJson(String jsonStr) async {
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    await _orders.clear();
    await _schedules.clear();
    await _sessions.clear();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final o in (data['orders'] as List? ?? [])) {
      final m = o as Map<String, dynamic>;
      await _orders.put(
        m['dateKey'] as String,
        DailyOrderRecord(
          id: 'ord_${m['dateKey']}',
          dateKey: m['dateKey'] as String,
          completedOrders: (m['completedOrders'] as num).toInt(),
          notes: (m['notes'] as String?) ?? '',
          createdAtMillis: now,
          updatedAtMillis: now,
          entries: [
            for (final e in (m['entries'] as List? ?? []))
              OrderEntry.fromJson(e as Map<String, dynamic>),
          ],
        ),
      );
    }
    for (final s in (data['schedules'] as List? ?? [])) {
      final m = s as Map<String, dynamic>;
      final days = <DailySchedule>[];
      for (final d in (m['days'] as List? ?? [])) {
        final dm = d as Map<String, dynamic>;
        days.add(DailySchedule(
          dateKey: dm['dateKey'] as String,
          isWorkingDay: (dm['isWorkingDay'] as bool?) ?? true,
          startMinutes: (dm['startMinutes'] as num?)?.toInt() ?? 540,
          endMinutes: (dm['endMinutes'] as num?)?.toInt() ?? 1020,
          breakDurationMinutes:
              (dm['breakDurationMinutes'] as num?)?.toInt() ?? 30,
          notes: (dm['notes'] as String?) ?? '',
        ));
      }
      final sched = WorkSchedule(
        id: 'sch_${m['weekStartKey']}',
        weekStartKey: m['weekStartKey'] as String,
        weekEndKey: m['weekEndKey'] as String,
        dailySchedules: days,
        createdAtMillis: now,
        updatedAtMillis: now,
      );
      await _schedules.put(sched.weekStartKey, sched);
    }
    for (final s in (data['sessions'] as List? ?? [])) {
      final m = s as Map<String, dynamic>;
      final breaks = <BreakInterval>[];
      for (final b in (m['breaks'] as List? ?? [])) {
        final bm = b as Map<String, dynamic>;
        breaks.add(BreakInterval(
          startMillis: (bm['startMillis'] as num).toInt(),
          endMillis: (bm['endMillis'] as num?)?.toInt(),
        ));
      }
      await _sessions.add(WorkSession(
        id: 'res_$now',
        dateKey: m['dateKey'] as String,
        startMillis: (m['startMillis'] as num).toInt(),
        endMillis: (m['endMillis'] as num?)?.toInt(),
        breaks: breaks,
        notes: (m['notes'] as String?) ?? '',
        status: (m['status'] as num?)?.toInt() ?? 2,
        manualStartMinutes: (m['manualStartMinutes'] as num?)?.toInt(),
        manualEndMinutes: (m['manualEndMinutes'] as num?)?.toInt(),
        manualBreakMinutes: (m['manualBreakMinutes'] as num?)?.toInt() ?? 0,
        isManual: (m['isManual'] as bool?) ?? false,
      ));
    }
    if (data['settings'] is Map) {
      await _settings.put(
          'user',
          UserSettings.fromJson(
              Map<String, dynamic>.from(data['settings'] as Map)));
    }
  }

  Future<void> clearAll() async {
    await _orders.clear();
    await _schedules.clear();
    await _sessions.clear();
    await _settings.put('user', UserSettings());
  }

  // ---------------------------------------------------------------- report --
  /// Builds the weekly report for the week containing [anyDayInWeek].
  ///
  /// Averages use recorded days only — unrecorded days are never treated
  /// as zero. [WeeklyReport.missingRecordDates] lists days with no data.
  WeeklyReport buildWeeklyReport(DateTime anyDayInWeek) {
    final start = WeekCalendar.weekStart(anyDayInWeek);
    final days = WeekCalendar.weekDays(anyDayInWeek);
    final schedule = scheduleForWeek(anyDayInWeek);
    final schedByDay = <String, DailySchedule>{
      for (final d in schedule?.dailySchedules ?? []) d.dateKey: d
    };
    // v27.5: bonuses resolve against the CURRENT settings — the
    // distance bonus against this week's effective flag (per-week
    // override ?? global default) and the current tiers; manual
    // bonuses are read straight off the entries. Derived, never
    // stored, so edits re-derive everywhere consistently.
    final settings = this.settings;
    final weekKey = WeekCalendar.dateKey(start);
    final distanceBonusOn = settings.distanceBonusEnabledForWeek(weekKey);
    final bonusTiers = settings.distanceBonusTiers;
    // v27.6: flat bonus paid on every counted order (0 = off),
    // resolved from the current settings like the other bonuses.
    final flatPerOrder = settings.flatOrderBonusEgp;

    var totalOrders = 0;
    var totalMinutes = 0;
    var recordedDays = 0;
    var paidDays = 0;
    var workingDaysWithData = 0;
    var workingMinutesSum = 0;
    var totalKmOut = 0.0;
    var totalKmBack = 0.0;
    var totalDistanceBonus = 0.0;
    var totalManualBonus = 0.0;
    String? bestDay;
    var bestOrders = -1;
    final missing = <String>[];
    final breakdown = <DayBreakdown>[];

    for (final day in days) {
      final key = WeekCalendar.dateKey(day);
      final order = _orders.get(key);
      final minutes = recordedMinutesForDate(key);
      final sched = schedByDay[key];
      final isWorking = sched?.isWorkingDay ?? true;
      final planned = (sched?.netPlannedMinutes ?? 0) / 60.0;

      final hasData = order != null || minutes > 0;
      if (!hasData) missing.add(key);
      if (hasData) recordedDays++;

      final orders = order?.completedOrders;
      // v27: the salary's daily fixed pay counts ONLY days with at
      // least one counted order — a stored 0 or a session-only day
      // earns nothing.
      if (orders != null && orders >= 1) paidDays++;
      if (orders != null) {
        totalOrders += orders;
        if (orders > bestOrders) {
          bestOrders = orders;
          bestDay = key;
        }
      }
      final kmOut = order?.totalKmOut ?? 0;
      final kmBack = order?.totalKmBack ?? 0;
      totalKmOut += kmOut;
      totalKmBack += kmBack;
      // v27.5 bonuses for the day. Distance: only a COMPLETED order
      // has a finalized round-trip distance to tier against (count-only
      // entries complete with 0 km, so they earn none). Manual: counts
      // for every counted order (status >= 1), independent of the
      // distance-bonus flag.
      var dayDistanceBonus = 0.0;
      var dayManualBonus = 0.0;
      for (final e in order?.entries ?? const <OrderEntry>[]) {
        if (e.status >= 1 && e.manualBonusEgp > 0) {
          dayManualBonus += e.manualBonusEgp;
        }
        if (distanceBonusOn && e.isCompleted) {
          dayDistanceBonus +=
              distanceBonusFor(e.effectiveKmTotal, bonusTiers);
        }
      }
      totalDistanceBonus += dayDistanceBonus;
      totalManualBonus += dayManualBonus;
      // v26: planned schedule hours count as worked when the day has at
      // least one logged order but no recorded session (derived only).
      final effMinutes = effectiveWorkMinutes(
        recordedMinutes: minutes,
        orders: orders,
        schedule: sched,
      );
      totalMinutes += effMinutes;
      if (isWorking && hasData) {
        workingDaysWithData++;
        workingMinutesSum += effMinutes;
      }
      breakdown.add(DayBreakdown(
        dateKey: key,
        orders: orders,
        workMinutes: effMinutes,
        plannedHours: planned,
        isWorkingDay: isWorking,
        kmOut: kmOut,
        kmBack: kmBack,
        distanceBonus: dayDistanceBonus,
        manualBonus: dayManualBonus,
        // v27.6: the day's counted orders each earn the flat amount.
        flatBonus: (orders ?? 0) * flatPerOrder,
      ));
    }

    final totalHours = totalMinutes / 60.0;
    final plannedHours =
        schedule?.totalPlannedHours ?? 0.0;

    double? avgOrders;
    if (workingDaysWithData > 0) {
      var sum = 0;
      var n = 0;
      for (final d in breakdown) {
        if (d.isWorkingDay && d.orders != null) {
          sum += d.orders!;
          n++;
        }
      }
      if (n > 0) avgOrders = sum / n;
    }
    double? avgHours;
    if (workingDaysWithData > 0) avgHours = (workingMinutesSum / 60.0) / workingDaysWithData;
    double? ordersPerHour;
    if (totalHours > 0) ordersPerHour = totalOrders / totalHours;

    return WeeklyReport(
      weekStartKey: WeekCalendar.dateKey(start),
      weekEndKey: WeekCalendar.dateKey(start.add(const Duration(days: 6))),
      totalOrders: totalOrders,
      totalRecordedHours: totalHours,
      totalPlannedHours: plannedHours,
      days: breakdown,
      averageOrdersPerWorkingDay: avgOrders,
      averageHoursPerWorkingDay: avgHours,
      ordersPerWorkingHour: ordersPerHour,
      bestDayKey: bestDay,
      missingRecordDates: missing,
      recordedDaysCount: recordedDays,
      paidDaysCount: paidDays,
      totalKmOut: totalKmOut,
      totalKmBack: totalKmBack,
      totalDistanceBonus: totalDistanceBonus,
      totalManualBonus: totalManualBonus,
      distanceBonusEnabled: distanceBonusOn,
      flatOrderBonusEgp: flatPerOrder,
    );
  }

  /// Shareable plain-text summary of a report.
  String reportShareText(WeeklyReport r,
      {required String Function(String) dayLabel}) {
    final b = StringBuffer();
    b.writeln('${r.weekStartKey} – ${r.weekEndKey}');
    b.writeln('Orders: ${r.totalOrders}');
    b.writeln('Hours: ${WeekCalendar.formatHours(r.totalRecordedHours)}');
    if (r.averageOrdersPerWorkingDay != null) {
      b.writeln(
          'Avg/day: ${r.averageOrdersPerWorkingDay!.toStringAsFixed(1)}');
    }
    if (r.bestDayKey != null) b.writeln('Best day: ${dayLabel(r.bestDayKey!)}');
    if (r.missingRecordDates.isNotEmpty) {
      b.writeln('Missing: ${r.missingRecordDates.length} day(s)');
    }
    return b.toString();
  }
}
