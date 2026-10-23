import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/developer/developer_mode.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/profile/profile_screen.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// v27.4: Developer Mode gate — the diagnostics tools (notification
/// tests, status card, diagnostics log) stay hidden until the
/// password unlocks them; the unlock persists in settings.
void main() {
  group('DeveloperMode.accepts', () {
    test('the stored password unlocks; anything else does not', () {
      expect(DeveloperMode.accepts(DeveloperMode.password), isTrue);
      expect(DeveloperMode.accepts('0000'), isFalse);
      expect(DeveloperMode.accepts(''), isFalse);
    });

    test('surrounding whitespace is ignored', () {
      expect(DeveloperMode.accepts('  ${DeveloperMode.password} '), isTrue);
    });
  });

  group('persistence', () {
    late Directory tmp;
    late DatabaseService db;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('df_devmode_');
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
    });

    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('locked by default; unlock survives a settings round-trip', () async {
      expect(db.settings.developerModeUnlocked, isFalse);
      final s = db.settings..developerModeUnlocked = true;
      await db.saveSettings(s);
      expect(db.settings.developerModeUnlocked, isTrue);
      final json = db.settings.toJson();
      expect(json['developerModeUnlocked'], isTrue);
    });
  });

  group('profile screen gate', () {
    late Directory tmp;
    late DatabaseService db;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('df_devmode_ui_');
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
      // Deterministic platform replies for every plugin call the
      // profile screen makes (notification status card + health
      // rows), so no channel future is left dangling across the
      // fake/real async boundary.
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async {
          switch (call.method) {
            case 'getNotificationChannels':
              return [
                {
                  'id': NotificationService.channelId,
                  'name': 'Reminders',
                  'description': '',
                  'importance': 5,
                }
              ];
            case 'pendingNotificationRequests':
              return <Object>[];
            case 'canScheduleExactNotifications':
            case 'requestNotificationsPermission':
            case 'requestExactAlarmsPermission':
              return true;
            default:
              return null;
          }
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.valor.deliveryflow/battery'),
        (call) async => call.method == 'isIgnoring' ? true : null,
      );
    });

    tearDown(() async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('com.valor.deliveryflow/battery'), null);
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    Future<void> pumpProfile(WidgetTester tester) async {
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
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('locked: tools hidden, the lock entry shows', (tester) async {
      await pumpProfile(tester);
      expect(find.text('اختبار إشعار فوري'), findsNothing);
      expect(find.text('اختبار إشعار مجدول (بعد دقيقة)'), findsNothing);
      expect(find.text('سجل التشخيص'), findsNothing);
      expect(find.text('حالة الإشعارات'), findsNothing);
      expect(find.text('نسخة المطور'), findsOneWidget);
    });

    testWidgets('wrong password: inline error, stays locked', (tester) async {
      await pumpProfile(tester);
      await tester.ensureVisible(find.text('نسخة المطور'));
      await tester.pump();
      await tester.tap(find.text('نسخة المطور'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('تفعيل نسخة المطور'), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      await tester.enterText(
          find.descendant(of: dialog, matching: find.byType(TextField)),
          '0000');
      await tester
          .tap(find.descendant(of: dialog, matching: find.text('تفعيل')));
      await tester.pump();
      expect(find.text('كلمة المرور غير صحيحة'), findsOneWidget);
      expect(find.text('اختبار إشعار فوري'), findsNothing);
      expect(db.settings.developerModeUnlocked, isFalse);
    });

    testWidgets('unlocked (persisted): every gated tool shows', (tester) async {
      // Seed the persisted unlock exactly as a restarted app would
      // read it, then check the revealed state. The save runs in
      // runAsync: test bodies are a FakeAsync zone where Hive's
      // internal timers never fire (widget_test's standing note).
      final s = db.settings..developerModeUnlocked = true;
      await tester.runAsync(() => db.saveSettings(s));
      await pumpProfile(tester);
      expect(find.text('اختبار إشعار فوري'), findsOneWidget);
      expect(find.text('اختبار إشعار مجدول (بعد دقيقة)'), findsOneWidget);
      expect(find.text('سجل التشخيص'), findsOneWidget);
      expect(find.text('حالة الإشعارات'), findsOneWidget);
    });
  });
}
