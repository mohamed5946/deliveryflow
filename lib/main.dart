import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app/app.dart';
import 'core/cloud/cloud_init.dart';
import 'core/cloud/cloud_providers.dart';
import 'core/cloud/cloud_types.dart';
import 'core/database/database_service.dart';
import 'core/date_time/week_calendar.dart';
import 'core/logging/app_log_service.dart';
import 'core/logging/frame_timing_collector.dart';
import 'core/notifications/notification_service.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // v27.21: cheap app-wide frame-timing collection for the
  // diagnostics log screen (last 120 frames, no per-frame logging).
  frameTimingCollector.start();

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

  // v27.33: cloud backend — real Firebase project (see
  // lib/firebase_options.dart). If init fails for any reason this
  // returns NotConfiguredBackend and the app stays local-only; the
  // Profile cloud screens show the not-configured state.
  final cloudBackend = await initCloudBackend();
  final cloudConfigured = cloudBackendIsConfigured(cloudBackend);
  if (!cloudConfigured) {
    appLog.info(
      AppLogCategory.system,
      'Cloud not configured (no Firebase project yet) — local-only mode',
    );
  }

  // v27.33 session persistence: Firebase Auth restores its own
  // session natively (stored refresh token) across app restarts,
  // phone reboots, and background kills. Seed the account state
  // from it so a restart NEVER shows a login screen to a signed-in
  // user. Only an explicit sign-out ends the session. The
  // fingerprint lock is a lock screen, not a logout — it never
  // touches this state.
  CloudAccount? restoredAccount;
  // v27.35 blacklist: a restored session belonging to a blocked
  // account is signed out by the restore gate — remember that it
  // was blocked (not just "no session") so the account screen can
  // show the blocked message instead of a bare login form.
  var restoredBlocked = false;
  try {
    restoredAccount = await cloudBackend.restoreSession();
  } on CloudAccountBlocked {
    restoredAccount = null;
    restoredBlocked = true;
  } catch (_) {
    restoredAccount = null;
  }

  runApp(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(notif),
        appLogServiceProvider.overrideWithValue(appLog),
        cloudBackendProvider.overrideWithValue(cloudBackend),
        cloudConfiguredProvider.overrideWithValue(cloudConfigured),
        if (restoredAccount != null)
          cloudAccountProvider.overrideWith(
            (ref) => CloudAccountNotifier(
              ref.watch(cloudAuthServiceProvider),
              ref.watch(cloudSyncServiceProvider),
            )..seedRestoredSession(restoredAccount!),
          ),
        if (restoredBlocked)
          cloudAccountProvider.overrideWith(
            (ref) => CloudAccountNotifier(
              ref.watch(cloudAuthServiceProvider),
              ref.watch(cloudSyncServiceProvider),
            )..seedError('This account has been blocked.'),
          ),
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
