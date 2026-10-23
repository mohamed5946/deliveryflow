import 'package:deliveryflow/theme/top_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// v27.4: the app-wide top snackbar — every in-app bar slides down
/// from the TOP of the screen (Mohamed's ask) instead of rising from
/// the bottom over the navigation bar.
void main() {
  Widget host(void Function(BuildContext) action) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => action(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows near the top and auto-dismisses', (tester) async {
    await tester.pumpWidget(host((c) => showTopSnackBar(c, 'تم الحفظ')));
    await tester.tap(find.text('go'));
    await tester.pump();
    // Let the slide-down animation finish.
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('تم الحفظ'), findsOneWidget);
    // On the default 800x600 test surface the banner must sit in the
    // top area, nowhere near the bottom.
    final top = tester.getTopLeft(find.text('تم الحفظ')).dy;
    expect(top, lessThan(200));
    // Default duration is the snackbar-standard 4 seconds.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('تم الحفظ'), findsNothing);
  });

  testWidgets('action button fires the callback and dismisses', (tester) async {
    var tapped = false;
    await tester.pumpWidget(host((c) => showTopSnackBar(
          c,
          'اتحذف الأوردر',
          actionLabel: 'تراجع',
          onAction: () => tapped = true,
        )));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('تراجع'));
    await tester.pump();
    expect(tapped, isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('اتحذف الأوردر'), findsNothing);
  });

  testWidgets('a second banner replaces the first', (tester) async {
    BuildContext? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          captured = c;
          return const SizedBox();
        }),
      ),
    ));
    showTopSnackBar(captured!, 'الأولى');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    showTopSnackBar(captured!, 'التانية');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('الأولى'), findsNothing);
    expect(find.text('التانية'), findsOneWidget);
    // Drain the second banner's auto-dismiss timer before test end.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('التانية'), findsNothing);
  });
}
