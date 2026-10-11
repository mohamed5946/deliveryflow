import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../date_time/week_calendar.dart';
import 'models.dart';

/// Local-first persistence layer built on Hive.
///
/// Boxes:
/// - `settings`   : single [UserSettings] under key `'user'`.
/// - `schedules`   : [WorkSchedule] keyed by week-start dateKey (unique per week).
/// - `orders`     : [DailyOrderRecord] keyed by dateKey (unique per day).
/// - `sessions`   : [WorkSession] with auto-increment int keys.
/// - `meta`       : schema version + misc flags.
class DatabaseService {
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

  Future<void> _migrateIfNeeded() async {
    final stored = _meta.get('schemaVersion') as int?;
    if (stored == null || stored < kSchemaVersion) {
      // v1 is the first schema; future versions migrate here.
      await _meta.put('schemaVersion', kSchemaVersion);
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
    record.completedOrders = record.completedOrders + 1;
    record.isConfirmed = true;
    record.updatedAtMillis = now;
    await _orders.put(dateKey, record);
    return entry;
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
    record.updatedAtMillis = DateTime.now().millisecondsSinceEpoch;
    await record.save();
  }

  /// Deletes one order entry and decrements the day's order count.
  Future<void> deleteOrderEntry({
    required String dateKey,
    required String entryId,
  }) async {
    final record = _orders.get(dateKey);
    if (record == null) return;
    final before = record.entries.length;
    record.entries.removeWhere((e) => e.id == entryId);
    if (record.entries.length < before) {
      record.completedOrders =
          (record.completedOrders - 1).clamp(0, 1 << 30);
      record.updatedAtMillis = DateTime.now().millisecondsSinceEpoch;
      await record.save();
    }
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

    var totalOrders = 0;
    var totalMinutes = 0;
    var recordedDays = 0;
    var workingDaysWithData = 0;
    var workingMinutesSum = 0;
    var totalKmOut = 0.0;
    var totalKmBack = 0.0;
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
      totalMinutes += minutes;
      if (isWorking && hasData) {
        workingDaysWithData++;
        workingMinutesSum += minutes;
      }
      breakdown.add(DayBreakdown(
        dateKey: key,
        orders: orders,
        workMinutes: minutes,
        plannedHours: planned,
        isWorkingDay: isWorking,
        kmOut: kmOut,
        kmBack: kmBack,
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
      totalKmOut: totalKmOut,
      totalKmBack: totalKmBack,
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
