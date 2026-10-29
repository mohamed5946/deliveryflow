// v27.35 — Real digit boxes + account creation via Google.
//
// Field verdict on v27.34: the single rectangular input was REJECTED
// (the boxes disappeared, replaced by a strip). v27.35 restores the
// boxes as REAL tappable inputs: one TextField per box, tap a box to
// focus it, digits fill sequentially, auto-submit when full, ~900ms
// spin, green success / red error + full restart, verify button
// enabled only when full. No single-rectangle field, no overlay
// strip, no opacity-0 / 1px hidden-field trick.
//
// Google sign-up: Google sign-in WITHOUT creating a profile, then a
// short completion step (username + phone, each unique) creates the
// driver profile + login mappings. A Google account stays separate
// from an Email/Password account with the same email (no
// auto-linking). The fake backend stands in for real Google sign-in.
//
// All codes used here are DUMMY values passed to the widgets /
// backends under test. No real gate value appears in this file.
import 'dart:io';

import 'package:deliveryflow/core/cloud/cloud_providers.dart';
import 'package:deliveryflow/core/cloud/cloud_services.dart';
import 'package:deliveryflow/core/cloud/cloud_types.dart';
import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:deliveryflow/core/providers.dart';
import 'package:deliveryflow/features/cloud/cloud_account_screen.dart';
import 'package:deliveryflow/features/registration/glass_otp.dart';
import 'package:deliveryflow/theme/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'v27_33_test.dart' show FakeCloudBackend;

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  GlassOtpEntry gate({VoidCallback? onVerified}) => GlassOtpEntry(
        expectedCode: '123456',
        title: 'Code',
        hint: 'Enter code',
        verifyLabel: 'Verify',
        errorLabel: 'Wrong code',
        successLabel: 'Verified!',
        onVerified: onVerified ?? () {},
      );

  TextField boxField(WidgetTester tester, int index) =>
      tester.widget<TextField>(find.byKey(ValueKey('otpBox-$index')));

  Future<void> enterDigit(
    WidgetTester tester,
    int index,
    String digit,
  ) async {
    await tester.enterText(find.byKey(ValueKey('otpBox-$index')), digit);
    await tester.pump();
  }

  group('v27.35 gate: real digit boxes', () {
    testWidgets('one real TextField per box, no single-rectangle input',
        (tester) async {
      await tester.pumpWidget(wrap(gate()));
      await tester.pump();
      // Six boxes for a six-digit code: exactly six fields, each
      // keyed, inside the boxes row — not one field covering a row.
      expect(find.byType(TextField), findsNWidgets(6));
      for (var i = 0; i < 6; i++) {
        expect(find.byKey(ValueKey('otpBox-$i')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('otpBoxesRow')), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Opacity && w.opacity == 0),
        findsNothing,
      );
    });

    testWidgets('each box is 52 wide and 64 tall', (tester) async {
      await tester.pumpWidget(wrap(gate()));
      await tester.pump();
      // The box Container carries its size as tight constraints
      // (52x64 per the design) — deterministic, no layout guessing.
      for (var i = 0; i < 6; i++) {
        final box = tester.widget<Container>(
          find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.child is TextField &&
                (w.child as TextField).key == ValueKey('otpBox-$i'),
          ),
        );
        final c = box.constraints!;
        expect(c.minWidth, 52);
        expect(c.maxWidth, 52);
        expect(c.minHeight, 64);
        expect(c.maxHeight, 64);
      }
    });

    testWidgets('tap a box focuses its own input', (tester) async {
      await tester.pumpWidget(wrap(gate()));
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(boxField(tester, 0).focusNode?.hasFocus, isFalse);
      await tester.tap(find.byKey(const ValueKey('otpBox-0')));
      await tester.pump();
      expect(boxField(tester, 0).focusNode?.hasFocus, isTrue);
    });

    testWidgets('tap-ahead redirect: tapping a later empty box '
        'focuses the first empty box', (tester) async {
      await tester.pumpWidget(wrap(gate()));
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('otpBox-3')));
      await tester.pump();
      // Sequential fill: digits must land one after another, so a
      // tap ahead of the next empty box jumps back to it.
      expect(boxField(tester, 0).focusNode?.hasFocus, isTrue);
      expect(boxField(tester, 3).focusNode?.hasFocus, isFalse);
    });

    testWidgets('sequential fill: digit in box 0 advances focus to box 1',
        (tester) async {
      await tester.pumpWidget(wrap(gate()));
      await tester.pump();
      await enterDigit(tester, 0, '1');
      expect(boxField(tester, 0).controller?.text, '1');
      expect(boxField(tester, 1).focusNode?.hasFocus, isTrue);
      await enterDigit(tester, 1, '2');
      expect(boxField(tester, 1).controller?.text, '2');
      expect(boxField(tester, 2).focusNode?.hasFocus, isTrue);
    });

    testWidgets('verify button stays disabled until the entry is full',
        (tester) async {
      await tester.pumpWidget(wrap(gate()));
      await tester.pump();
      GlassButton verifyButton() =>
          tester.widget<GlassButton>(find.byType(GlassButton));
      expect(verifyButton().onPressed, isNull);
      for (var i = 0; i < 5; i++) {
        await enterDigit(tester, i, '${i + 1}');
      }
      // Five of six digits: still not submittable from the button.
      expect(verifyButton().onPressed, isNull);
    });

    testWidgets('full entry triggers spin, success, onVerified',
        (tester) async {
      var verified = false;
      await tester.pumpWidget(wrap(gate(onVerified: () => verified = true)));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await enterDigit(tester, i, '${i + 1}');
      }
      // The sixth digit auto-submits: boxes give way to the spinning
      // circle (identified by its lock icon — other rotating widgets
      // exist in the tree, so the icon is the precise marker).
      expect(find.byKey(const ValueKey('otpBoxesRow')), findsNothing);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('Verified!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      expect(verified, isTrue);
    });

    testWidgets('wrong code shows error, then clears and refocuses',
        (tester) async {
      await tester.pumpWidget(wrap(gate()));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await enterDigit(tester, i, '${6 - i}');
      }
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('Wrong code'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1000));
      // Full restart: every box cleared, box 0 focused again.
      for (var i = 0; i < 6; i++) {
        expect(boxField(tester, i).controller?.text, isEmpty);
      }
      expect(boxField(tester, 0).focusNode?.hasFocus, isTrue);
    });

    testWidgets('backspace on an empty box deletes the previous digit',
        (tester) async {
      await tester.pumpWidget(wrap(gate()));
      await tester.pump();
      await enterDigit(tester, 0, '1');
      expect(boxField(tester, 1).focusNode?.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(boxField(tester, 0).controller?.text, isEmpty);
      expect(boxField(tester, 0).focusNode?.hasFocus, isTrue);
    });

    testWidgets('boxes are digits-only with a numeric keypad',
        (tester) async {
      await tester.pumpWidget(wrap(gate()));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        final field = boxField(tester, i);
        expect(field.keyboardType, TextInputType.number);
        expect(
          field.inputFormatters!
              .whereType<FilteringTextInputFormatter>(),
          isNotEmpty,
        );
        expect(
          field.inputFormatters!
              .whereType<LengthLimitingTextInputFormatter>(),
          isNotEmpty,
        );
      }
    });
  });

  group('v27.35 Google sign-up (service, fake backend)', () {
    test('begin returns needs-completion and creates NO account',
        () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      final start = await auth.beginGoogleSignUp();
      expect(start.needsCompletion, isTrue);
      expect(start.account, isNull);
      expect(backend.users.containsKey('google_uid'), isFalse);
      expect(backend.currentAccount, isNull);
    });

    test('complete creates a driver with all three login mappings',
        () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.beginGoogleSignUp();
      final account = await auth.completeGoogleSignUp(
        username: 'gdriver',
        phone: '01012345678',
      );
      expect(account.uid, 'google_uid');
      expect(account.role, CloudRole.driver);
      expect(account.email, 'google.driver@example.com');
      expect(backend.usernameLookups['gdriver'], account.email);
      expect(
        await backend.resolveLoginEmail('gdriver'),
        account.email,
      );
      expect(
        await backend.resolveLoginEmail('01012345678'),
        account.email,
      );
      expect(
        await backend.lookupUsernameByEmail(account.email),
        'gdriver',
      );
    });

    test('complete with a taken username throws the exact Arabic message',
        () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(
        email: 'a@x.y',
        password: 'dummy123',
        username: 'takenname',
        phone: '01112345678',
      );
      await auth.beginGoogleSignUp();
      Object? error;
      try {
        await auth.completeGoogleSignUp(
          username: 'TAKENNAME',
          phone: '01012345678',
        );
      } catch (e) {
        error = e;
      }
      expect(
        error.toString(),
        contains('الـ username ده اتاخد قبل كده، اختار username تاني'),
      );
    });

    test('complete with a taken phone throws the exact Arabic message',
        () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.signUp(
        email: 'a@x.y',
        password: 'dummy123',
        username: 'someone',
        phone: '01012345678',
      );
      await auth.beginGoogleSignUp();
      Object? error;
      try {
        await auth.completeGoogleSignUp(
          username: 'freename',
          phone: '01012345678',
        );
      } catch (e) {
        error = e;
      }
      expect(
        error.toString(),
        contains('رقم الموبايل ده اتاخد قبل كده، استخدم رقم تاني'),
      );
    });

    test('pre-existing Google account signs in via begin', () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      final first = await auth.signInWithGoogle();
      expect(first, isNotNull);
      await auth.signOut();
      final start = await auth.beginGoogleSignUp();
      expect(start.account, isNotNull);
      expect(start.needsCompletion, isFalse);
      expect(start.account!.uid, 'google_uid');
    });

    test('cancel clears the pending sign-up; complete then fails',
        () async {
      final backend = FakeCloudBackend();
      final auth = CloudAuthService(backend);
      await auth.beginGoogleSignUp();
      await auth.cancelGoogleSignUp();
      Object? error;
      try {
        await auth.completeGoogleSignUp(
          username: 'gdriver',
          phone: '01012345678',
        );
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
    });
  });

  group('v27.35 Google sign-up (widget)', () {
    Future<DatabaseService> tempDb(WidgetTester tester) async {
      late Directory tmp;
      late DatabaseService db;
      await tester.runAsync(() async {
        tmp = await Directory.systemTemp.createTemp('df_v2735_ui_');
        db = DatabaseService();
        await db.init(hivePath: tmp.path);
      });
      addTearDown(() => tester.runAsync(() async {
            await Hive.close();
            await tmp.delete(recursive: true);
          }));
      return db;
    }

    testWidgets('sign-up view shows Google button; completing creates '
        'the account', (tester) async {
      final db = await tempDb(tester);
      final backend = FakeCloudBackend();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cloudBackendProvider.overrideWithValue(backend),
            databaseServiceProvider.overrideWithValue(db),
            settingsProvider.overrideWith(
              (ref) => SettingsNotifier(db, NotificationService()),
            ),
          ],
          child: const MaterialApp(home: CloudAccountScreen()),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('إنشاء حساب'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('cloudGoogleSignUpButton')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('cloudGoogleSignUpButton')));
      await tester.pump();
      // Completion form: username + phone, then create.
      expect(
        find.byKey(const ValueKey('cloudGoogleUsernameField')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cloudGooglePhoneField')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('cloudGoogleUsernameField')),
        'gdriver',
      );
      await tester.enterText(
        find.byKey(const ValueKey('cloudGooglePhoneField')),
        '01012345678',
      );
      await tester.tap(find.byKey(const ValueKey('cloudGoogleCompleteButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(backend.users['google_uid'], isNotNull);
      expect(backend.users['google_uid']!.username, 'gdriver');
      expect(find.text('gdriver'), findsWidgets);
    });
  });
}
