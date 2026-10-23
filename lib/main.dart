import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app/app.dart';
import 'core/database/database_service.dart';
import 'core/date_time/week_calendar.dart';
import 'core/logging/app_log_service.dart';
import 'core/notifications/notification_service.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Communication port for background GPS tracking isolate.
  FlutterForegroundTask.initCommunicationPort();

  // Edge-to-edge: draw behind system bars so the aurora theme reaches
  // the screen edges instead of black bars.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Transparent system bars: no black rectangle behind the floating
  // nav bar in the Android gesture/button navigation area.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // v27.2: diagnostics log FIRST — the services below record into it
  // (init outcomes, schema migrations, scheduling attempts). Best
  // effort: if it can't open, the app runs with logging as a no-op.
  final appLog = AppLogService();
  try {
    await appLog.init();
  } catch (_) {}

  // Local-first storage.
  final db = DatabaseService(log: appLog);
  await db.init();

  // Local notifications (best effort — never crash startup).
  final notif = NotificationService(log: appLog);
  try {
    await notif.init();
  } catch (_) {}

  // Record the launch (with the running version) in the log.
  try {
    final info = await PackageInfo.fromPlatform();
    appLog.info(
      AppLogCategory.system,
      'App start — DeliveryFlow ${info.version}+${info.buildNumber}',
    );
  } catch (_) {}

  runApp(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(notif),
        appLogServiceProvider.overrideWithValue(appLog),
      ],
      child: const DeliveryFlowApp(),
    ),
  );

  // Reschedule reminders on every launch (also covers device reboot).
  // Runs after first frame so providers are ready.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final settings = db.settings;
      await notif.rescheduleAll(
        settings: settings,
        hasOrderRecord: (k) => db.orderRecord(k) != null,
        isWorkingDay: (k) {
          final sched = db.scheduleForWeek(WeekCalendar.parseDateKey(k));
          if (sched == null) return true;
          for (final d in sched.dailySchedules) {
            if (d.dateKey == k) return d.isWorkingDay;
          }
          return true;
        },
        scheduleForDate: (k) {
          final sched = db.scheduleForWeek(WeekCalendar.parseDateKey(k));
          if (sched == null) return null;
          for (final d in sched.dailySchedules) {
            if (d.dateKey == k) return d;
          }
          return null;
        },
      );
      // v27.4: every pending schedule now points at the new
      // Importance.max channel — both legacy channels can go.
      await notif.deleteLegacyChannels();
    } catch (_) {}
  });
}
