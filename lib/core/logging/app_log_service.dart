import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

/// v27.2: in-app diagnostics log — the app's black box.
///
/// Why this exists: the notification saga (v26–v27.1) burned three
/// releases on blind guessing because nothing inside the app recorded
/// WHAT it did or WHY it failed. This service records the critical
/// paths (notifications, tracking, orders, share, system, settings) so
/// the next failure is read from the log, not guessed.
///
/// Design rules:
/// - SINGLE responsibility: record, cap, read, export, clear entries.
///   It knows nothing about notifications/tracking/orders themselves.
/// - Logging must NEVER crash, throw or block the app: [log] is
///   fire-and-forget, swallows every internal error, and is a no-op
///   until [init] has opened the box.
/// - Cheap: entries are tiny JSON strings in their own Hive box, hard
///   capped at [maxEntries] with the oldest pruned automatically.
enum AppLogCategory {
  notifications,
  tracking,
  orders,
  share,
  system,
  settings,
  reports, // v27.4: PDF report generation outcomes
  schedule, // v27.10: stored-week normalization / startup repair
}

enum AppLogLevel { info, warn, error }

/// One diagnostics entry. Immutable; persisted as a JSON string.
class AppLogEntry {
  final int timestampMillis;
  final AppLogCategory category;
  final AppLogLevel level;
  final String message;

  /// Optional technical detail (usually an exception type + message).
  final String? detail;

  const AppLogEntry({
    required this.timestampMillis,
    required this.category,
    required this.level,
    required this.message,
    this.detail,
  });

  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(timestampMillis);

  Map<String, dynamic> toJson() => {
        't': timestampMillis,
        'c': category.name,
        'l': level.name,
        'm': message,
        if (detail != null) 'd': detail,
      };

  String encode() => jsonEncode(toJson());

  /// Tolerant decode: a corrupt or foreign value yields null instead of
  /// throwing, so one bad stored string can never break the viewer.
  static AppLogEntry? tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final m = Map<String, dynamic>.from(decoded);
      final t = (m['t'] as num?)?.toInt();
      final message = m['m'] as String?;
      if (t == null || message == null) return null;
      return AppLogEntry(
        timestampMillis: t,
        category: AppLogCategory.values.firstWhere(
          (c) => c.name == m['c'],
          orElse: () => AppLogCategory.system,
        ),
        level: AppLogLevel.values.firstWhere(
          (l) => l.name == m['l'],
          orElse: () => AppLogLevel.info,
        ),
        message: message,
        detail: m['d'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// One plain-text line, used by copy/export:
  /// `[2026-10-22 10:45:03] [notifications] [ERROR] msg — Type: detail`.
  String toTextLine() {
    final t = timestamp;
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    final base =
        '[$stamp] [${category.name}] [${level.name.toUpperCase()}] $message';
    return detail == null ? base : '$base — $detail';
  }
}

/// Formats any thrown object as `Type: message` for log details and
/// the technical-reason line in failure dialogs.
String formatLogError(Object error) => '${error.runtimeType}: $error';

class AppLogService {
  static const String boxName = 'app_log';
  static const int maxEntries = 500;

  Box<String>? _box;

  bool get isReady => _box != null;

  Future<void> init({String? hivePath}) async {
    if (_box != null) return;
    if (hivePath != null) {
      Hive.init(hivePath);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      Hive.init(dir.path);
    }
    _box = await Hive.openBox<String>(boxName);
  }

  /// Fire-and-forget append. Never throws, never blocks: the actual
  /// Hive write is unawaited and every failure is swallowed — a broken
  /// log must never take the app down with it.
  void log(
    AppLogCategory category,
    AppLogLevel level,
    String message, {
    Object? error,
    String? detail,
  }) {
    final box = _box;
    if (box == null) return;
    try {
      // An explicit detail and a thrown error can coexist (e.g. the
      // received share text AND the parse exception) — keep both.
      final detailParts = [
        if (detail != null) detail,
        if (error != null) formatLogError(error),
      ];
      final entry = AppLogEntry(
        timestampMillis: DateTime.now().millisecondsSinceEpoch,
        category: category,
        level: level,
        message: message,
        detail: detailParts.isEmpty ? null : detailParts.join(' — '),
      );
      unawaited(
        box.add(entry.encode()).then((_) => _prune(box)).catchError((_) {}),
      );
    } catch (_) {
      // Swallow: logging is best-effort by contract.
    }
  }

  void info(AppLogCategory category, String message, {String? detail}) =>
      log(category, AppLogLevel.info, message, detail: detail);

  void warn(AppLogCategory category, String message,
          {Object? error, String? detail}) =>
      log(category, AppLogLevel.warn, message, error: error, detail: detail);

  void error(AppLogCategory category, String message,
          {Object? error, String? detail}) =>
      log(category, AppLogLevel.error, message, error: error, detail: detail);

  /// Drops the oldest entries once the box grows past [maxEntries].
  /// Box keys from `add()` auto-increment, so ascending keys are the
  /// oldest entries. Runs inside the write chain; errors swallowed by
  /// the caller's catchError.
  Future<void> _prune(Box<String> box) async {
    final excess = box.length - maxEntries;
    if (excess <= 0) return;
    final keys = box.keys.cast<int>().toList()..sort();
    await box.deleteAll(keys.take(excess));
  }

  /// All stored entries, NEWEST first. Corrupt values are skipped.
  /// [category] filters to a single قسم when given.
  List<AppLogEntry> entries({AppLogCategory? category}) {
    final box = _box;
    if (box == null) return const [];
    final keys = box.keys.cast<int>().toList()..sort();
    final result = <AppLogEntry>[];
    for (final key in keys.reversed) {
      final raw = box.get(key);
      if (raw == null) continue;
      final entry = AppLogEntry.tryDecode(raw);
      if (entry == null) continue;
      if (category != null && entry.category != category) continue;
      result.add(entry);
    }
    return result;
  }

  int get length => _box?.length ?? 0;

  Future<void> clear() async {
    try {
      await _box?.clear();
    } catch (_) {}
  }

  /// Whole log as plain text, oldest first (reads like a log file),
  /// ready for the clipboard or the share sheet.
  String exportText() {
    final chronological = entries().reversed.toList();
    final buffer = StringBuffer('DeliveryFlow diagnostics log '
        '(${chronological.length} entries)');
    for (final e in chronological) {
      buffer.writeln();
      buffer.write(e.toTextLine());
    }
    return buffer.toString();
  }

  /// Groups the current entries by category for the viewer's filter
  /// chips (only categories that actually have entries).
  Set<AppLogCategory> get presentCategories {
    // A set literal is insertion-ordered (LinkedHashSet) in Dart.
    final set = <AppLogCategory>{};
    for (final e in entries()) {
      set.add(e.category);
    }
    return set;
  }
}
