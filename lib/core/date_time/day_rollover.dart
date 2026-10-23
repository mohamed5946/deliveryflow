import 'dart:async';

import 'package:flutter/widgets.dart';

import 'week_calendar.dart';

/// The local midnight that ends the calendar day containing [from]
/// (i.e. the start of the next day). Calendar arithmetic via
/// [WeekCalendar.addDays] (v27.11): a Duration step would land at
/// 23:00/01:00 across a DST transition instead of true midnight.
DateTime nextMidnight(DateTime from) => WeekCalendar.addDays(from, 1);

/// True when [a] and [b] fall on different calendar days.
bool dayChanged(DateTime a, DateTime b) => !WeekCalendar.isSameDay(a, b);

/// Watches for the calendar day rolling over while a screen stays alive
/// (v26): fires [onDayChanged] when the date advances past midnight —
/// detected both by a timer armed at the next midnight boundary (app in
/// the foreground) and on every app resume (app was backgrounded across
/// midnight). [onDayChanged] receives the previously known day and the
/// new current day (both date-only).
class DayRolloverWatcher with WidgetsBindingObserver {
  DayRolloverWatcher({required this.onDayChanged});

  final void Function(DateTime previous, DateTime current) onDayChanged;

  DateTime _knownToday = WeekCalendar.dateOnly(DateTime.now());
  Timer? _timer;
  bool _started = false;

  /// The calendar day this watcher currently treats as "today".
  DateTime get knownToday => _knownToday;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _armMidnightTimer();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) checkNow();
  }

  /// Re-evaluates the current day; fires [onDayChanged] once when it
  /// differs from the last known day. Safe to call at any time.
  void checkNow() {
    final now = WeekCalendar.dateOnly(DateTime.now());
    if (!dayChanged(_knownToday, now)) return;
    final previous = _knownToday;
    _knownToday = now;
    onDayChanged(previous, now);
  }

  void _armMidnightTimer() {
    _timer?.cancel();
    final now = DateTime.now();
    final wait = nextMidnight(now).difference(now);
    // Fire just past the boundary so the clock has ticked over.
    _timer = Timer(wait + const Duration(seconds: 1), () {
      checkNow();
      _armMidnightTimer();
    });
  }
}
