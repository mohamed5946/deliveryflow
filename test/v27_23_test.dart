import 'dart:io';

import 'package:deliveryflow/features/registration/glass_otp.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// v27.23: glassy OTP gates (registration + Developer Mode) and the
/// removal of the /insights tab.
///
/// All codes used here are DUMMY values passed to the widget under
/// test. No real gate value appears in this file, in any fixture, or
/// in any test name.
void main() {
  group('OtpGate (pure logic)', () {
    test('matches only the exact code, ignoring surrounding whitespace',
        () {
      const gate = OtpGate('123456');
      expect(gate.matches('123456'), isTrue);
      expect(gate.matches('  123456  '), isTrue);
      expect(gate.matches('123455'), isFalse);
      expect(gate.matches('12345'), isFalse);
      expect(gate.matches(''), isFalse);
    });

    test('digitCount follows the expected code length', () {
      expect(const OtpGate('123456').digitCount, 6);
      expect(const OtpGate('1234').digitCount, 4);
    });

    test('digitsOnly strips every non-digit', () {
      expect(OtpGate.digitsOnly('12a34b'), '1234');
      expect(OtpGate.digitsOnly('ab'), '');
      expect(OtpGate.digitsOnly('987'), '987');
    });
  });

  group('GlassOtpEntry widget (dummy codes only)', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('correct code: spin, then success, then onVerified',
        (tester) async {
      var verified = false;
      await tester.pumpWidget(wrap(GlassOtpEntry(
        expectedCode: '123456',
        title: 'Code',
        hint: 'Enter code',
        verifyLabel: 'Verify',
        errorLabel: 'Wrong code',
        successLabel: 'Verified!',
        onVerified: () => verified = true,
      )));
      // v27.35: one real field per box — enter one digit per box.
      for (var i = 0; i < 6; i++) {
        await tester.enterText(
          find.byKey(ValueKey('otpBox-$i')),
          '${i + 1}',
        );
        await tester.pump();
      }
      // Auto-submit on completion → spinning circle phase.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Verified!'), findsNothing);
      // After the ~900ms transition, success shows, then onVerified.
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('Verified!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      expect(verified, isTrue);
    });

    testWidgets('wrong code: error, then cleared input and restart',
        (tester) async {
      var verified = false;
      var wrongAttempts = 0;
      await tester.pumpWidget(wrap(GlassOtpEntry(
        expectedCode: '123456',
        title: 'Code',
        hint: 'Enter code',
        verifyLabel: 'Verify',
        errorLabel: 'Wrong code',
        successLabel: 'Verified!',
        onVerified: () => verified = true,
        onWrongAttempt: () => wrongAttempts++,
      )));
      // v27.35: one real field per box — enter one digit per box.
      for (var i = 0; i < 6; i++) {
        await tester.enterText(find.byKey(ValueKey('otpBox-$i')), '1');
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('Wrong code'), findsOneWidget);
      expect(find.text('Verified!'), findsNothing);
      expect(verified, isFalse);
      expect(wrongAttempts, 1);
      // After the error hold, the flow restarts from the beginning:
      // error gone, verify button back, boxes empty.
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('Wrong code'), findsNothing);
      expect(find.text('Verify'), findsOneWidget);
      // v27.35: every box is cleared on restart; check box 0.
      final field =
          tester.widget<TextField>(find.byKey(const ValueKey('otpBox-0')));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('input field is digits-only with a numeric keypad',
        (tester) async {
      await tester.pumpWidget(wrap(GlassOtpEntry(
        expectedCode: '123456',
        title: 'Code',
        hint: 'Enter code',
        verifyLabel: 'Verify',
        errorLabel: 'Wrong code',
        successLabel: 'Verified!',
        onVerified: () {},
      )));
      // v27.35: each box is its own field; check box 0.
      final field =
          tester.widget<TextField>(find.byKey(const ValueKey('otpBox-0')));
      expect(field.keyboardType, TextInputType.number);
      expect(
        field.inputFormatters!
            .whereType<FilteringTextInputFormatter>()
            .isNotEmpty,
        isTrue,
      );
    });

    testWidgets('cancel action renders only when provided',
        (tester) async {
      await tester.pumpWidget(wrap(GlassOtpEntry(
        expectedCode: '1234',
        title: 'Code',
        hint: 'Enter code',
        verifyLabel: 'Verify',
        errorLabel: 'Wrong code',
        successLabel: 'Verified!',
        onVerified: () {},
        onCancel: () {},
        cancelLabel: 'Cancel',
      )));
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('v27.23 wiring scans', () {
    test('router has exactly the original 5 tabs, no insights', () {
      final router = File('lib/app/router.dart').readAsStringSync();
      for (final path in [
        '/home',
        '/schedule',
        '/reports',
        '/history',
        '/profile'
      ]) {
        expect(router, contains("'$path'"));
      }
      expect(router, isNot(contains("'/insights'")));
      expect(router, isNot(contains('GlassDashboard')));
    });

    test('no direct BackdropFilter in the new OTP files', () {
      for (final path in [
        'lib/features/registration/glass_otp.dart',
        'lib/features/registration/registration_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src, isNot(contains('BackdropFilter')));
      }
      // Glass blur (if any) comes via GlassCard, which is itself
      // RepaintBoundary-wrapped per the v27.21 performance law.
      final otp =
          File('lib/features/registration/glass_otp.dart')
              .readAsStringSync();
      expect(otp, anyOf(contains('GlassCard'), contains('GlassButton')));
    });

    test('registration gate uses the shared OTP widget, no raw field',
        () {
      final src =
          File('lib/features/registration/registration_screen.dart')
              .readAsStringSync();
      expect(src, contains('GlassOtpEntry'));
      expect(src, isNot(contains('TextField')));
    });
  });
}
