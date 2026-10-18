import 'package:deliveryflow/theme/app_theme.dart';
import 'package:deliveryflow/theme/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// v23 regression test: the dashboard "quick actions" row puts two
/// [GlassButton]s in [Expanded] slots. At ~360dp each button gets ~165dp,
/// and the real Arabic label "عرض تفاصيل الأسبوع" used to paint outside
/// the button (confirmed on a real screenshot). The label must shrink to
/// fit instead of overflowing.
///
/// Flutter's test framework throws a FlutterError when a RenderFlex
/// overflows during layout, so reaching the end of the test with no
/// exception means no overflow happened.
void main() {
  Future<void> pumpQuickActionsRow(
    WidgetTester tester, {
    required double width,
    required ThemeMode themeMode,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: const [
                  Expanded(
                    child: GlassButton(
                      label: 'أضف أوردر',
                      icon: Icons.add_rounded,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: GlassButton(
                      label: 'عرض تفاصيل الأسبوع',
                      icon: Icons.chevron_right_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('GlassButton long Arabic label', () {
    testWidgets('no overflow at 360dp, light theme', (tester) async {
      await pumpQuickActionsRow(tester,
          width: 360, themeMode: ThemeMode.light);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 320dp, light theme', (tester) async {
      await pumpQuickActionsRow(tester,
          width: 320, themeMode: ThemeMode.light);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 360dp, dark theme', (tester) async {
      await pumpQuickActionsRow(tester,
          width: 360, themeMode: ThemeMode.dark);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow on tablet width 768dp', (tester) async {
      await pumpQuickActionsRow(tester,
          width: 768, themeMode: ThemeMode.light);
      expect(tester.takeException(), isNull);
    });
  });
}
