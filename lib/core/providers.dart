import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/database_service.dart';
import '../core/database/models.dart';
import '../core/date_time/week_calendar.dart';
import '../core/logging/app_log_service.dart';
import '../core/notifications/notification_service.dart';

/// Overridden in main() after async init.
final databaseServiceProvider =
    Provider<DatabaseService>((ref) => throw UnimplementedError());

final notificationServiceProvider =
    Provider<NotificationService>((ref) => throw UnimplementedError());

/// v27.2: diagnostics log. Overridden in main() with the initialized
/// instance; the default is an uninitialized service whose log calls
/// are safe no-ops (keeps tests and previews working untouched).
final appLogServiceProvider =
    Provider<AppLogService>((ref) => AppLogService());

/// Bumped whenever records change so report providers refresh.
final dataVersionProvider = StateProvider<int>((ref) => 0);

void bumpDataVersion(WidgetRef ref) =>
    ref.read(dataVersionProvider.notifier).state++;

class SettingsNotifier extends StateNotifier<UserSettings> {
  SettingsNotifier(this._db, this._notif, {AppLogService? log})
      : _log = log,
        super(_db.settings);

  final DatabaseService _db;
  final NotificationService _notif;
  final AppLogService? _log;

  Future<void> update(UserSettings Function(UserSettings s) apply) async {
    final next = apply(state);
    await _db.saveSettings(next);
    if (!mounted) return;
    // Assign a fresh instance so listeners always rebuild.
    state = UserSettings.fromJson(next.toJson());
    await _reschedule();
  }

  Future<void> _reschedule() async {
    try {
      await _notif.rescheduleAll(
        settings: state,
        hasOrderRecord: (k) => _db.orderRecord(k) != null,
        isWorkingDay: (k) {
          final sched =
              _db.scheduleForWeek(WeekCalendar.parseDateKey(k));
          if (sched == null) return true;
          for (final d in sched.dailySchedules) {
            if (d.dateKey == k) return d.isWorkingDay;
          }
          return true;
        },
        scheduleForDate: (k) {
          final sched =
              _db.scheduleForWeek(WeekCalendar.parseDateKey(k));
          if (sched == null) return null;
          for (final d in sched.dailySchedules) {
            if (d.dateKey == k) return d;
          }
          return null;
        },
      );
    } catch (e) {
      // Notifications are best-effort; never break settings saves —
      // but since v27.2 the failure is at least recorded in the log.
      _log?.error(
        AppLogCategory.settings,
        'Reminder reschedule after a settings change failed',
        error: e,
      );
    }
  }

  /// Call after order/session/schedule changes.
  Future<void> refreshReminders() => _reschedule();
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, UserSettings>((ref) {
  return SettingsNotifier(
    ref.watch(databaseServiceProvider),
    ref.watch(notificationServiceProvider),
    log: ref.watch(appLogServiceProvider),
  );
});

/// Weekly report for the week containing [anyDay].
final weeklyReportProvider =
    FutureProvider.family<WeeklyReport, DateTime>((ref, anyDay) async {
  ref.watch(dataVersionProvider);
  final db = ref.watch(databaseServiceProvider);
  return db.buildWeeklyReport(anyDay);
});

/// All stored week-start keys, newest first (for history).
final historyWeeksProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(dataVersionProvider);
  // Derive from schedules + order records + sessions to include weeks that
  // have data but no schedule.
  final db = ref.watch(databaseServiceProvider);
  final keys = <String>{};
  // Access via public API: use reports' week keys is awkward; instead scan
  // a bounded window: last 52 weeks + any future scheduled weeks.
  final today = DateTime.now();
  for (var i = 0; i < 52; i++) {
    final probe = WeekCalendar.addDays(today, -7 * i);
    final r = db.buildWeeklyReport(probe);
    if (r.recordedDaysCount > 0 ||
        db.scheduleForWeek(probe) != null) {
      keys.add(r.weekStartKey);
    }
  }
  final sorted = keys.toList()..sort((a, b) => b.compareTo(a));
  return sorted;
});
