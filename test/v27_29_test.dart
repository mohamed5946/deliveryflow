import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:deliveryflow/theme/bin_eating_delete_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// v27.29: Mohamed's two corrections to the v27.28 delete animation,
/// verified here:
/// 1. No floating red line in the idle bin: the single lid sits flush on
///    the bin body's rim (lid bottom edge == body top edge, no gap).
/// 2. Corrected trajectory: the lid lifts STRAIGHT UP and holds, and each
///    letter hops in from above — its final approach into the bin is a
///    purely vertical drop through the lid gap (dx constant, dy
///    increasing), not a sideways slide-in.
/// 3. Exactly ONE lid element exists at every moment: idle, mid-flight,
///    and after closing — never two lids, never a lid above a line.
void main() {
  Future<void> pumpBin(
    WidgetTester tester, {
    required VoidCallback onConfirmed,
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Center(
              child: BinEatingDeleteButton(
                label: 'Delete',
                onConfirmed: onConfirmed,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Rect rectOf(WidgetTester tester, String key) {
    final box = tester.renderObject(find.byKey(Key(key))) as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  group('v27.29 bin: one flush lid, from-above entry', () {
    testWidgets('idle bin: exactly one lid, flush on the body rim',
        (tester) async {
      await pumpBin(tester, onConfirmed: () {});
      // Single-lid constraint in the idle state.
      expect(find.byKey(const Key('binLid')), findsOneWidget);
      expect(find.byKey(const Key('binBody')), findsOneWidget);
      // No gap between lid and body: the lid is part of the bin, not a
      // floating line above it.
      final lid = rectOf(tester, 'binLid');
      final body = rectOf(tester, 'binBody');
      expect(body.top - lid.bottom, closeTo(0.0, 1.0));
      // And the lid sits directly above the body (same horizontal span).
      expect(lid.center.dx, closeTo(body.center.dx, 2.0));
    });

    testWidgets(
        'lid lifts straight up and holds; letters drop vertically in',
        (tester) async {
      var confirmed = 0;
      await pumpBin(tester, onConfirmed: () => confirmed++);
      final idleLid = rectOf(tester, 'binLid');
      await tester.tap(find.byType(BinEatingDeleteButton));
      // Settle pump: tap's onTap fires on the next frame, so the
      // controller starts here; later pumps then measure real time.
      await tester.pump();
      // Lid rises straight up: same x, clearly above idle (t = 300 ms is
      // inside the hold window, after the 0.15 lift and before closing).
      await tester.pump(const Duration(milliseconds: 300));
      final raisedLid = rectOf(tester, 'binLid');
      expect(find.byKey(const Key('binLid')), findsOneWidget);
      expect(raisedLid.center.dx, closeTo(idleLid.center.dx, 0.5));
      expect(raisedLid.center.dy, lessThan(idleLid.center.dy - 8));
      // Letter 0 flight is [0.15, 0.45] of 1400 ms: its drop phase
      // (p in 0.6..1) runs from t = 462 ms to t = 630 ms. Across two
      // pumps inside that phase the letter must move straight DOWN:
      // x constant, y increasing — a from-above entry through the gap.
      await tester.pump(const Duration(milliseconds: 162));
      final dropStart =
          tester.getCenter(find.byKey(const Key('binLetter_0')));
      await tester.pump(const Duration(milliseconds: 84));
      final dropMid =
          tester.getCenter(find.byKey(const Key('binLetter_0')));
      expect(dropMid.dx, closeTo(dropStart.dx, 1.0));
      expect(dropMid.dy, greaterThan(dropStart.dy + 1));
      // Still exactly one lid mid-flight, and it is still raised.
      expect(find.byKey(const Key('binLid')), findsOneWidget);
      expect(
        rectOf(tester, 'binLid').center.dy,
        lessThan(idleLid.center.dy - 8),
      );
    });

    testWidgets('letters enter sequentially, lid closes, check draws once',
        (tester) async {
      var confirmed = 0;
      await pumpBin(tester, onConfirmed: () => confirmed++);
      final idleLid = rectOf(tester, 'binLid');
      await tester.tap(find.byType(BinEatingDeleteButton));
      await tester.pump();
      // At t = 630 ms letter 0 has finished (its interval ends at 0.45)
      // while letter 1 (interval [0.21, 0.51]) is still visible: the
      // hops are sequential, one after another.
      await tester.pump(const Duration(milliseconds: 630));
      double letterOpacity(String key) {
        return tester
            .widget<Opacity>(find.ancestor(
              of: find.byKey(Key(key)),
              matching: find.byType(Opacity),
            ))
            .opacity;
      }

      expect(letterOpacity('binLetter_0'), 0.0);
      expect(letterOpacity('binLetter_1'), greaterThan(0.0));
      // Lid is raised at 630 ms (hold window) and coming back down at
      // 1100 ms (inside the 0.70 → 0.82 close window). Full close
      // coincides with the check replacing the bin, so the lid itself
      // is not queried after that point.
      final raisedLid = rectOf(tester, 'binLid');
      expect(raisedLid.center.dy, lessThan(idleLid.center.dy - 8));
      await tester.pump(const Duration(milliseconds: 470));
      final closingLid = rectOf(tester, 'binLid');
      expect(find.byKey(const Key('binLid')), findsOneWidget);
      expect(closingLid.center.dy, greaterThan(raisedLid.center.dy));
      expect(closingLid.center.dy, lessThan(idleLid.center.dy));
      // Check draws, then completion fires exactly once.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('binSuccessCheck')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      expect(confirmed, 1);
      await tester.pump(const Duration(milliseconds: 500));
      expect(confirmed, 1);
    });

    testWidgets('reduce-motion skips the animation and completes at once',
        (tester) async {
      var confirmed = 0;
      await pumpBin(tester,
          onConfirmed: () => confirmed++, disableAnimations: true);
      await tester.tap(find.byType(BinEatingDeleteButton));
      await tester.pump();
      expect(confirmed, 1);
      expect(find.byKey(const Key('binSuccessCheck')), findsNothing);
    });
  });
}
