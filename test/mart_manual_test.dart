import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/core/tracking/mart_learner.dart';
import 'package:deliveryflow/features/profile/mart_picker_screen.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// v27.9: the manual mart pin (Profile «موقع المارت» → map picker).
/// A hand-placed mart raises UserSettings.martManual, which must
/// (a) persist through Hive + JSON, (b) FREEZE MartLearner — no refine,
/// no replace, no candidate growth, however many observations arrive —
/// and (c) clear completely (mart + flag + candidate) so learning can
/// start over. The widget tests drive the real picker screen through
/// the settings-notifier seam: confirm writes the map-centre coords as
/// a manual mart, clear wipes it.
void main() {
  late Directory tmp;
  late DatabaseService db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('df_martmanual_');
    db = DatabaseService();
    await db.init(hivePath: tmp.path);
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  group('martManual persistence', () {
    test('defaults to false and round-trips through Hive and JSON',
        () async {
      expect(db.settings.martManual, isFalse);

      final s = db.settings;
      applyManualMart(s, 30.00385, 30.98388);
      await db.saveSettings(s);

      final re = db.settings;
      expect(re.martLat, 30.00385);
      expect(re.martLng, 30.98388);
      expect(re.martManual, isTrue);
      expect(re.hasMart, isTrue);

      final json = UserSettings.fromJson(re.toJson());
      expect(json.martLat, 30.00385);
      expect(json.martLng, 30.98388);
      expect(json.martManual, isTrue);
    });
  });

  group('MartLearner manual freeze', () {
    MartLearnerState manualState() => MartLearnerState(
          martLat: 30.0,
          martLng: 30.98,
          martCount: 4,
          manual: true,
        );

    test('nearby observations never refine a manual mart', () {
      var state = manualState();
      for (var i = 0; i < 10; i++) {
        final out = MartLearner.observe(state, 30.0005, 30.9805);
        expect(out.changed, isFalse);
        expect(out.refined, isFalse);
        state = out.state;
      }
      expect(state.martLat, 30.0);
      expect(state.martLng, 30.98);
      expect(state.martCount, 4);
    });

    test('a far cluster never replaces a manual mart', () {
      var state = manualState();
      for (final p in [(30.02, 30.99), (30.0205, 30.99), (30.0202, 30.99)]) {
        final out = MartLearner.observe(state, p.$1, p.$2);
        expect(out.changed, isFalse);
        expect(out.replaced, isFalse);
        expect(out.state.hasCandidate, isFalse);
        state = out.state;
      }
      expect(state.martLat, 30.0);
      expect(state.martCount, 4);
    });
  });

  group('clear resets everything', () {
    test('clear wipes mart + flag + candidate; learning can save again',
        () async {
      final s = db.settings;
      applyManualMart(s, 30.0, 30.98);
      s.martCandidateLat = 30.5;
      s.martCandidateLng = 31.0;
      s.martCandidateCount = 1;
      s.martObservationCount = 7;
      await db.saveSettings(s);
      expect(db.settings.martManual, isTrue);

      await db.saveSettings(applyClearMart(db.settings));
      final cleared = db.settings;
      expect(cleared.hasMart, isFalse);
      expect(cleared.martLat, isNull);
      expect(cleared.martLng, isNull);
      expect(cleared.martManual, isFalse);
      expect(cleared.martObservationCount, 0);
      expect(cleared.martCandidateLat, isNull);
      expect(cleared.martCandidateLng, isNull);
      expect(cleared.martCandidateCount, 0);

      // Learning from scratch: two clustered observations save a mart.
      var state = MartLearnerState(
        martLat: cleared.martLat,
        martLng: cleared.martLng,
        martCount: cleared.martObservationCount,
        candidateLat: cleared.martCandidateLat,
        candidateLng: cleared.martCandidateLng,
        candidateCount: cleared.martCandidateCount,
        manual: cleared.martManual,
      );
      state = MartLearner.observe(state, 30.0, 30.98).state;
      final out = MartLearner.observe(state, 30.0005, 30.98);
      expect(out.learned, isTrue);
      expect(out.state.hasMart, isTrue);
    });
  });

  group('picker saves through the settings-notifier seam', () {
    // The picker's confirm/clear buttons call
    // settingsProvider.notifier.update(applyManualMart/applyClearMart);
    // drive that exact seam here in a real-async zone (an awaited Hive
    // put inside a widget test's fake-async zone never completes — the
    // codebase's widget tests avoid in-test Hive writes).
    test('confirm persists the pinned coords with the manual flag',
        () async {
      final notifier = SettingsNotifier(db, NotificationService());
      await notifier.update((s) => applyManualMart(s, 30.00385, 30.98388));
      expect(notifier.state.martManual, isTrue);
      expect(db.settings.martLat, 30.00385);
      expect(db.settings.martLng, 30.98388);
      expect(db.settings.martManual, isTrue);
    });

    test('clear through the notifier wipes mart + flag + candidate',
        () async {
      final notifier = SettingsNotifier(db, NotificationService());
      await notifier.update((s) => applyManualMart(s, 30.0, 30.98)
        ..martCandidateLat = 30.5
        ..martCandidateCount = 1);
      await notifier.update(applyClearMart);
      expect(db.settings.hasMart, isFalse);
      expect(db.settings.martManual, isFalse);
      expect(db.settings.martCandidateLat, isNull);
      expect(db.settings.martCandidateCount, 0);
    });
  });

  group('MartPickerScreen (widget)', () {
    Future<void> pumpPicker(WidgetTester tester) async {
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
            home: const MartPickerScreen(),
          ),
        ),
      );
      // Timed pumps, not pumpAndSettle: the aurora background animates
      // continuously, so the tree never "settles" (same pattern as the
      // other screen widget tests).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets(
        'no mart yet: hint + confirm render over the fallback centre; '
        'no clear button', (tester) async {
      await pumpPicker(tester);
      expect(find.text('حرّك الخريطة لحد ما الدبوس يبقى على المارت'),
          findsOneWidget);
      expect(find.text('تأكيد موقع المارت'), findsOneWidget);
      expect(find.text('استخدام موقعي الحالي'), findsOneWidget);
      expect(find.text('مسح موقع المارت'), findsNothing);
      // The coordinate readout IS the point confirm will save (no GPS
      // in the harness, no saved mart → fallback city view).
      expect(find.text('30.03000, 31.02000'), findsOneWidget);
    });

    testWidgets('a learned mart shows its observation count + clear',
        (tester) async {
      final s = db.settings
        ..martLat = 30.0
        ..martLng = 30.98
        ..martObservationCount = 5;
      // runAsync: an awaited Hive put inside the fake test zone never
      // completes (same seam as order_detail_edit_test).
      await tester.runAsync(() => db.saveSettings(s));

      await pumpPicker(tester);
      expect(find.text('اتعلم من 5 مشاهدة'), findsOneWidget);
      expect(find.text('مسح موقع المارت'), findsOneWidget);
      // The map opened on the saved mart.
      expect(find.text('30.00000, 30.98000'), findsOneWidget);
    });
  });
}
