import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/database/database_service.dart';
import 'core/date_time/week_calendar.dart';
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

  // Local-first storage.
  final db = DatabaseService();
  await db.init();

  // Local notifications (best effort — never crash startup).
  final notif = NotificationService();
  try {
    await notif.init();
  } catch (_) {}

  runApp(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(notif),
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
          final sched =
              db.scheduleForWeek(WeekCalendar.parseDateKey(k));
          if (sched == null) return true;
          for (final d in sched.dailySchedules) {
            if (d.dateKey == k) return d.isWorkingDay;
          }
          return true;
        },
      );
    } catch (_) {}
  });
}
