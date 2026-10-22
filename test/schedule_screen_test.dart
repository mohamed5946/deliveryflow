import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/schedule/schedule_screen.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

/// v27.3: schedule-screen day rows — a past day with no orders shows
/// the day-off chip (يوم إجازة), a worked day shows مكتمل + its count,
/// today on a working plan still shows لم يبدأ, and tapping a day row
/// opens that day's orders (/orders?date=…) instead of the editor.
void main() {
  late Directory tmp;
  late DatabaseService db;
  late String workedDayKey;

  Future<void> seedWeek(DateTime anchor, {String? workedKey}) async {
    final start = WeekCalendar.weekStart(anchor);
    final days = WeekCalendar.weekDays(anchor);
    await db.saveSchedule(WorkSchedule(
      id: 'sch_${WeekCalendar.dateKey(start)}',
      weekStartKey: WeekCalendar.dateKey(start),
      weekEndKey: WeekCalendar.dateKey(days.last),
      dailySchedules: [for (final d in days) DailySchedule(dateKey: WeekCalendar.dateKey(d))],
      createdAtMillis: 1,
      updatedAtMillis: 1,
    ));
    if (workedKey != null) {
      await db.upsertOrderRecord(dateKey: workedKey, completedOrders: 3);
    }
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('df_sched_ui_');
    db = DatabaseService();
    await db.init(hivePath: tmp.path);
    final now = DateTime.now();
    // Current week: an all-working plan (view mode on first load).
    await seedWeek(now);
    // Previous week: all working, with one worked day (3 orders).
    final prev = now.subtract(const Duration(days: 7));
    workedDayKey = WeekCalendar.dateKey(WeekCalendar.weekDays(prev)[2]);
    await seedWeek(prev, workedKey: workedDayKey);
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/schedule',
      routes: [
        GoRoute(
          path: '/schedule',
          builder: (_, __) => const ScheduleScreen(),
        ),
        GoRoute(
          path: '/orders',
          builder: (_, state) => Scaffold(
            body: Text('orders-for:${state.uri.queryParameters['date']}'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseServiceProvider.overrideWithValue(db),
          notificationServiceProvider
              .overrideWithValue(NotificationService()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('day-off chip, completed chip, and tap opens day orders',
      (tester) async {
    await pumpScreen(tester);

    // Current week: today (working plan, nothing recorded) is still
    // "not started" — the day-off chip must not claim it yet.
    expect(find.text('لم يبدأ'), findsWidgets);

    // Go to the previous week: every day is in the past.
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The six orderless past days show the day-off chip; the worked
    // day shows مكتمل with its orders count.
    expect(find.text('يوم إجازة'), findsWidgets);
    expect(find.text('مكتمل'), findsOneWidget);
    expect(find.text('3 أوردرات مكتملة'), findsOneWidget);

    // Tapping the worked day's row opens its orders, not the editor.
    await tester.ensureVisible(find.text('مكتمل'));
    await tester.tap(find.text('مكتمل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('orders-for:$workedDayKey'), findsOneWidget);
  });
}
