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

/// v27.13: swipe actions + Assign picker + protection, and schedule
/// view-mode times. Tap on a block does nothing (tap-vs-swipe
/// resolution); mutations go through swipe actions or Assign, and no
/// change happens without an explicit Yes in the confirmation dialog.
/// A protected block can neither be deleted nor broken.
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
    ValueChanged<int>? onAssign,
    Set<int>? protected,
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
              onAssignHour: onAssign ?? (_) {},
              protectedBlockStarts: protected ?? const {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder blockKey(int start) =>
      find.byKey(ValueKey('day-hour-block-2026-10-25-$start'));
  Finder deleteKey(int start) =>
      find.byKey(ValueKey('block-action-delete-$start'));
  Finder breakKey(int start) =>
      find.byKey(ValueKey('block-action-break-$start'));

  group('tap vs swipe', () {
    testWidgets('tap on a block does nothing (no tap-toggle any more)',
        (tester) async {
      var toggled = <int>[];
      await pumpSection(tester,
          day: workDay(), onToggle: (s) => toggled.add(s));

      // 11 blocks for 11:00-22:00, labelled by start hour.
      expect(find.text('11:00'), findsOneWidget);
      expect(find.text('21:00'), findsOneWidget);
      expect(find.text('22:00'), findsNothing);

      await tester.tap(find.text('14:00'));
      await tester.pumpAndSettle();
      expect(toggled, isEmpty);
      expect(find.text('هل أنت متأكد من حذف البلوكاية؟'), findsNothing);
    });

    testWidgets('swipe alone changes nothing; revealed Delete + Yes toggles',
        (tester) async {
      var toggled = <int>[];
      await pumpSection(tester,
          day: workDay(), onToggle: (s) => toggled.add(s));

      await tester.timedDrag(blockKey(840), const Offset(-150, 0),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      // Swiping only revealed the action: no dialog, no callback.
      expect(toggled, isEmpty);
      expect(find.text('هل أنت متأكد من حذف البلوكاية؟'), findsNothing);

      await tester.tap(deleteKey(840));
      await tester.pump();
      expect(find.text('هل أنت متأكد من حذف البلوكاية؟'), findsOneWidget);
      await tester.tap(find.text('نعم'));
      await tester.pumpAndSettle();
      expect(toggled, [840]);
    });

    testWidgets('swipe left Delete + No leaves the block unchanged',
        (tester) async {
      var toggled = <int>[];
      await pumpSection(tester,
          day: workDay(), onToggle: (s) => toggled.add(s));

      await tester.timedDrag(blockKey(840), const Offset(-150, 0),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(deleteKey(840));
      await tester.pump();
      await tester.tap(find.text('لا'));
      await tester.pumpAndSettle();
      expect(toggled, isEmpty);
    });

    testWidgets('swipe right Break on a work block asks delete; Yes toggles',
        (tester) async {
      var toggled = <int>[];
      await pumpSection(tester,
          day: workDay(), onToggle: (s) => toggled.add(s));

      await tester.timedDrag(blockKey(840), const Offset(150, 0),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(breakKey(840));
      await tester.pump();
      expect(find.text('هل أنت متأكد من حذف البلوكاية؟'), findsOneWidget);
      await tester.tap(find.text('نعم'));
      await tester.pumpAndSettle();
      expect(toggled, [840]);
    });

    testWidgets('swipe right Restore on a break block asks add; No leaves it',
        (tester) async {
      var toggled = <int>[];
      final day = workDay()..breakHourStarts = [840];
      await pumpSection(tester, day: day, onToggle: (s) => toggled.add(s));

      expect(find.text('استراحة'), findsWidgets);
      await tester.timedDrag(blockKey(840), const Offset(150, 0),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(breakKey(840));
      await tester.pump();
      expect(find.text('هل أنت متأكد من إضافة البلوكاية؟'), findsOneWidget);
      await tester.tap(find.text('لا'));
      await tester.pumpAndSettle();
      expect(toggled, isEmpty);
    });

    testWidgets('+1/-1 buttons are gone; Assign button is present',
        (tester) async {
      await pumpSection(tester, day: workDay());
      expect(find.text('+ ساعة'), findsNothing);
      expect(find.text('- ساعة'), findsNothing);
      expect(find.text('تسجيل'), findsOneWidget);
    });
  });

  group('Assign button', () {
    testWidgets('picker excludes existing hours (8 AM example) + Yes assigns',
        (tester) async {
      var assigned = <int>[];
      await pumpSection(tester,
          day: workDay(start: 8 * 60, end: 11 * 60),
          onAssign: (h) => assigned.add(h));

      await tester.tap(find.text('تسجيل'));
      await tester.pumpAndSettle();
      expect(find.text('اختر ساعة لإضافتها'), findsOneWidget);
      // Existing blocks 8, 9, 10 are not offered; 11 is (the picker
      // list is lazily built, so scroll until 11 appears to prove it).
      expect(find.byKey(const ValueKey('assign-hour-8')), findsNothing);
      expect(find.byKey(const ValueKey('assign-hour-9')), findsNothing);
      expect(find.byKey(const ValueKey('assign-hour-10')), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('assign-hour-11')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assign-hour-11')));
      await tester.pump();
      expect(find.text('هل أنت متأكد من إضافة البلوكاية؟'), findsOneWidget);
      await tester.tap(find.text('نعم'));
      await tester.pumpAndSettle();
      expect(assigned, [11]);
    });

    testWidgets('Assign picker + No assigns nothing', (tester) async {
      var assigned = <int>[];
      await pumpSection(tester,
          day: workDay(start: 8 * 60, end: 11 * 60),
          onAssign: (h) => assigned.add(h));

      await tester.tap(find.text('تسجيل'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assign-hour-14')));
      await tester.pump();
      await tester.tap(find.text('لا'));
      await tester.pumpAndSettle();
      expect(assigned, isEmpty);
    });

    testWidgets('day off: Assign offers all hours and creates a shift',
        (tester) async {
      var assigned = <int>[];
      await pumpSection(tester,
          day: workDay()..isWorkingDay = false,
          onAssign: (h) => assigned.add(h));
      expect(find.text('يوم إجازة'), findsOneWidget);

      await tester.tap(find.text('تسجيل'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assign-hour-8')));
      await tester.pump();
      await tester.tap(find.text('نعم'));
      await tester.pumpAndSettle();
      expect(assigned, [8]);
    });

    testWidgets('no schedule: Assign is shown and picks an hour',
        (tester) async {
      var assigned = <int>[];
      await pumpSection(tester, day: null, onAssign: (h) => assigned.add(h));
      expect(find.text('مفيش جدول لليوم ده'), findsOneWidget);

      await tester.tap(find.text('تسجيل'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assign-hour-8')));
      await tester.pump();
      await tester.tap(find.text('نعم'));
      await tester.pumpAndSettle();
      expect(assigned, [8]);
    });
  });

  group('v27.14 at-rest clean + progressive reveal', () {
    testWidgets('at rest NO action widget exists for any block',
        (tester) async {
      await pumpSection(tester, day: workDay());
      // The v27.13 bug: both actions were always rendered behind the
      // translucent block, so these keys existed (and peeked through)
      // at rest. At rest they must not exist at all.
      for (final start in [660, 840, 1260]) {
        expect(deleteKey(start), findsNothing);
        expect(breakKey(start), findsNothing);
      }
    });

    testWidgets('drag left reveals ONLY Delete, growing with drag distance',
        (tester) async {
      await pumpSection(tester, day: workDay());
      final gesture =
          await tester.startGesture(tester.getCenter(blockKey(840)));
      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump();
      expect(deleteKey(840), findsOneWidget);
      expect(breakKey(840), findsNothing);
      final small = tester.getSize(deleteKey(840)).width;
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      expect(deleteKey(840), findsOneWidget);
      expect(breakKey(840), findsNothing);
      final big = tester.getSize(deleteKey(840)).width;
      expect(big, greaterThan(small));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('drag right reveals ONLY Break, never Delete',
        (tester) async {
      await pumpSection(tester, day: workDay());
      final gesture =
          await tester.startGesture(tester.getCenter(blockKey(840)));
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(breakKey(840), findsOneWidget);
      expect(deleteKey(840), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('drag right on a break block reveals ONLY Restore',
        (tester) async {
      final day = workDay()..breakHourStarts = [840];
      await pumpSection(tester, day: day);
      final gesture =
          await tester.startGesture(tester.getCenter(blockKey(840)));
      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      // A break block has no Delete: a left drag reveals nothing.
      expect(deleteKey(840), findsNothing);
      expect(breakKey(840), findsNothing);
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(breakKey(840), findsOneWidget);
      expect(deleteKey(840), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('release below threshold snaps fully back and hides action',
        (tester) async {
      await pumpSection(tester, day: workDay());
      await tester.timedDrag(blockKey(840), const Offset(-30, 0),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(deleteKey(840), findsNothing);
      expect(breakKey(840), findsNothing);
      // The block is back at rest: a tap still does nothing.
      await tester.tap(find.text('14:00'));
      await tester.pumpAndSettle();
      expect(find.text('هل أنت متأكد من حذف البلوكاية؟'), findsNothing);
    });

    testWidgets('protected block drag reveals no action on either side',
        (tester) async {
      await pumpSection(tester,
          day: workDay(), protected: {840});
      final gesture =
          await tester.startGesture(tester.getCenter(blockKey(840)));
      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(deleteKey(840), findsNothing);
      expect(breakKey(840), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('protection', () {
    testWidgets('protected block shows a lock; tap explains, changes nothing',
        (tester) async {
      var toggled = <int>[];
      await pumpSection(tester,
          day: workDay(), onToggle: (s) => toggled.add(s), protected: {840});
      expect(find.text('محمي'), findsOneWidget);

      await tester.tap(find.text('14:00'));
      await tester.pump();
      expect(find.text('لا يمكن حذف هذه البلوكاية لأنها تحتوي على أوردرات'),
          findsOneWidget);
      await tester.tap(find.text('حسناً'));
      await tester.pumpAndSettle();
      expect(toggled, isEmpty);
    });

    testWidgets('protected block cannot be swiped open or toggled',
        (tester) async {
      var toggled = <int>[];
      await pumpSection(tester,
          day: workDay(), onToggle: (s) => toggled.add(s), protected: {840});

      // Drags in both directions: no dialog, no callback — the block
      // never opens, so neither swipe action can fire.
      await tester.timedDrag(blockKey(840), const Offset(-150, 0),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.timedDrag(blockKey(840), const Offset(150, 0),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(toggled, isEmpty);
      expect(find.text('هل أنت متأكد من حذف البلوكاية؟'), findsNothing);
      expect(find.text('هل أنت متأكد من إضافة البلوكاية؟'), findsNothing);
    });

    testWidgets('unprotected block next to a protected one still toggles',
        (tester) async {
      var toggled = <int>[];
      await pumpSection(tester,
          day: workDay(), onToggle: (s) => toggled.add(s), protected: {840});

      await tester.timedDrag(blockKey(900), const Offset(-150, 0),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(deleteKey(900));
      await tester.pump();
      await tester.tap(find.text('نعم'));
      await tester.pumpAndSettle();
      expect(toggled, [900]);
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
