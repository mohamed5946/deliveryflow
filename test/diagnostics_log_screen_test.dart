import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/logging/app_log_service.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/profile/diagnostics_log_screen.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// v27.2: smoke test for the diagnostics-log viewer — seeded entries
/// render, the category filter narrows the list, a tap expands the
/// technical detail, and the clear button opens its confirm dialog.
/// (The clear itself is covered by the service unit tests; Hive IO
/// does not complete inside the fake-async widget zone.)
void main() {
  late Directory tmp;
  late AppLogService logSvc;
  late DatabaseService db;

  Future<void> waitFor(bool Function() cond) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!cond() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('df_log_ui_');
    // The GlassScaffold aurora background watches settingsProvider,
    // which needs a real DatabaseService — initialized HERE (setUp
    // runs in the real async zone; the widget-test zone would hang).
    db = DatabaseService();
    await db.init(hivePath: tmp.path);
    logSvc = AppLogService();
    await logSvc.init(hivePath: tmp.path);
    logSvc.error(
      AppLogCategory.notifications,
      'schedule FAILED id=9998',
      detail: 'PlatformException: exact_alarms_not_permitted',
    );
    logSvc.info(AppLogCategory.orders, 'Order counted on delivery start');
    await waitFor(() => logSvc.length == 2);
    expect(logSvc.length, 2);
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseServiceProvider.overrideWithValue(db),
          notificationServiceProvider
              .overrideWithValue(NotificationService()),
          appLogServiceProvider.overrideWithValue(logSvc),
        ],
        child: MaterialApp(
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
          home: const DiagnosticsLogScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('renders entries, filters by category, expands detail',
      (tester) async {
    await pumpScreen(tester);

    // Both seeded entries are listed (newest first).
    expect(find.text('schedule FAILED id=9998'), findsOneWidget);
    expect(find.text('Order counted on delivery start'), findsOneWidget);
    // Detail is collapsed until the tile is tapped.
    expect(find.textContaining('exact_alarms_not_permitted'),
        findsNothing);

    await tester.tap(find.text('schedule FAILED id=9998'));
    await tester.pump();
    expect(find.textContaining('exact_alarms_not_permitted'),
        findsOneWidget);

    // Filter to orders only: the notification entry disappears.
    // (widgetWithText: the bare text also matches the tile's own
    // category badge.)
    await tester.tap(find.widgetWithText(ChoiceChip, 'الأوردرات'));
    await tester.pump();
    expect(find.text('Order counted on delivery start'), findsOneWidget);
    expect(find.text('schedule FAILED id=9998'), findsNothing);

    // Back to all, then the clear button opens its confirm dialog.
    await tester.tap(find.widgetWithText(ChoiceChip, 'الكل'));
    await tester.pump();
    expect(find.text('schedule FAILED id=9998'), findsOneWidget);
    await tester.tap(find.text('مسح السجل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('مسح سجل التشخيص؟'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('مسح سجل التشخيص؟'), findsNothing);
  });
}
