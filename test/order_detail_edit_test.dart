import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/daily_orders/order_detail_screen.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// v27.6 regression: the order-detail AppBar edit (pencil) button
/// shipped DEAD in every release up to v27.5 — it was built as
/// `Pressable(scaleOnly: true, onTap: …)`, and by Pressable's own
/// contract scaleOnly means "animation only, onTap is never invoked"
/// (a mode meant for nesting inside another tap handler — there was
/// none). It animated on press but never opened the edit sheet.
/// These tests tap the real button on the real screen and require
/// the sheet to open, with its v27.6 manual-bonus field present and
/// prefilled from the entry.
void main() {
  late Directory tmp;
  late DatabaseService db;
  late String dateKey;
  late String entryId;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('df_editbtn_');
    db = DatabaseService();
    await db.init(hivePath: tmp.path);

    final now = DateTime.now();
    dateKey = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final e = await db.addOrderEntry(
      dateKey: dateKey,
      timestampMillis: now.millisecondsSinceEpoch,
      kmOut: 6,
      kmBack: 5,
    );
    entryId = e.id;
    await db.updateOrderEntry(
        dateKey: dateKey, entryId: e.id, status: 3);

    // _recoverTracking probes the foreground-task plugin from
    // initState; answer false (no service running) deterministically.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      (call) async => false,
    );
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  Future<void> pumpDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseServiceProvider.overrideWithValue(db),
          notificationServiceProvider
              .overrideWithValue(NotificationService()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: OrderDetailScreen(dateKey: dateKey, entryId: entryId),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('edit (pencil) button opens the edit sheet',
      (tester) async {
    await pumpDetail(tester);

    final editButton = find.byIcon(Icons.edit_rounded);
    expect(editButton, findsOneWidget);

    await tester.tap(editButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The sheet is up: its title and the v27.6 manual-bonus field.
    expect(find.text('تعديل الأوردر'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byWidgetPredicate((w) =>
            w is TextField && w.decoration?.labelText == 'بونص إضافي'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('edit sheet bonus field is prefilled from the entry',
      (tester) async {
    // Give the seeded order a manual bonus first. The write must run
    // in a real-async zone — an awaited Hive put inside the fake
    // test zone never completes (timers/IO are frozen there).
    await tester.runAsync(() => db.updateOrderEntry(
        dateKey: dateKey, entryId: entryId, manualBonusEgp: 15));

    await pumpDetail(tester);

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final bonusField = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'بونص إضافي');
    expect(bonusField, findsOneWidget);
    final widget = tester.widget<TextField>(bonusField);
    expect(widget.controller?.text, '15');

    // NOTE: the sheet's save is intentionally not driven end-to-end
    // here — its persistence seam is the same
    // `updateOrderEntry(manualBonusEgp:)` call the breakdown-row
    // editor uses, proven at the DB level in manual_bonus_test.dart;
    // driving the modal save chain to a Hive put inside a widget
    // test deadlocks on the fake-async zone (the codebase's widget
    // tests avoid in-test Hive writes for the same reason).
  });
}
