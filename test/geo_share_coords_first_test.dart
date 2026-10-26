import 'package:deliveryflow/core/deep_link/geo_share_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// v27.18 coordinates-FIRST extraction regression tests.
///
/// Field bug (2026-10-26, Mohamed's screenshot): at the end of a trip
/// DeliveryFlow showed "تعذر فتح الموقع المشارك" with reason
/// "geocode: address not found" for the received text
/// "Sameh Gado Street 194 194, 3@30.003383,30.976819".
/// The old extractor took the FIRST number-pair match (`194, 3` —
/// second street number + the digit glued to `@`) and returned null
/// when latitude 194 failed its range check, never scanning on to
/// the real pair. The `@` was not the cause; first-match-and-give-up
/// was. These tests pin the radical fix: scan the ENTIRE text for a
/// valid pair, by any method, no matter what stray characters appear.
void main() {
  group('v27.18 screenshot case (first test)', () {
    test('exact screenshot text extracts coords, never geocodes', () async {
      const screenshot =
          'Sameh Gado Street 194 194, 3@30.003383,30.976819';
      final t = await parseShareInput(screenshot);
      expect(t, isNotNull);
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.003383, 1e-6));
      expect(t.lng, closeTo(30.976819, 1e-6));
      // hasCoords means handleSharedGeoUri goes straight to
      // navigation and never calls geocodeAddressSmart.
      expect(t.label, contains('Sameh Gado Street'));
      expect(t.label, isNot(contains('30.003383')));
      expect(t.label, isNot(contains('30.976819')));
      expect(t.label, isNot(contains('@')));
    });

    test('same text wrapped in geo:0,0?q= also extracts coords', () async {
      final t = await parseShareInput(
          'geo:0,0?q=Sameh Gado Street 194 194, 3@30.003383,30.976819');
      expect(t, isNotNull);
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.003383, 1e-6));
      expect(t.lng, closeTo(30.976819, 1e-6));
    });

    test('extractor directly on the screenshot text', () {
      final t = extractCoordsFromText(
          'Sameh Gado Street 194 194, 3@30.003383,30.976819');
      expect(t, isNotNull);
      expect(t!.lat, closeTo(30.003383, 1e-6));
      expect(t.lng, closeTo(30.976819, 1e-6));
    });
  });

  group('v27.18 @ / spacing / gluing variants', () {
    test('address @30.1,31.2 (no space)', () async {
      final t = await parseShareInput('address @30.1,31.2');
      expect(t!.lat, closeTo(30.1, 1e-6));
      expect(t.lng, closeTo(31.2, 1e-6));
    });

    test('address@30.1,31.2 (glued, no spaces)', () async {
      final t = await parseShareInput('address@30.1,31.2');
      expect(t!.lat, closeTo(30.1, 1e-6));
      expect(t.lng, closeTo(31.2, 1e-6));
    });

    test('address @ 30.1 , 31.2 (spaces around comma)', () async {
      final t = await parseShareInput('address @ 30.1 , 31.2');
      expect(t!.lat, closeTo(30.1, 1e-6));
      expect(t.lng, closeTo(31.2, 1e-6));
    });

    test('address@@30.1,31.2 (doubled @)', () async {
      final t = await parseShareInput('address@@30.1,31.2');
      expect(t!.lat, closeTo(30.1, 1e-6));
      expect(t.lng, closeTo(31.2, 1e-6));
    });

    test('address newline coords, no @ at all', () async {
      final t = await parseShareInput('address\n30.1,31.2');
      expect(t!.lat, closeTo(30.1, 1e-6));
      expect(t.lng, closeTo(31.2, 1e-6));
    });

    test('address #30.1,31.2 and other stray punctuation', () async {
      final t = await parseShareInput('address #\$% & * (30.1,31.2)');
      expect(t!.lat, closeTo(30.1, 1e-6));
      expect(t.lng, closeTo(31.2, 1e-6));
    });
  });

  group('v27.18 Arabic + street numbers + punctuation noise', () {
    test('Arabic text with street numbers and a coordinate pair',
        () async {
      final t = await parseShareInput(
          'شارع النصر عمارة 194 الدور 3، شقة 12 @ 30.05,31.25!!!');
      expect(t, isNotNull);
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.05, 1e-6));
      expect(t.lng, closeTo(31.25, 1e-6));
      expect(t.label, contains('شارع النصر'));
    });

    test('duplicated street numbers before the pair do not poison it',
        () async {
      final t = await parseShareInput('Street 194 194, 194 30.1,31.2');
      expect(t!.lat, closeTo(30.1, 1e-6));
      expect(t.lng, closeTo(31.2, 1e-6));
    });
  });

  group('v27.18 geo: and Google Maps forms', () {
    test('geo:0,0?q=lat,lng', () async {
      final t = await parseShareInput('geo:0,0?q=30.1,31.2');
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.1, 1e-6));
    });

    test('geo:lat,lng direct', () async {
      final t = await parseShareInput('geo:30.1,31.2');
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.1, 1e-6));
    });

    test('Maps link ?q=lat,lng', () async {
      final t = await parseShareInput(
          'https://www.google.com/maps?q=30.1,31.2');
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.1, 1e-6));
    });

    test('Maps link /@lat,lng,zoom', () async {
      final t = await parseShareInput(
          'https://www.google.com/maps/@30.1,31.2,17z');
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.1, 1e-6));
    });

    test('Maps place link /place/.../@lat,lng', () async {
      final t = await parseShareInput(
          'https://www.google.com/maps/place/Cairo+Tower/@30.0458,31.2244,17z');
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.0458, 1e-6));
    });
  });

  group('v27.18 pair-choice rule', () {
    test('two pairs: the pair after @ wins (even though not last)',
        () async {
      // First pair is a decoy, second is marked by @, third trails.
      final t = await parseShareInput(
          'decoy 30.0,31.0 @ 30.5,31.5 trailing 30.9,31.9');
      expect(t!.lat, closeTo(30.5, 1e-6));
      expect(t.lng, closeTo(31.5, 1e-6));
    });

    test('two pairs, no @: the last valid pair wins', () async {
      final t = await parseShareInput('first 30.0,31.0 then 30.9,31.9');
      expect(t!.lat, closeTo(30.9, 1e-6));
      expect(t.lng, closeTo(31.9, 1e-6));
    });
  });

  group('v27.18 rejection paths', () {
    test('no coordinates: label-only target for geocode fallback',
        () async {
      final t = await parseShareInput('شارع فيصل الرئيسي');
      expect(t, isNotNull);
      expect(t!.hasCoords, isFalse);
      // The full original text is preserved as the label, so the
      // caller can geocode it and, on failure, show it in the dialog.
      expect(t.label, 'شارع فيصل الرئيسي');
    });

    test('no coordinates in plain English text: label preserved too',
        () async {
      final t = await parseShareInput('just some text');
      expect(t, isNotNull);
      expect(t!.hasCoords, isFalse);
      expect(t.label, 'just some text');
    });

    test('pair outside Egypt bounds is rejected, never a target',
        () async {
      final t = await parseShareInput('عنوان @ 40.7128,-74.0060');
      expect(t, isNotNull);
      expect(t!.hasCoords, isFalse);
    });

    test('pair without decimal points is never coordinates', () async {
      // Street numbers only: must not become a navigation target.
      final t = await parseShareInput('Street 194, 3');
      expect(t, isNotNull);
      expect(t!.hasCoords, isFalse);
    });

    test('empty text still returns null', () async {
      expect(await parseShareInput(''), isNull);
      expect(await parseShareInput('   '), isNull);
    });

    test('bare non-Maps URL still returns null', () async {
      expect(await parseShareInput('https://example.com/foo'), isNull);
    });
  });
}
