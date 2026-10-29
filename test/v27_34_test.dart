import 'package:deliveryflow/features/registration/glass_otp.dart';
import 'package:deliveryflow/theme/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// v27.34: registration-code gate keyboard fix.
///
/// Field report (Infinix/XOS): tapping the digit boxes never opened
/// the keyboard — the old input was a 1px, opacity-0 hidden field
/// that relied on a programmatic focus request. These tests guard
/// the replacement: a real, normally-sized input covering the boxes
/// row, focusable by tapping the row, with digits mirrored into the
/// visible boxes and the full-entry submit path intact.
///
/// All codes used here are DUMMY values passed to the widget under
/// test. No real gate value appears in this file.
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

  group('v27.34 gate input (keyboard fix)', () {
    testWidgets('input field is normally sized, not a 1px hidden field',
        (tester) async {
      await tester.pumpWidget(wrap(gate()));
      final box =
          tester.getSize(find.byType(TextField).first);
      // The old bug was a 1px-tall invisible field; the replacement
      // must cover the boxes row (64 tall, spanning the row width).
      expect(box.height, greaterThanOrEqualTo(48));
      expect(box.width, greaterThan(100));
    });

    testWidgets('no opacity-0 wrapper hides the input', (tester) async {
      await tester.pumpWidget(wrap(gate()));
      expect(
        find.byWidgetPredicate(
            (w) => w is Opacity && w.opacity == 0),
        findsNothing,
      );
    });

    testWidgets('tapping the boxes row gives the input focus',
        (tester) async {
      await tester.pumpWidget(wrap(gate()));
      await tester.pump();
      final field =
          tester.widget<TextField>(find.byType(TextField));
      // Drop any autofocus so the tap itself is what focuses.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(field.focusNode?.hasFocus, isFalse);
      // Tap the middle of the boxes row (the input covers it).
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(field.focusNode?.hasFocus, isTrue);
    });

    testWidgets('typing digits updates the visible boxes',
        (tester) async {
      await tester.pumpWidget(wrap(gate()));
      await tester.enterText(find.byType(TextField), '123');
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // Verify button stays disabled until the entry is full.
      final button = tester.widget<GlassButton>(
        find.byType(GlassButton),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('full entry still triggers spin, success, onVerified',
        (tester) async {
      var verified = false;
      await tester.pumpWidget(wrap(
        gate(onVerified: () => verified = true),
      ));
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Verified!'), findsNothing);
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('Verified!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      expect(verified, isTrue);
    });

    testWidgets('input field stays digits-only with numeric keypad',
        (tester) async {
      await tester.pumpWidget(wrap(gate()));
      final field =
          tester.widget<TextField>(find.byType(TextField));
      expect(field.keyboardType, TextInputType.number);
      expect(
        field.inputFormatters!
            .whereType<FilteringTextInputFormatter>()
            .isNotEmpty,
        isTrue,
      );
    });
  });
}
