import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
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

/// v27.9 regression: the order EDIT sheet prefilled its km fields from
/// the MANUAL km fields (entry.kmOut/kmBack) — which stay 0 whenever
/// the app measured the trip itself — so a GPS-measured order showed
/// 0.0 in the sheet. Worse, one combined `kmChanged` zeroed BOTH legs'
/// GPS km on any edit: fixing only the return distance wiped the GPS
/// outgoing distance to 0 (Mohamed's field report: «لو ما كتبتهاش
/// بتبقى صفر» — "if I don't retype it, it becomes zero").
///
/// The fix: prefill from effectiveKmOut/effectiveKmBack and resolve
/// each leg independently via resolveLegKmEdit — unchanged or emptied
/// field → null/null (leg preserved, GPS included); changed field →
/// that leg only goes manual; garbage/negative → invalid.
void main() {
  late Directory tmp;
  late DatabaseService db;
  late String dateKey;
  late String entryId;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('df_editkm_');
    db = DatabaseService();
    await db.init(hivePath: tmp.path);

    final now = DateTime.now();
    dateKey = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    // A GPS-measured order: outgoing measured 4 km by GPS (manual
    // kmOut stays 0), return not measured at all.
    final e = await db.addOrderEntry(
      dateKey: dateKey,
      timestampMillis: now.millisecondsSinceEpoch,
    );
    entryId = e.id;
    await db.updateOrderEntry(
      dateKey: dateKey,
      entryId: e.id,
      status: 3,
      gpsKmOut: 4.0,
    );

    // Same foreground-task mock as order_detail_edit_test.
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

  OrderEntry entry() => db
      .orderRecord(dateKey)!
      .entries
      .firstWhere((e) => e.id == entryId);

  group('resolveLegKmEdit', () {
    test('an untouched field (exact effective value) keeps the leg', () {
      final edit = resolveLegKmEdit('4.0', 4.0);
      expect(edit.invalid, isFalse);
      expect(edit.km, isNull);
      expect(edit.gpsKm, isNull);
    });

    test('a long-decimal GPS value round-trips as unchanged', () {
      const gps = 3.67804675329121;
      final edit = resolveLegKmEdit(gps.toString(), gps);
      expect(edit.invalid, isFalse);
      expect(edit.km, isNull);
      expect(edit.gpsKm, isNull);
    });

    test('an emptied field keeps the calculated distance', () {
      for (final raw in ['', '   ']) {
        final edit = resolveLegKmEdit(raw, 4.0);
        expect(edit.invalid, isFalse, reason: 'raw=$raw');
        expect(edit.km, isNull);
        expect(edit.gpsKm, isNull);
      }
    });

    test('a changed value makes only that leg manual', () {
      final edit = resolveLegKmEdit('2.5', 0);
      expect(edit.invalid, isFalse);
      expect(edit.km, 2.5);
      expect(edit.gpsKm, 0);
    });

    test('comma decimal separator is accepted', () {
      final edit = resolveLegKmEdit('2,5', 0);
      expect(edit.invalid, isFalse);
      expect(edit.km, 2.5);
    });

    test('garbage and negatives are invalid', () {
      for (final raw in ['abc', '-1', '4.0.1']) {
        final edit = resolveLegKmEdit(raw, 4.0);
        expect(edit.invalid, isTrue, reason: 'raw=$raw');
      }
    });
  });

  group('sheet save mapping at the DB level', () {
    test('editing ONLY the return km preserves the GPS outgoing km',
        () async {
      // Exactly what the sheet passes after the fix: outgoing
      // unchanged (null/null), return changed to 2.5.
      final outEdit =
          resolveLegKmEdit(entry().effectiveKmOut.toString(), 4.0);
      final backEdit = resolveLegKmEdit('2.5', entry().effectiveKmBack);
      await db.updateOrderEntry(
        dateKey: dateKey,
        entryId: entryId,
        kmOut: outEdit.km,
        kmBack: backEdit.km,
        gpsKmOut: outEdit.gpsKm,
        gpsKmBack: backEdit.gpsKm,
      );

      final e = entry();
      expect(e.gpsKmOut, 4.0); // GPS distance NOT wiped
      expect(e.effectiveKmOut, 4.0);
      expect(e.isManualOut, isFalse);
      expect(e.kmBack, 2.5);
      expect(e.gpsKmBack, 0);
      expect(e.isManualBack, isTrue); // يدوي on the return leg only
    });

    test('saving with both fields emptied changes nothing', () async {
      await db.updateOrderEntry(
        dateKey: dateKey,
        entryId: entryId,
        kmBack: 1.5, // pre-existing manual return value
      );
      final before = entry();
      final outEdit = resolveLegKmEdit('', before.effectiveKmOut);
      final backEdit = resolveLegKmEdit('', before.effectiveKmBack);
      await db.updateOrderEntry(
        dateKey: dateKey,
        entryId: entryId,
        kmOut: outEdit.km,
        kmBack: backEdit.km,
        gpsKmOut: outEdit.gpsKm,
        gpsKmBack: backEdit.gpsKm,
      );
      final after = entry();
      expect(after.gpsKmOut, 4.0);
      expect(after.kmBack, 1.5);
      expect(after.effectiveKmTotal, before.effectiveKmTotal);
    });

    test('editing the outgoing value leaves the return leg untouched',
        () async {
      await db.updateOrderEntry(
        dateKey: dateKey,
        entryId: entryId,
        kmBack: 1.5,
      );
      await db.updateOrderEntry(
        dateKey: dateKey,
        entryId: entryId,
        kmOut: 5.25,
        gpsKmOut: 0,
      );
      final e = entry();
      expect(e.kmOut, 5.25);
      expect(e.gpsKmOut, 0);
      expect(e.isManualOut, isTrue);
      expect(e.kmBack, 1.5); // untouched
      expect(e.isManualBack, isTrue);
    });
  });

  group('edit sheet (widget)', () {
    testWidgets('km fields are prefilled with the EFFECTIVE distances',
        (tester) async {
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

      await tester.tap(find.byIcon(Icons.edit_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The bug showed 0.0 here (the manual field); the fix shows the
      // GPS-measured 4.0 the rest of the screen displays.
      final outField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.labelText ?? '').startsWith('رايح'));
      expect(outField, findsOneWidget);
      expect(tester.widget<TextField>(outField).controller?.text, '4.0');

      // Return leg was never measured: effective is 0 either way.
      final backField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.labelText ?? '').startsWith('راجع'));
      expect(backField, findsOneWidget);
      expect(tester.widget<TextField>(backField).controller?.text, '0.0');

      // NOTE: the sheet's save is not driven end-to-end here — an
      // awaited Hive put inside the fake-async zone never completes
      // (see order_detail_edit_test). The save's exact argument
      // mapping is proven at the DB level above.
    });
  });
}
