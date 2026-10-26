import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/features/daily_orders/order_detail_screen.dart';
import 'package:deliveryflow/theme/design_system.dart';
import 'package:deliveryflow/theme/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// v27.20 regression tests:
/// - WeekDayStrip names follow the locale (the reported bug: the strip
///   stayed Arabic after switching the app to English, because it used
///   a hardcoded Arabic list).
/// - End Order button visibility: only during the two active legs.
/// - Hero tags are unique per order (a shared tag throws
///   'multiple heroes share the same tag').
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  group('weekdayNames', () {
    test('Arabic names, Sunday first', () {
      expect(WeekDayStrip.weekdayNames('ar'), [
        'الأحد',
        'الاثنين',
        'الثلاثاء',
        'الأربعاء',
        'الخميس',
        'الجمعة',
        'السبت',
      ]);
    });

    test('English names, Sunday first', () {
      expect(WeekDayStrip.weekdayNames('en'), [
        'Sunday',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ]);
    });

    test('unknown locale falls back to English', () {
      expect(WeekDayStrip.weekdayNames('fr').first, 'Sunday');
    });
  });

  testWidgets('WeekDayStrip renders the locale names', (tester) async {
    Future<void> pump(Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: WeekDayStrip(weekStart: DateTime(2026, 10, 25)),
          ),
        ),
      );
      await tester.pump();
    }

    await pump(const Locale('ar'));
    expect(find.text('الأحد'), findsOneWidget);
    expect(find.text('Sunday'), findsNothing);

    await pump(const Locale('en'));
    expect(find.text('Sunday'), findsOneWidget);
    expect(find.text('الأحد'), findsNothing);
  });

  group('showEndOrderButton', () {
    OrderEntry entryWithStatus(int status) => OrderEntry(
          id: 'e1',
          dateKey: '2026-10-27',
          timestampMillis: 0,
          status: status,
        );

    test('hidden when pending and completed', () {
      expect(showEndOrderButton(entryWithStatus(0)), isFalse);
      expect(showEndOrderButton(entryWithStatus(3)), isFalse);
    });

    test('visible during both active legs only', () {
      expect(showEndOrderButton(entryWithStatus(1)), isTrue);
      expect(showEndOrderButton(entryWithStatus(2)), isTrue);
    });
  });

  test('Hero tags are unique per order', () {
    expect(orderDetailHeroTag('a'), 'order-detail-a');
    expect(orderDetailHeroTag('a'), isNot(orderDetailHeroTag('b')));
  });

  testWidgets('Hero flies through SmoothPageRoute', (tester) async {
    // The app's custom PageRouteBuilder must not suppress Hero:
    // pushing a route whose page holds the same tag must complete
    // the flight without a duplicate-tag error and land on the
    // destination hero.
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              SmoothPageRoute(
                builder: (_) => Hero(
                  tag: orderDetailHeroTag('x'),
                  child: const Material(
                    type: MaterialType.transparency,
                    child: Text('destination card'),
                  ),
                ),
              ),
            ),
            child: Hero(
              tag: orderDetailHeroTag('x'),
              child: const Material(
                type: MaterialType.transparency,
                child: Text('source card'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('source card'));
    await tester.pumpAndSettle();
    expect(find.text('destination card'), findsOneWidget);
  });
}
