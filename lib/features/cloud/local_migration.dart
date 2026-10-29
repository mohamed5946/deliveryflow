// v27.33 — First-login local-data migration builder.
//
// Upgraders (gate already passed, local Hive data present) get a
// ONE-TIME offer after their first cloud sign-in: upload their local
// days under their UID. This builder converts local Hive records
// into cloud day summaries using the app's OWN weekly-report math
// ([DatabaseService.buildWeeklyReport]): per-day orders, km, and
// distance/manual/flat bonuses come from DayBreakdown, and the
// salary total comes from [buildDaySummary] (the shared formula) —
// so migrated summaries match the local weekly view exactly.
// Raw order records migrate alongside (dateKey, completed orders,
// total km) for the driver's detail views.
//
// Nothing here uploads: the caller passes the result to
// [CloudSyncService.migrateLocalDataOnce], which enforces the
// upload-once marker (UserSettings.cloudMigratedUid).
import '../../core/cloud/cloud_types.dart';
import '../../core/database/database_service.dart';
import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';

class LocalMigrationData {
  const LocalMigrationData({
    required this.summaries,
    required this.orders,
  });

  final List<CloudDaySummary> summaries;
  final List<Map<String, dynamic>> orders;
}

LocalMigrationData buildLocalMigrationData(
  DatabaseService db,
  UserSettings settings,
  String uid,
) {
  final records = db.allOrderRecords;
  final weekStarts = <String>{};
  for (final record in records) {
    final day = WeekCalendar.parseDateKey(record.dateKey);
    weekStarts.add(
      WeekCalendar.dateKey(WeekCalendar.weekStart(day)),
    );
  }
  final summaries = <CloudDaySummary>[];
  for (final weekKey in weekStarts) {
    final report = db.buildWeeklyReport(
      WeekCalendar.parseDateKey(weekKey),
    );
    for (final day in report.days) {
      if (day.orders == null) continue;
      summaries.add(
        buildDaySummary(
          uid: uid,
          dateKey: day.dateKey,
          ordersCount: day.orders!,
          totalKm: day.kmTotal,
          orderPrice: settings.orderPrice ?? 0,
          dailyFixedPay: settings.dailyFixedPay ?? 0,
          distanceBonus: day.distanceBonus,
          manualBonus: day.manualBonus,
          flatBonus: day.flatBonus,
        ),
      );
    }
  }
  final orders = [
    for (final record in records)
      {
        'dateKey': record.dateKey,
        'completedOrders': record.completedOrders,
        'totalKm': record.totalKm,
      },
  ];
  return LocalMigrationData(summaries: summaries, orders: orders);
}
