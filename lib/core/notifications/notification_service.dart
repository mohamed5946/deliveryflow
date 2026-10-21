import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../date_time/week_calendar.dart';
import '../database/models.dart';

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
  static const String channelId = 'deliveryflow_reminders';
  static const String channelName = 'Reminders';
  static const String channelDesc =
      'Schedule, daily order and weekly report reminders';

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
    } catch (_) {
      // Keep the UTC fallback — scheduling still works, just offset.
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDesc,
      importance: Importance.defaultImportance,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    _initialized = true;
  }

  /// Requests POST_NOTIFICATIONS (Android 13+) and returns the result.
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final granted = await android.requestNotificationsPermission();
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
      return can ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  Future<void> showTest({required String title, required String body}) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.defaultImportance,
      ),
    );
    await _plugin.show(_testId, title, body, details);
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
    var candidate = tz.TZDateTime(
        tz.local, day.year, day.month, day.day, hour, minute).add(Duration(days: delta));
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
    final details = const NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.defaultImportance,
      ),
    );
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      details,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
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
    if (!settings.notificationsEnabled) return;

    final strings = _LocalizedStrings(settings.languageCode);
    final exact = await requestExactAlarmPermission();

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
        await _plugin.zonedSchedule(
          _followUpBase + i,
          strings.followUpTitle,
          strings.followUpBody,
          when,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              channelDescription: channelDesc,
              importance: Importance.defaultImportance,
            ),
          ),
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }

    // v26 shift-end reminders (opt-in): at each working day's shift end,
    // remind him to log that day's orders. Overnight shifts also get a
    // 23:55 reminder (see shiftEndReminderTimes). Scheduled for the next
    // 14 days like follow-ups; rescheduleAll re-runs on app start, on
    // settings changes and on schedule changes (refreshReminders).
    if (settings.shiftEndReminderEnabled && scheduleForDate != null) {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.defaultImportance,
        ),
      );
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
          await _plugin.zonedSchedule(
            _shiftEndBase + i * 2 + j,
            t.preMidnight ? strings.shiftPreMidnightTitle : strings.shiftEndTitle,
            t.preMidnight
                ? strings.shiftPreMidnightBody
                : (overnight
                    ? strings.shiftOvernightEndBody
                    : strings.shiftEndBody),
            when,
            details,
            androidScheduleMode: exact
                ? AndroidScheduleMode.exactAllowWhileIdle
                : AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        }
      }
    }

    // Saturday schedule reminder (weekday 6).
    if (settings.scheduleReminderEnabled) {
      await _plugin.zonedSchedule(
        _scheduleId,
        strings.scheduleTitle,
        strings.scheduleBody,
        _nextWeekday(6, settings.scheduleReminderHour,
            settings.scheduleReminderMinute),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDesc,
            importance: Importance.defaultImportance,
          ),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }

    // Saturday report reminder (weekday 6).
    if (settings.reportReminderEnabled) {
      await _plugin.zonedSchedule(
        _reportId,
        strings.reportTitle,
        strings.reportBody,
        _nextWeekday(6, settings.reportReminderHour,
            settings.reportReminderMinute),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDesc,
            importance: Importance.defaultImportance,
          ),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
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
        dailyTitle: 'مساء الخير! 🚚 خلصت شغل النهارده؟ سجل عدد الأوردرات اللي عملتها.',
        dailyBody: 'سجّل أوردرات النهارده وساعات شغلك عشان تقريرك يفضل دقيق.',
        followUpTitle: 'تذكير',
        followUpBody: 'لسه مسجلتش أوردرات النهارده.',
        scheduleTitle: 'خطط للأسبوع القادم 📅',
        scheduleBody:
            'جهّز جدول الأسبوع الجديد! حدّد مواعيد شغلك من الأحد للسبت.',
        reportTitle: 'تقرير الأسبوع جاهز 📊',
        reportBody: 'تقرير الأسبوع جاهز! شوف إجمالي أوردراتك وساعات شغلك.',
        shiftEndTitle: 'خلصت الشيفت؟ 🏁',
        shiftEndBody:
            'سجّل أوردرات اليوم وانت فاكرها — دي آخر خطوة في يومك.',
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
