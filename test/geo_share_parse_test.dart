import 'package:deliveryflow/core/deep_link/geo_share_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// v27.7 regression tests: Amazon Flex shares can arrive as a `geo:`
/// VIEW intent of the form `geo:0,0?q=<address @ lat,lng>`. (0,0) is
/// the conventional "no coordinates" placeholder, so the parser saw a
/// label-only target and geocoded the whole "address @ coords" string,
/// which Nominatim can't resolve («geocode: address not found») — even
/// though the exact coordinates were sitting inside the label.
/// parseShareInput now rescues an embedded coordinate pair from any
/// label-only target before it is returned.
void main() {
  // The exact field payload (2026-10-23): address with Arabic-Indic
  // digits, then "@lat,lng".
  const flexText =
      'شارع أمين الخولي السياحية السادسة ٥٨ الدور ٣@30.003853,30.983884';

  group('v27.7 embedded-coords rescue in label-only targets', () {
    test('geo:0,0?q=<address @ lat,lng> yields the embedded coords',
        () async {
      final t = await parseShareInput('geo:0,0?q=$flexText');
      expect(t, isNotNull);
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.003853, 1e-6));
      expect(t.lng, closeTo(30.983884, 1e-6));
      // Label keeps the customer's address, without the coords/@
      // residue (digits normalized to ASCII, like every share text).
      expect(t.label, contains('شارع أمين الخولي'));
      expect(t.label, isNot(contains('@')));
      expect(t.label, isNot(contains('30.003853')));
      expect(t.label, isNot(contains('30.983884')));
    });

    test('geo:?q=<address @ lat,lng> (no coord part at all) also rescues',
        () async {
      final t = await parseShareInput('geo:?q=$flexText');
      expect(t, isNotNull);
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.003853, 1e-6));
      expect(t.lng, closeTo(30.983884, 1e-6));
      expect(t.label, contains('شارع أمين الخولي'));
      expect(t.label, isNot(contains('@')));
    });

    test('plain Flex text (no geo: wrapper) parses to the same coords',
        () async {
      final t = await parseShareInput(flexText);
      expect(t, isNotNull);
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.003853, 1e-6));
      expect(t.lng, closeTo(30.983884, 1e-6));
      expect(t.label, contains('شارع أمين الخولي'));
    });

    test('geo: label with NO embedded coords stays label-only (geocode '
        'fallback preserved)', () async {
      final t = await parseShareInput('geo:0,0?q=شارع التحرير');
      expect(t, isNotNull);
      expect(t!.hasCoords, isFalse);
      expect(t.label, 'شارع التحرير');
    });

    test('real geo:lat,lng?q=label is unchanged', () async {
      final t = await parseShareInput(
          'geo:30.003853,30.983884?q=شارع أمين الخولي');
      expect(t, isNotNull);
      expect(t!.hasCoords, isTrue);
      expect(t.lat, closeTo(30.003853, 1e-6));
      expect(t.lng, closeTo(30.983884, 1e-6));
      expect(t.label, 'شارع أمين الخولي');
    });
  });
}
