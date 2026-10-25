import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/date_time/time_format.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/dashboard/day_hours_section.dart';
import 'package:deliveryflow/features/schedule/schedule_screen.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

/// v27.12: confirmation-dialog flow for block edits, and schedule
/// view-mode times. No block change happens without an explicit Yes:
/// dialog appears on tap, Yes applies it, No (or dismiss) leaves the
/// schedule unchanged.
void main() {
  late Directory tmp;
  late DatabaseService db;

  DailySchedule workDay({int start = 11 * 60, int end = 22 * 60}) =>
      DailySchedule(
        dateKey: '2026-10-25',
        startMinutes: start,
        endMinutes: end,
        breakDurationMinutes: 0,
      );

  Future<void> pumpSection(
    WidgetTester tester, {
    DailySchedule? day,
    DateTime? now,
    ValueChanged<int>? onToggle,
    VoidCallback? onAdd,
    VoidCallback? onRemove,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: DayHoursSection(
              day: day,
              selectedDay: DateTime(2026, 10, 25),
              now: now ?? DateTime(2026, 10, 25, 13, 30),
              timeFormat: TimeFormatMode.h24,
              arabic: true,
              onToggleBreak: onToggle ?? (_) {},
              onAddHour: onAdd ?? () {},
              onRemoveHour: onRemove ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('confirmation dialogs', () {
    testWidgets('work block tap asks delete; Yes toggles, No does not',
        (tester) async {
      var toggled = <int>[];
      await pumpSection(tester,
          day: workDay(), onToggle: (s) => toggled.add(s));

      // 11 blocks for 11:00-22:00, labelled by start hour.
      expect(find.text('11:00'), findsOneWidget);
      expect(find.text('21:00'), findsOneWidget);
      expect(find.text('22:00'), findsNothing);

      await tester.tap(find.text('14:00'));
      await tester.pump();
      expect(find.text('هل أنت متأكد من حذف البلوكاية؟'), findsOneWidget);

      await tester.tap(find.text('لا'));
      await tester.pumpAndSettle();
      expect(toggled, isEmpty);
      expect(find.text('هل أنت متأكد من حذف البلوكاية؟'), findsNothing);

      // Tap again, this time Yes.
      await tester.tap(find.text('14:00'));
      await tester.pump();
      await tester.tap(find.text('نعم'));
      await tester.pumpAndSettle();
      expect(toggled, [840]);
    });

    testWidgets('break block tap asks add (restore); No leaves it',
        (tester) async {
      var toggled = <int>[];
      final day = workDay()..breakHourStarts = [840];
      await pumpSection(tester, day: day, onToggle: (s) => toggled.add(s));

      expect(find.text('استراحة'), findsWidgets);
      await tester.tap(find.text('14:00'));
      await tester.pump();
      expect(find.text('هل أنت متأكد من إضافة البلوكاية؟'), findsOneWidget);
      await tester.tap(find.text('لا'));
      await tester.pumpAndSettle();
      expect(toggled, isEmpty);
    });

    testWidgets('+ hour asks add, - hour asks delete; Yes fires each',
        (tester) async {
      var added = 0;
      var removed = 0;
      await pumpSection(tester,
          day: workDay(),
          onAdd: () => added++,
          onRemove: () => removed++);

      await tester.ensureVisible(find.text('+ ساعة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ ساعة'));
      await tester.pump();
      expect(find.text('هل أنت متأكد من إضافة البلوكاية؟'), findsOneWidget);
      await tester.tap(find.text('نعم'));
      await tester.pumpAndSettle();
      expect(added, 1);

      await tester.ensureVisible(find.text('- ساعة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('- ساعة'));
      await tester.pump();
      expect(find.text('هل أنت متأكد من حذف البلوكاية؟'), findsOneWidget);
      await tester.tap(find.text('لا'));
      await tester.pumpAndSettle();
      expect(removed, 0);
    });

    testWidgets('day off shows Day off only; no schedule is neutral',
        (tester) async {
      await pumpSection(tester,
          day: workDay()..isWorkingDay = false);
      expect(find.text('يوم إجازة'), findsOneWidget);
      expect(find.text('11:00'), findsNothing);

      await pumpSection(tester, day: null);
      expect(find.text('مفيش جدول لليوم ده'), findsOneWidget);
      expect(find.text('11:00'), findsNothing);
    });
  });

  group('schedule view-mode times', () {
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('df_day_hours_ui_');
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
      // Current week with one working day 8:00-11:00 on a past day so
      // view mode (not the fresh-week editor) renders.
      final anchor = DateTime.now();
      final start = WeekCalendar.weekStart(anchor);
      final days = WeekCalendar.weekDays(anchor)
          .map((d) => DailySchedule(
                dateKey: WeekCalendar.dateKey(d),
                startMinutes: 8 * 60,
                endMinutes: 11 * 60,
                breakDurationMinutes: 0,
              ))
          .toList();
      await db.saveSchedule(WorkSchedule(
        id: 'sch_${WeekCalendar.dateKey(start)}',
        weekStartKey: WeekCalendar.dateKey(start),
        weekEndKey: WeekCalendar.dateKey(WeekCalendar.weekDays(anchor).last),
        dailySchedules: days,
        createdAtMillis: 1,
        updatedAtMillis: 1,
      ));
      // 24-hour format so the expected text is deterministic.
      final settings = db.settings..timeFormat = 1;
      await db.saveSettings(settings);
    });

    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    testWidgets('view mode shows start-end times opposite the day name',
        (tester) async {
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
      // Every working row shows its times in view mode (7 rows).
      expect(find.text('08:00 - 11:00'), findsWidgets);
    });
  });
}
