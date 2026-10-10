import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../date_time/week_calendar.dart';
import '../database/models.dart';

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
  static const int _testId = 9999;

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
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
  });
}
