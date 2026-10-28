import 'dart:io';

import 'package:deliveryflow/app/router.dart';
import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/daily_orders/order_detail_screen.dart';
import 'package:deliveryflow/features/daily_orders/order_entry_screen.dart';
import 'package:deliveryflow/features/dashboard/dashboard_screen.dart';
import 'package:deliveryflow/features/profile/profile_screen.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Pumps [screen] inside a minimal localized app with real (temp-dir)
/// Hive-backed providers.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required DatabaseService db,
  ThemeMode themeMode = ThemeMode.system,
  Locale locale = const Locale('ar'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        notificationServiceProvider
            .overrideWithValue(NotificationService()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        locale: locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: screen,
      ),
    ),
  );
  // Settle manually instead of pumpAndSettle: indeterminate progress
  // indicators (e.g. the loading spinner) never settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late Directory tmp;
  late DatabaseService db;

  Directory syncTemp(String prefix) {
    final d = Directory(
        '/tmp/${prefix}_${DateTime.now().microsecondsSinceEpoch}');
    d.createSync(recursive: true);
    return d;
  }

  setUp(() async {
    // NOTE: setUp runs in the real async zone. All async Hive work must
    // happen here (or inside tester.runAsync): testWidgets bodies run in a
    // FakeAsync zone where Hive's internal timers never fire.
    tmp = syncTemp('df_widget');
    db = DatabaseService();
    await db.init(hivePath: tmp.path);
  });

  tearDown(() async {
    await Hive.close();
    tmp.deleteSync(recursive: true);
  });

  group('Dashboard', () {
    testWidgets('renders greeting, stats and quick actions (RTL)',
        (tester) async {
      final now = DateTime.now();
      final key =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await tester.runAsync(
          () => db.upsertOrderRecord(dateKey: key, completedOrders: 5));
      await pumpScreen(tester, const DashboardScreen(), db: db);
      expect(find.textContaining('مرحباً'), findsOneWidget);
      // Quick actions: add order + week details.
      expect(find.text('أضف أوردر'), findsOneWidget);
      expect(find.text('عرض تفاصيل الأسبوع'), findsOneWidget);
      // RTL directionality for Arabic.
      final dir = tester.widget<Directionality>(
          find.byType(Directionality).first);
      expect(dir.textDirection, TextDirection.rtl);
    });

    testWidgets('shows empty state when no records exist', (tester) async {
      await pumpScreen(tester, const DashboardScreen(), db: db);
      expect(find.text('لا توجد سجلات بعد'), findsOneWidget);
    });

    testWidgets('shows weekly totals after recording data', (tester) async {
      final now = DateTime.now();
      final key =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await tester.runAsync(
          () => db.upsertOrderRecord(dateKey: key, completedOrders: 11));
      await pumpScreen(tester, const DashboardScreen(), db: db);
      // Weekly orders tile shows 11.
      expect(find.text('11'), findsWidgets);
    });
  });

  group('Themes', () {
    testWidgets('dark theme uses dark brightness', (tester) async {
      await pumpScreen(tester, const DashboardScreen(),
          db: db, themeMode: ThemeMode.dark);
      final ctx = tester.element(find.byType(Scaffold));
      expect(Theme.of(ctx).brightness, Brightness.dark);
    });

    testWidgets('light theme uses light brightness', (tester) async {
      await pumpScreen(tester, const DashboardScreen(),
          db: db, themeMode: ThemeMode.light);
      final ctx = tester.element(find.byType(Scaffold));
      expect(Theme.of(ctx).brightness, Brightness.light);
    });
  });

  group('LTR layout', () {
    testWidgets('English renders left-to-right', (tester) async {
      await pumpScreen(tester, const DashboardScreen(),
          db: db, locale: const Locale('en'));
      final dir = tester.widget<Directionality>(
          find.byType(Directionality).first);
      expect(dir.textDirection, TextDirection.ltr);
      // Empty-state action button only (quick actions hidden when empty).
      expect(find.text('Record today\'s orders'), findsOneWidget);
    });
  });

  group('Order entry', () {
    testWidgets('shows empty state and add button', (tester) async {
      await pumpScreen(tester, const OrderEntryScreen(), db: db);
      expect(find.text('أضف أوردر'), findsOneWidget);
      expect(
          find.text('لا توجد أوردرات مسجلة — أضف أول أوردر'),
          findsOneWidget);
    });

    // v27: the standalone bulk-count button is gone — «أضف أوردر» now
    // opens a choice sheet, and «تسجيل العدد فقط» leads to the bulk
    // dialog. (Only the choice + dialog opening are driven here; the
    // detailed flow's async path is the skipped test below.)
    testWidgets('add button opens the choice sheet; count option opens '
        'the bulk dialog', (tester) async {
      await pumpScreen(tester, const OrderEntryScreen(), db: db);
      // No standalone count button anymore.
      expect(find.text('تسجيل العدد فقط'), findsNothing);
      await tester.tap(find.text('أضف أوردر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('أوردر بتفاصيل'), findsOneWidget);
      expect(find.text('تسجيل العدد فقط'), findsOneWidget);
      await tester.tap(find.text('تسجيل العدد فقط'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('عدد أوردرات اليوم'), findsOneWidget);
    });

    // v23: the old "add order sheet shows km fields" test is stale — the
    // add flow changed (create a pending order instantly, no km questions)
    // and driving the full async path (notification refresh + navigation)
    // hangs in CI's widget-test environment. Skipped until the test gets
    // a mocked notification service.
    testWidgets('add order creates entry and opens detail screen',
        skip: true, (tester) async {
      await pumpScreen(tester, const OrderEntryScreen(), db: db);
      await tester.tap(find.text('أضف أوردر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Current flow: tapping creates a pending order instantly (no km
      // questions — distances come from GPS tracking) and opens the
      // detail screen so the courier can start the delivery.
      expect(find.byType(OrderDetailScreen, skipOffstage: false),
          findsOneWidget);
    });
  });

  group('Settings', () {
    testWidgets('theme radio changes persisted theme', (tester) async {
      // Tall viewport: the theme rows sit below the profile header cards.
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pumpScreen(tester, const ProfileScreen(), db: db);
      // v27.26: theme rows live in the appearance detail screen.
      await tester.tap(find.text('المظهر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        await tester.tap(find.text('الوضع الداكن'));
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (db.settings.themeMode == 2) break;
        }
      });
      expect(db.settings.themeMode, 2);
    });

    testWidgets('language switch is offered', (tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pumpScreen(tester, const ProfileScreen(), db: db);
      // v27.26: language rows live in the language detail screen.
      await tester.ensureVisible(find.text('اللغة'));
      await tester.pump();
      await tester.tap(find.text('اللغة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('العربية', skipOffstage: false), findsOneWidget);
      expect(find.text('English', skipOffstage: false), findsOneWidget);
    });

    testWidgets('notification toggles exist', (tester) async {
      // Tall viewport so the whole settings list is laid out.
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pumpScreen(tester, const ProfileScreen(), db: db);
      // v27.26: notification rows live in the notifications detail screen.
      await tester.tap(find.text('الإشعارات'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('تفعيل الإشعارات'), findsOneWidget);
      expect(find.text('تذكير الأوردرات اليومي'), findsOneWidget);
    });
  });

  // v27 regression: the GoRouter used to be rebuilt on every settings
  // change (buildRouter called inside build), resetting the app to the
  // splash screen. The router must be one instance for the app's life.
  test('router is created once and survives settings changes', () {
    final container = ProviderContainer(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        notificationServiceProvider
            .overrideWithValue(NotificationService()),
      ],
    );
    addTearDown(container.dispose);
    final first = container.read(routerProvider);
    container
        .read(settingsProvider.notifier)
        .update((s) => s..themeMode = 2);
    final second = container.read(routerProvider);
    expect(identical(first, second), isTrue);
  });
}
