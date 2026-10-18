import 'package:deliveryflow/core/deep_link/geo_share_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseGeoUri', () {
    test('parses plain coordinates', () {
      final t = parseGeoUri('geo:30.0444,31.2357')!;
      expect(t.hasCoords, isTrue);
      expect(t.lat, closeTo(30.0444, 1e-6));
      expect(t.lng, closeTo(31.2357, 1e-6));
      expect(t.label, isEmpty);
    });

    test('parses coordinates with q label', () {
      final t = parseGeoUri('geo:30.0444,31.2357?q=Cairo+Tower')!;
      expect(t.hasCoords, isTrue);
      expect(t.label, 'Cairo Tower');
    });

    test('parses address-only share', () {
      final t = parseGeoUri(
          'geo:0,0?q=%D8%B4%D8%A7%D8%B1%D8%B9%20%D8%A7%D9%84%D8%AA%D8%AD%D8%B1%D9%8A%D8%B1')!;
      expect(t.hasCoords, isFalse);
      expect(t.label, 'شارع التحرير');
    });

    test('tolerates non-encoded q label instead of throwing', () {
      final t = parseGeoUri('geo:0,0?q=شارع التحرير')!;
      expect(t.hasCoords, isFalse);
      expect(t.label, 'شارع التحرير');
    });

    test('rejects garbage', () {
      expect(parseGeoUri('not a uri'), isNull);
      expect(parseGeoUri('geo:'), isNull);
    });
  });

  group('parseShareInput (v24 Google Maps formats, no network)', () {
    test('maps.google.com ?q= with coordinates', () async {
      final t = await parseShareInput('https://maps.google.com/?q=30.0444,31.2357');
      expect(t, isNotNull);
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.0444, 1e-6));
    });

    test('google.com/maps/search with query= coordinates', () async {
      final t = await parseShareInput(
          'https://www.google.com/maps/search/?api=1&query=30.0444,31.2357');
      expect(t, isNotNull);
      expect(t!.hasCoords, isTrue);
    });

    test('place link with @lat,lng keeps place name as label', () async {
      final t = await parseShareInput(
          'https://www.google.com/maps/place/Cairo+Tower/@30.0458,31.2244,17z');
      expect(t, isNotNull);
      expect(t!.hasCoords, isTrue);
      expect(t.label, contains('Cairo Tower'));
    });

    test('search link with address text', () async {
      final t = await parseShareInput(
          'https://www.google.com/maps/search/ميدان التحرير، القاهرة');
      expect(t, isNotNull);
      expect(t!.hasCoords, isFalse);
      expect(t.label, isNotEmpty);
    });

    test('share-sheet text wrapping a URL (trailing punctuation stripped)',
        () async {
      final t = await parseShareInput(
          'شوف المكان ده https://www.google.com/maps?q=30.1,31.2.');
      expect(t, isNotNull);
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.1, 1e-6));
    });

    test('geo: URIs still work through the unified entry point', () async {
      final t = await parseShareInput('geo:30.0,31.0?q=test');
      expect(t, isNotNull);
      expect(t!.hasCoords, isTrue);
      expect(t.label, 'test');
    });

    test('plain text with no URL returns null', () async {
      expect(await parseShareInput('just some text'), isNull);
      expect(await parseShareInput(''), isNull);
    });

    test('unsupported https URL returns null', () async {
      expect(await parseShareInput('https://example.com/foo'), isNull);
    });
  });
}
