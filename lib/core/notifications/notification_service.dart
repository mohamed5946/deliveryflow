import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../date_time/week_calendar.dart';
import '../database/models.dart';
import '../logging/app_log_service.dart';
import '../tracking/arrival_notifications.dart';

/// The Android schedule mode for a reminder: exact (fires on time,
/// needs the exact-alarm permission) or inexact.
AndroidScheduleMode androidScheduleModeFor(bool exact) => exact
    ? AndroidScheduleMode.exactAllowWhileIdle
    : AndroidScheduleMode.inexactAllowWhileIdle;

/// v27.1: whether a failed schedule attempt should be retried once
/// with the inexact mode. Only an exact-mode [PlatformException]
/// qualifies — on Android 14+ the exact-alarm permission can be
/// revoked (or misreported as granted) between the permission check
/// and the schedule call, and the exact call then throws; degrading
/// to inexact beats losing the reminder entirely.
bool shouldRetryInexact({required bool usedExact, required Object error}) =>
    usedExact && error is PlatformException;

/// One shift-end reminder instant (local wall-clock).
class ShiftEndReminderTime {
  final DateTime when;

  /// True for the 23:55 same-day reminder of an overnight shift.
  final bool preMidnight;

  const ShiftEndReminderTime(this.when, {this.preMidnight = false});
}

/// v26: reminder instants for a shift that starts on [day].
///
/// - Normal shift (end after start): one reminder at the shift end.
/// - Overnight shift (end <= start, so it ends the next day): TWO
///   reminders — one at 23:55 on [day] to log the pre-midnight orders,
///   and one at the shift end on the next day to log the rest.
List<ShiftEndReminderTime> shiftEndReminderTimes({
  required DateTime day,
  required int startMinutes,
  required int endMinutes,
}) {
  final base = DateTime(day.year, day.month, day.day);
  if (endMinutes > startMinutes) {
    return [ShiftEndReminderTime(base.add(Duration(minutes: endMinutes)))];
  }
  return [
    ShiftEndReminderTime(base.add(const Duration(hours: 23, minutes: 55)),
        preMidnight: true),
    ShiftEndReminderTime(base.add(Duration(days: 1, minutes: endMinutes))),
  ];
}

/// Local-only notification scheduling.
///
/// - One Android channel for reminders.
/// - Timezone-aware scheduling via the `timezone` package.
/// - Stable notification IDs derived from (kind, dateKey) so rescheduling
///   never duplicates.
/// - Every [rescheduleAll] cancels first, then re-schedules: idempotent.
class NotificationService {
  /// v27.2: optional diagnostics log (constructor-injected from main;
  /// null in tests — all logging then no-ops). Scheduling outcomes,
  /// permission states and the EXACT exception of every failed attempt
  /// land here, ending the blind-debugging era of this saga.
  NotificationService({AppLogService? log}) : _log = log;

  final AppLogService? _log;

  /// v27.3: reminders moved to a fresh channel. The original
  /// 'deliveryflow_reminders' channel was created by an old build with
  /// low importance, and Android freezes a channel's importance at
  /// creation — notifications landed in the shade's silent section and
  /// the app could never raise it in place.
  ///
  /// v27.4: STILL landing silently on Mohamed's phone despite the v2
  /// channel, so reminders move once more — to
  /// 'deliveryflow_reminders_v3', created explicitly with
  /// Importance.max (sound + vibration) so they post at the very top
  /// of the shade. Both legacy channels are deleted on launch once
  /// pending schedules point at the new one (see main).
  static const String channelId = 'deliveryflow_reminders_v3';
  static const String legacyChannelId = 'deliveryflow_reminders';
  static const String legacyChannelIdV2 = 'deliveryflow_reminders_v2';
  static const String channelName = 'Reminders';
  static const String channelDesc =
      'Schedule, daily order and weekly report reminders';

  /// v27.4: ONE details object for every user-facing notification —
  /// maximum importance/priority, reminder category, public visibility
  /// — so reminders and both tests always post heads-up at the top of
  /// the shade instead of the silent section.
  static const AndroidNotificationDetails reminderAndroidDetails =
      AndroidNotificationDetails(
    channelId,
    channelName,
    channelDescription: channelDesc,
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.reminder,
    visibility: NotificationVisibility.public,
  );
  static const NotificationDetails reminderDetails =
      NotificationDetails(android: reminderAndroidDetails);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Notification IDs (stable ranges)
  static const int _dailyBase = 1000;
  static const int _followUpBase = 2000;
  static const int _scheduleId = 3001;
  static const int _reportId = 3002;
  static const int _shiftEndBase = 4000; // + dayOffset*2 + slot
  static const int _testId = 9999;
  static const int _testScheduledId = 9998;

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    // v26 fix: tz.local defaults to UTC when setLocalLocation is never
    // called, so every zonedSchedule fired on UTC wall-clock (3 hours off
    // Cairo) and enabled reminders effectively never arrived. Resolve the
    // device timezone and set it BEFORE any scheduling happens.
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // Keep the UTC fallback — scheduling still works, just offset.
      _log?.warn(
        AppLogCategory.notifications,
        'Timezone resolution failed — scheduling on the UTC fallback',
        error: e,
      );
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    try {
      // v27.8: arrival-prompt «لا» taps are recorded into the shared
      // response file the tracking isolate polls — in the foreground
      // via this handler, in the background via the entry-point one.
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) {
          handleArrivalNotificationResponse(response);
        },
        onDidReceiveBackgroundNotificationResponse:
            arrivalNotificationResponseBackground,
      );
      // v27.4: create the v3 channel EXPLICITLY at Importance.max
      // with sound + vibration — the strongest posting Android allows,
      // so reminders land at the very top of the shade, never silent.
      const channel = AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      // v27.8: the arrival-detection channel, also at Importance.max
      // (the tracking isolate creates it too before first use —
      // channel creation is idempotent).
      const arrivalsChannel = AndroidNotificationChannel(
        ArrivalNotifications.channelId,
        ArrivalNotifications.channelName,
        description: ArrivalNotifications.channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(arrivalsChannel);
    } catch (e) {
      _log?.error(
        AppLogCategory.notifications,
        'Notification plugin init failed',
        error: e,
      );
      rethrow;
    }
    _initialized = true;
    _log?.info(
      AppLogCategory.notifications,
      'Notification service initialized (tz: ${tz.local.name})',
    );
  }

  /// v27.4: delete BOTH pre-v27.4 reminders channels (the original
  /// and the v27.3 v2 channel) after the launch reschedule has
  /// re-pointed every pending schedule at the Importance.max v3
  /// channel. Harmless when a channel does not exist (fresh installs);
  /// each deletion is guarded and the migration is recorded in the
  /// diagnostics log.
  Future<void> deleteLegacyChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    for (final id in [legacyChannelId, legacyChannelIdV2]) {
      try {
        await android.deleteNotificationChannel(id);
      } catch (e) {
        _log?.warn(
          AppLogCategory.notifications,
          'Legacy notification channel deletion failed ($id)',
          error: e,
        );
      }
    }
    _log?.info(
      AppLogCategory.notifications,
      'Legacy notification channels deleted '
      '(max-priority migration to $channelId)',
    );
  }

  /// v27.8: dismiss any arrival prompt still on screen (e.g. the
  /// courier pressed «وصلت للعميل» in the app while the 10-second
  /// auto-confirm countdown was running). Best effort.
  Future<void> cancelArrivalPrompts() async {
    try {
      await _plugin.cancel(ArrivalNotifications.outgoingNotificationId);
      await _plugin.cancel(ArrivalNotifications.returningNotificationId);
    } catch (_) {}
  }

  /// Requests POST_NOTIFICATIONS (Android 13+) and returns the result.
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final granted = await android.requestNotificationsPermission();
    _log?.log(
      AppLogCategory.notifications,
      (granted ?? false) ? AppLogLevel.info : AppLogLevel.warn,
      'POST_NOTIFICATIONS permission: ${granted ?? false}',
    );
    return granted ?? false;
  }

  /// Requests exact-alarm permission (Android 12+). Returns true when
  /// exact alarms can be used; otherwise scheduling falls back to inexact.
  Future<bool> requestExactAlarmPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    try {
      await android.requestExactAlarmsPermission();
      final can = await android.canScheduleExactNotifications();
      _log?.log(
        AppLogCategory.notifications,
        (can ?? false) ? AppLogLevel.info : AppLogLevel.warn,
        'Exact-alarm permission after request: ${can ?? false}',
      );
      return can ?? false;
    } catch (e) {
      _log?.error(
        AppLogCategory.notifications,
        'Exact-alarm permission request failed',
        error: e,
      );
      return false;
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  Future<void> showTest({required String title, required String body}) async {
    try {
      await _plugin.show(_testId, title, body, reminderDetails);
      _log?.info(
        AppLogCategory.notifications,
        'Instant test notification shown (id $_testId)',
      );
    } catch (e) {
      _log?.error(
        AppLogCategory.notifications,
        'Instant test notification FAILED',
        error: e,
      );
      rethrow;
    }
  }

  /// Schedules a one-off test notification ~60 seconds ahead through
  /// the SAME zonedSchedule path as the real reminders (same channel,
  /// exact mode when permitted, inexact otherwise), so the user can
  /// prove scheduled delivery end-to-end with the app closed
  /// (v27 diagnostics). One-off: no matchDateTimeComponents, unlike the
  /// recurring reminders.
  Future<void> showScheduledTest({
    required String title,
    required String body,
  }) async {
    final exact = await canScheduleExactNotifications();
    final when = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 60));
    _log?.info(
      AppLogCategory.notifications,
      'Scheduled test: target $when, exact=$exact (id $_testScheduledId)',
    );
    try {
      await _zonedScheduleWithFallback(
        id: _testScheduledId,
        title: title,
        body: body,
        when: when,
        details: reminderDetails,
        exact: exact,
      );
      _log?.info(
        AppLogCategory.notifications,
        'Scheduled test scheduled OK for $when',
      );
    } catch (e) {
      _log?.error(
        AppLogCategory.notifications,
        'Scheduled test FAILED to schedule for $when',
        error: e,
      );
      rethrow;
    }
  }

  /// Whether exact alarms may be scheduled right now (Android 12+).
  /// When false, reminders fall back to inexact scheduling and can
  /// arrive late — the settings UI surfaces this state (v27). Query
  /// only: never opens any system screen.
  ///
  /// v27.1: report the REAL platform answer. A null reply or a thrown
  /// error used to be treated as "granted" — an optimistic lie that
  /// sent exact-mode schedule calls in without permission, where they
  /// throw on Android 14+ and the reminder silently never lands.
  Future<bool> canScheduleExactNotifications() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    try {
      return await android.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------
  // v27.4: notification status-card reads (developer mode). Each one
  // answers from the LIVE platform state, never from cached settings.
  // ---------------------------------------------------------------

  /// Whether notifications are currently allowed for the app
  /// (POST_NOTIFICATIONS / app-level toggle). Fails safe to true on
  /// non-Android; false when the platform call itself fails (the
  /// status card then flags it instead of lying).
  Future<bool> notificationsPermissionGranted() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    try {
      return await android.areNotificationsEnabled() ?? true;
    } catch (_) {
      return false;
    }
  }

  /// The importance the system reports for the ACTIVE reminders
  /// channel (v3) — the ground truth for whether reminders post
  /// heads-up or land in the shade's silent section. Null when the
  /// channel can't be read (not created yet / non-Android / error).
  Future<Importance?> remindersChannelImportance() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return null;
    try {
      final channels = await android.getNotificationChannels();
      if (channels == null) return null;
      for (final c in channels) {
        if (c.id == channelId) return c.importance;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// How many notifications are currently scheduled (pending) with
  /// the plugin — the status card's proof that rescheduleAll worked.
  Future<int> pendingNotificationCount() async {
    try {
      return (await _plugin.pendingNotificationRequests()).length;
    } catch (_) {
      return 0;
    }
  }

  /// zonedSchedule with a one-shot safety net (v27.1): when the
  /// exact-mode call throws a [PlatformException] (permission revoked
  /// or misreported between check and call), retry ONCE inexactly
  /// instead of losing the notification. Any other failure, and any
  /// failure of the retry itself, propagates to the caller.
  Future<void> _zonedScheduleWithFallback({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required NotificationDetails details,
    required bool exact,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    // v27.2: EVERY attempt is recorded in the diagnostics log — id,
    // target time, mode, success, and on failure the exact exception
    // (both attempts). This is the line that ends the guessing.
    final mode = exact ? 'exact' : 'inexact';
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: androidScheduleModeFor(exact),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
      );
      _log?.info(
        AppLogCategory.notifications,
        'scheduled id=$id at $when mode=$mode',
      );
    } catch (e) {
      if (!shouldRetryInexact(usedExact: exact, error: e)) {
        _log?.error(
          AppLogCategory.notifications,
          'schedule FAILED id=$id at $when mode=$mode (no retry)',
          error: e,
        );
        rethrow;
      }
      _log?.warn(
        AppLogCategory.notifications,
        'schedule attempt failed id=$id mode=exact — retrying inexact',
        error: e,
      );
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: matchDateTimeComponents,
        );
        _log?.info(
          AppLogCategory.notifications,
          'scheduled id=$id at $when mode=inexact (retry)',
        );
      } catch (e2) {
        _log?.error(
          AppLogCategory.notifications,
          'schedule FAILED id=$id at $when mode=inexact (retry)',
          error: e2,
        );
        rethrow;
      }
    }
  }

  tz.TZDateTime _nextDaily(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Next occurrence of [weekday] (1=Mon..7=Sun) at [hour]:[minute].
  tz.TZDateTime _nextWeekday(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var day = tz.TZDateTime(tz.local, now.year, now.month, now.day);
    var delta = (weekday - day.weekday) % 7;
    var candidate =
        tz.TZDateTime(tz.local, day.year, day.month, day.day, hour, minute)
            .add(Duration(days: delta));
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  Future<void> _scheduleDaily({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
    required bool exact,
  }) async {
    await _zonedScheduleWithFallback(
      id: id,
      title: title,
      body: body,
      when: when,
      details: reminderDetails,
      exact: exact,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Rebuilds every scheduled reminder from [settings].
  ///
  /// - Daily order reminder: every day at the configured time.
  /// - Follow-up: 30 days of daily slots is wasteful; instead we schedule the
  ///   next 14 days and rely on [rescheduleAll] being called on app start and
  ///   on settings/record changes.
  /// - Schedule reminder: next Saturday at the configured time.
  /// - Report reminder: next Saturday at the configured time.
  Future<void> rescheduleAll({
    required UserSettings settings,
    required bool Function(String dateKey) hasOrderRecord,
    required bool Function(String dateKey) isWorkingDay,
    DailySchedule? Function(String dateKey)? scheduleForDate,
  }) async {
    await cancelAll();
    if (!settings.notificationsEnabled) {
      _log?.info(
        AppLogCategory.notifications,
        'rescheduleAll skipped: notifications disabled — 0 scheduled',
      );
      return;
    }

    final strings = _LocalizedStrings(settings.languageCode);
    final exact = await requestExactAlarmPermission();
    final int scheduled;
    try {
      scheduled = await _scheduleAllReminders(
        settings: settings,
        strings: strings,
        exact: exact,
        hasOrderRecord: hasOrderRecord,
        isWorkingDay: isWorkingDay,
        scheduleForDate: scheduleForDate,
      );
    } catch (e) {
      _log?.error(
        AppLogCategory.notifications,
        'rescheduleAll FAILED (exact=$exact)',
        error: e,
      );
      rethrow;
    }
    _log?.info(
      AppLogCategory.notifications,
      'rescheduleAll: $scheduled reminder(s) scheduled (exact=$exact)',
    );
  }

  /// The scheduling work of [rescheduleAll]; returns how many
  /// notifications were scheduled. Split out (v27.2) so the public
  /// method owns only the outcome logging and the count.
  Future<int> _scheduleAllReminders({
    required UserSettings settings,
    required _LocalizedStrings strings,
    required bool exact,
    required bool Function(String dateKey) hasOrderRecord,
    required bool Function(String dateKey) isWorkingDay,
    required DailySchedule? Function(String dateKey)? scheduleForDate,
  }) async {
    var scheduled = 0;

    // Daily order reminder (repeats daily at fixed time).
    if (settings.dailyReminderEnabled) {
      await _scheduleDaily(
        id: _dailyBase,
        when: _nextDaily(
            settings.dailyReminderHour, settings.dailyReminderMinute),
        title: strings.dailyTitle,
        body: strings.dailyBody,
        exact: exact,
      );
      scheduled++;
    }

    // Follow-up reminders for the next 14 days, skipped when a record
    // already exists or the day is a day off.
    if (settings.followUpReminderEnabled) {
      final now = DateTime.now();
      for (var i = 0; i < 14; i++) {
        final day = WeekCalendar.addDays(now, i);
        final key = WeekCalendar.dateKey(day);
        if (hasOrderRecord(key)) continue;
        if (!isWorkingDay(key)) continue;
        final when = tz.TZDateTime(
          tz.local,
          day.year,
          day.month,
          day.day,
          settings.followUpReminderHour,
          settings.followUpReminderMinute,
        );
        if (!when.isAfter(tz.TZDateTime.now(tz.local))) continue;
        await _zonedScheduleWithFallback(
          id: _followUpBase + i,
          title: strings.followUpTitle,
          body: strings.followUpBody,
          when: when,
          details: reminderDetails,
          exact: exact,
        );
        scheduled++;
      }
    }

    // v26 shift-end reminders (opt-in): at each working day's shift end,
    // remind him to log that day's orders. Overnight shifts also get a
    // 23:55 reminder (see shiftEndReminderTimes). Scheduled for the next
    // 14 days like follow-ups; rescheduleAll re-runs on app start, on
    // settings changes and on schedule changes (refreshReminders).
    if (settings.shiftEndReminderEnabled && scheduleForDate != null) {
      final tzNow = tz.TZDateTime.now(tz.local);
      final today = DateTime.now();
      for (var i = 0; i < 14; i++) {
        final day = WeekCalendar.addDays(today, i);
        final key = WeekCalendar.dateKey(day);
        final sched = scheduleForDate(key);
        if (sched == null || !sched.isWorkingDay) continue;
        final overnight = sched.endMinutes <= sched.startMinutes;
        final times = shiftEndReminderTimes(
          day: day,
          startMinutes: sched.startMinutes,
          endMinutes: sched.endMinutes,
        );
        for (var j = 0; j < times.length; j++) {
          final t = times[j];
          final when = tz.TZDateTime(tz.local, t.when.year, t.when.month,
              t.when.day, t.when.hour, t.when.minute);
          if (!when.isAfter(tzNow)) continue;
          await _zonedScheduleWithFallback(
            id: _shiftEndBase + i * 2 + j,
            title: t.preMidnight
                ? strings.shiftPreMidnightTitle
                : strings.shiftEndTitle,
            body: t.preMidnight
                ? strings.shiftPreMidnightBody
                : (overnight
                    ? strings.shiftOvernightEndBody
                    : strings.shiftEndBody),
            when: when,
            details: reminderDetails,
            exact: exact,
          );
          scheduled++;
        }
      }
    }

    // Saturday schedule reminder (weekday 6).
    if (settings.scheduleReminderEnabled) {
      await _zonedScheduleWithFallback(
        id: _scheduleId,
        title: strings.scheduleTitle,
        body: strings.scheduleBody,
        when: _nextWeekday(
            6, settings.scheduleReminderHour, settings.scheduleReminderMinute),
        details: reminderDetails,
        exact: exact,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      scheduled++;
    }

    // Saturday report reminder (weekday 6).
    if (settings.reportReminderEnabled) {
      await _zonedScheduleWithFallback(
        id: _reportId,
        title: strings.reportTitle,
        body: strings.reportBody,
        when: _nextWeekday(
            6, settings.reportReminderHour, settings.reportReminderMinute),
        details: reminderDetails,
        exact: exact,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      scheduled++;
    }
    return scheduled;
  }
}

/// Localized notification copy (Arabic default, English fallback).
class _LocalizedStrings {
  final String dailyTitle;
  final String dailyBody;
  final String followUpTitle;
  final String followUpBody;
  final String scheduleTitle;
  final String scheduleBody;
  final String reportTitle;
  final String reportBody;
  final String shiftEndTitle;
  final String shiftEndBody;
  final String shiftPreMidnightTitle;
  final String shiftPreMidnightBody;
  final String shiftOvernightEndBody;

  factory _LocalizedStrings(String languageCode) {
    if (languageCode == 'ar') {
      return const _LocalizedStrings._(
        dailyTitle:
            'مساء الخير! 🚚 خلصت شغل النهارده؟ سجل عدد الأوردرات اللي عملتها.',
        dailyBody: 'سجّل أوردرات النهارده وساعات شغلك عشان تقريرك يفضل دقيق.',
        followUpTitle: 'تذكير',
        followUpBody: 'لسه مسجلتش أوردرات النهارده.',
        scheduleTitle: 'خطط للأسبوع القادم 📅',
        scheduleBody:
            'جهّز جدول الأسبوع الجديد! حدّد مواعيد شغلك من الأحد للسبت.',
        reportTitle: 'تقرير الأسبوع جاهز 📊',
        reportBody: 'تقرير الأسبوع جاهز! شوف إجمالي أوردراتك وساعات شغلك.',
        shiftEndTitle: 'خلصت الشيفت؟ 🏁',
        shiftEndBody: 'سجّل أوردرات اليوم وانت فاكرها — دي آخر خطوة في يومك.',
        shiftPreMidnightTitle: 'قبل ما اليوم يخلص 🌙',
        shiftPreMidnightBody:
            'سجّل أوردرات النهارده اللي عملتها لحد دلوقتي، وبكرة كمّل باقي الشيفت.',
        shiftOvernightEndBody:
            'سجّل باقي أوردرات الشيفت اللي خلّصته عشان يومك يبقى كامل.',
      );
    }
    return const _LocalizedStrings._(
      dailyTitle: 'Good evening! 🚚',
      dailyBody:
          "How many orders did you complete today? Open DeliveryFlow to record them.",
      followUpTitle: 'Reminder',
      followUpBody: "You haven't recorded today's orders yet.",
      scheduleTitle: 'Plan next week 📅',
      scheduleBody:
          'Prepare your next work week. Set your Sunday-to-Saturday schedule.',
      reportTitle: 'Weekly report ready 📊',
      reportBody:
          'Your weekly report is ready. Review your orders and working hours.',
      shiftEndTitle: 'Shift over? 🏁',
      shiftEndBody:
          "Log today's orders while they're fresh — the last step of your day.",
      shiftPreMidnightTitle: 'Before the day ends 🌙',
      shiftPreMidnightBody:
          "Log today's orders so far — you'll add the rest when your shift ends.",
      shiftOvernightEndBody:
          'Log the remaining orders from your finished shift to complete the day.',
    );
  }

  const _LocalizedStrings._({
    required this.dailyTitle,
    required this.dailyBody,
    required this.followUpTitle,
    required this.followUpBody,
    required this.scheduleTitle,
    required this.scheduleBody,
    required this.reportTitle,
    required this.reportBody,
    required this.shiftEndTitle,
    required this.shiftEndBody,
    required this.shiftPreMidnightTitle,
    required this.shiftPreMidnightBody,
    required this.shiftOvernightEndBody,
  });
}
