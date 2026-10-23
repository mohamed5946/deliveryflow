import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/navigation/navigation_screen.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/design_system.dart';
import '../../theme/page_transitions.dart';
import '../date_time/week_calendar.dart';
import '../logging/app_log_service.dart';
import '../providers.dart';
import '../tracking/delivery_tracking_service.dart';

/// Result of parsing a shared location: a `geo:` URI, a Google Maps URL,
/// or share-sheet text containing one.
class GeoShareTarget {
  /// Coordinates when the share carries them; null for address-only
  /// shares (those need geocoding first).
  final double? lat;
  final double? lng;

  /// Human label / address (may be empty — then we reverse-geocode).
  final String label;

  const GeoShareTarget({this.lat, this.lng, this.label = ''});

  /// True when usable coordinates are present (0,0 counts as absent —
  /// it is the conventional "no coordinates" placeholder).
  bool get hasCoords =>
      lat != null && lng != null && !(lat == 0 && lng == 0);
}

/// Reads shared-location intents captured by MainActivity, on cold start
/// and via onNewIntent while already running:
/// - `geo:` VIEW intents (e.g. navigation shared from the Amazon Flex app)
/// - https Google Maps VIEW intents
/// - ACTION_SEND share-sheet text (e.g. a Google Maps link shared as text)
/// Each payload is delivered exactly once (the native side consumes it).
class GeoIntentReceiver {
  static const _channel =
      MethodChannel('com.valor.deliveryflow/nav_intent');

  /// Returns the pending shared payload, or null when nothing was shared.
  Future<String?> takeNavUri() async {
    try {
      final uri = await _channel.invokeMethod<String>('getNavUri');
      if (uri == null) return null;
      final t = uri.trim();
      if (t.isEmpty) return null;
      // v24: geo: URIs and Google Maps links/text — the Dart parser
      // decides what is usable.
      return t;
    } catch (_) {
      return null;
    }
  }
}

/// Parses `geo:lat,lng`, `geo:lat,lng?q=label` and `geo:0,0?q=address`
/// forms. Returns null when the URI carries neither coordinates nor a
/// usable query.
GeoShareTarget? parseGeoUri(String raw) {
  if (!raw.startsWith('geo:')) return null;
  final rest = raw.substring(4);
  var coordPart = rest;
  var query = '';
  final qIdx = rest.indexOf('?');
  if (qIdx >= 0) {
    coordPart = rest.substring(0, qIdx);
    query = rest.substring(qIdx + 1);
  }
  double? lat;
  double? lng;
  final coords = coordPart.split(',');
  if (coords.length >= 2) {
    lat = double.tryParse(coords[0].trim());
    lng = double.tryParse(coords[1].trim());
  }
  var label = '';
  for (final part in query.split('&')) {
    final kv = part.split('=');
    if (kv.length == 2 && kv[0] == 'q') {
      // v24: tolerate non-percent-encoded labels (real shares are
      // sometimes sloppy) — never crash the share flow on decode.
      final rawLabel = kv[1].replaceAll('+', ' ');
      try {
        label = Uri.decodeComponent(rawLabel).trim();
      } catch (_) {
        label = rawLabel.trim();
      }
    }
  }
  if (lat == null || lng == null) {
    // Address-only share: coordinates must come from geocoding.
    if (label.isEmpty) return null;
    return GeoShareTarget(label: label);
  }
  return GeoShareTarget(lat: lat, lng: lng, label: label);
}

/// v24: does this look like a Google Maps share URL?
bool _looksLikeMapsUrl(String s) {
  final l = s.toLowerCase();
  return (l.contains('google.') && l.contains('/maps')) ||
      l.contains('maps.google.') ||
      l.contains('goo.gl/maps') ||
      l.contains('maps.app.goo.gl');
}

/// v24: follows HTTP redirects manually (max 5 hops) so short links
/// (goo.gl/maps/…, maps.app.goo.gl/…) resolve to the real Google Maps
/// URL before parsing. Returns the last URL seen on any failure.
Future<String> _resolveShortLink(String url) async {
  var current = url;
  final client = http.Client();
  try {
    for (var i = 0; i < 5; i++) {
      final uri = Uri.tryParse(current);
      if (uri == null || !uri.hasScheme) break;
      http.StreamedResponse resp;
      try {
        final req = http.Request('GET', uri)..followRedirects = false;
        resp = await client.send(req).timeout(const Duration(seconds: 10));
      } catch (_) {
        break;
      }
      // Drain so the connection closes cleanly; a slow body must
      // never hang the share flow.
      try {
        await resp.stream.drain<void>().timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {}
      final code = resp.statusCode;
      final loc = resp.headers['location'];
      if ((code == 301 ||
              code == 302 ||
              code == 303 ||
              code == 307 ||
              code == 308) &&
          loc != null &&
          loc.isNotEmpty) {
        current = uri.resolve(loc).toString();
        continue;
      }
      break;
    }
  } finally {
    client.close();
  }
  return current;
}

/// v24: percent-decodes a URL component, tolerating values that were
/// never encoded (never throws).
String _safeDecode(String v) {
  final spaced = v.replaceAll('+', ' ');
  try {
    return Uri.decodeComponent(spaced).trim();
  } catch (_) {
    return spaced.trim();
  }
}

/// v24: parses Google Maps share URLs —
/// `maps.google.com/?q=`, `google.com/maps/search/…`, `/place/…/@lat,lng`,
/// `?q=lat,lng`, `?query=`, `?destination=`, `?daddr=`.
/// Returns null when no coordinates and no usable address are found.
GeoShareTarget? _parseGoogleMapsUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  // @lat,lng in the path (place/dir links). Also grab the place name
  // as a label when present: /place/<name>/@lat,lng.
  final atMatch =
      RegExp(r'@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)').firstMatch(url);
  if (atMatch != null) {
    final lat = double.tryParse(atMatch.group(1)!);
    final lng = double.tryParse(atMatch.group(2)!);
    if (lat != null && lng != null) {
      var label = '';
      final placeMatch = RegExp(r'/place/([^/?#@]+)').firstMatch(uri.path);
      if (placeMatch != null) {
        label =
            _safeDecode(placeMatch.group(1)!).replaceAll('_', ' ').trim();
      }
      return GeoShareTarget(lat: lat, lng: lng, label: label);
    }
  }

  // Query params: q / query / destination / daddr.
  for (final key in ['q', 'query', 'destination', 'daddr']) {
    final v = uri.queryParameters[key]?.trim();
    if (v != null && v.isNotEmpty) return _coordsOrLabel(v);
  }

  // /search/<address> path segment.
  final searchMatch = RegExp(r'/search/([^/?#]+)').firstMatch(uri.path);
  if (searchMatch != null) {
    final v = _safeDecode(searchMatch.group(1)!);
    if (v.isNotEmpty) return _coordsOrLabel(v);
  }

  // /place/<name> without coordinates — geocode the name.
  final placeOnly = RegExp(r'/place/([^/?#@]+)').firstMatch(uri.path);
  if (placeOnly != null) {
    final v = _safeDecode(placeOnly.group(1)!).replaceAll('_', ' ').trim();
    if (v.isNotEmpty) return GeoShareTarget(label: v);
  }
  return null;
}

/// v24: "lat,lng" → coordinates, anything else → address label.
GeoShareTarget _coordsOrLabel(String v) {
  final parts = v.split(',');
  if (parts.length >= 2) {
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat != null && lng != null) {
      return GeoShareTarget(lat: lat, lng: lng);
    }
  }
  return GeoShareTarget(label: v);
}

/// v24.2/v25.1: normalizes share text before parsing. Flex/WhatsApp shares
/// can carry non-ASCII digits (Arabic-Indic ٢٩.٩٨٧ and many other scripts),
/// look-alike separators (Arabic decimal separator ٫ U+066B, one-dot leader
/// U+2024, fullwidth ．，) that render identically to "." / "," in
/// screenshots, the Arabic comma (،), or invisible Unicode marks (ZWSP,
/// RLM/LRM) that silently break coordinate parsing. The coordinates are
/// the exact location, so normalize aggressively: one pass over the code
/// units converts every known decimal-digit block and separator to ASCII
/// and drops invisible marks.
String _normalizeShareText(String s) {
  // Zero code points of common Unicode decimal-digit (Nd) blocks; each
  // block is ten consecutive code points for digits 0–9.
  const digitBases = <int>[
    0x0660, // Arabic-Indic
    0x06F0, // Extended Arabic-Indic
    0x0966, // Devanagari
    0x09E6, // Bengali
    0x0A66, // Gurmukhi
    0x0AE6, // Gujarati
    0x0B66, // Oriya
    0x0BE6, // Tamil
    0x0C66, // Telugu
    0x0CE6, // Kannada
    0x0D66, // Malayalam
    0x0E50, // Thai
    0x0ED0, // Lao
    0x0F20, // Tibetan
    0x1040, // Myanmar
    0x17E0, // Khmer
    0x1810, // Mongolian
    0xFF10, // Fullwidth
  ];
  final buf = StringBuffer();
  for (final unit in s.codeUnits) {
    // Invisible Unicode marks: ZWSP, ZWNJ, ZWJ, LRM, RLM, BOM — drop.
    if (unit == 0x200B ||
        unit == 0x200C ||
        unit == 0x200D ||
        unit == 0x200E ||
        unit == 0x200F ||
        unit == 0xFEFF) {
      continue;
    }
    // Look-alike decimal separators → ASCII period: ٫ ․ ．
    if (unit == 0x066B || unit == 0x2024 || unit == 0xFF0E) {
      buf.write('.');
      continue;
    }
    // Comma look-alikes → ASCII comma: ٬ ， ،
    if (unit == 0x066C || unit == 0xFF0C || unit == 0x060C) {
      buf.write(',');
      continue;
    }
    // Non-ASCII decimal digits → ASCII.
    var isDigit = false;
    for (final base in digitBases) {
      if (unit >= base && unit <= base + 9) {
        buf.writeCharCode(0x30 + (unit - base));
        isDigit = true;
        break;
      }
    }
    if (!isDigit) buf.writeCharCode(unit);
  }
  return buf.toString();
}

/// v24: unified share entry point. Accepts:
/// - `geo:` URIs,
/// - Google Maps URLs (`maps.google.com/?q=`, `google.com/maps/search/`,
///   `goo.gl/maps/…`, `maps.app.goo.gl/…` — short links are resolved
///   via HTTP redirects first),
/// - share-sheet text wrapping any of the above (first URL wins).
/// Returns null when nothing usable is found.
Future<GeoShareTarget?> parseShareInput(String raw) async {
  final text = _normalizeShareText(raw.trim());
  if (text.isEmpty) return null;
  final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(text);
  var candidate = (urlMatch?.group(0) ?? text).trim();
  // Strip trailing punctuation the share text may have glued on.
  candidate = candidate.replaceAll(RegExp(r'[.,;)\]]+$'), '');
  if (candidate.startsWith('geo:')) {
    return _rescueEmbeddedCoords(parseGeoUri(candidate));
  }
  if (_looksLikeMapsUrl(candidate)) {
    var finalUrl = candidate;
    final lower = candidate.toLowerCase();
    if (lower.contains('goo.gl') || lower.contains('maps.app.goo.gl')) {
      try {
        finalUrl = await _resolveShortLink(candidate)
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        finalUrl = candidate;
      }
    }
    final parsed = _parseGoogleMapsUrl(finalUrl);
    if (parsed != null) return _rescueEmbeddedCoords(parsed);
  }
  // v24.1: Flex-style free text: "customer address @ lat,lng".
  // The coordinates are the EXACT location (source of truth); the
  // customer's written address is only a label for the notes — it is
  // never geocoded or treated as the location when coords exist.
  return _extractCoordsFromText(text);
}

/// v27.7: some shares carry the exact coordinates INSIDE what the
/// structured parsers above see as a plain address label — Amazon Flex
/// sends `geo:0,0?q=<address @ lat,lng>`, where (0,0) means "no
/// coordinates" so the target comes back label-only and would be
/// geocoded as one raw string (which Nominatim can't resolve). Before
/// such a target falls through to geocoding, rescue an embedded
/// "lat,lng" pair from its label: the coordinates win (they are the
/// exact location), and the extractor's cleaned label — the address
/// with the "@ coords" residue stripped — is kept. Targets that
/// already have coordinates, and labels with no embedded pair, pass
/// through unchanged: a true address-only share still geocodes exactly
/// as before.
GeoShareTarget? _rescueEmbeddedCoords(GeoShareTarget? target) {
  if (target == null || target.hasCoords || target.label.isEmpty) {
    return target;
  }
  return _extractCoordsFromText(target.label) ?? target;
}

/// v24.1: extracts a "lat,lng" pair embedded in free text, e.g.
/// "شارع عبدالحليم محمود عمارة 15 الدور الاخير @ 29.987240,30.979383".
/// The remaining text becomes the label (customer's address).
/// Returns null when no valid coordinate pair is found.
GeoShareTarget? _extractCoordsFromText(String text) {
  final m =
      RegExp(r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)').firstMatch(text);
  if (m == null) return null;
  final lat = double.tryParse(m.group(1)!);
  final lng = double.tryParse(m.group(2)!);
  if (lat == null || lng == null) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  final label = ('${text.substring(0, m.start)} ${text.substring(m.end)}')
      .replaceAll(RegExp(r'[@\-–—:;،,]+'), ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  return GeoShareTarget(lat: lat, lng: lng, label: label);
}

/// Resolves a free-text address to coordinates via Nominatim
/// (OpenStreetMap). Returns null when the address can't be resolved.
Future<LatLng?> geocodeAddress(String address) async {
  final url = Uri.https('nominatim.openstreetmap.org', '/search', {
    'q': address,
    'format': 'json',
    'limit': '1',
  });
  final resp = await http.get(url, headers: {
    'User-Agent': 'DeliveryFlow/24 (com.valor.deliveryflow)',
  }).timeout(const Duration(seconds: 15));
  if (resp.statusCode != 200) return null;
  final list = jsonDecode(resp.body) as List<dynamic>;
  if (list.isEmpty) return null;
  final first = list.first as Map<String, dynamic>;
  final lat = double.tryParse('${first['lat']}');
  final lng = double.tryParse('${first['lon']}');
  if (lat == null || lng == null) return null;
  return LatLng(lat, lng);
}

/// v24: drops apartment/floor/building details that confuse geocoders
/// ("شقة 5"، "الدور الثالث"، "عمارة 12").
String _stripUnitDetails(String s) {
  var out = s;
  out = out.replaceAll(RegExp(r'شق[ةه]\s*\d+'), ' ');
  out = out.replaceAll(RegExp(r'(الدور|دور)\s*\S+'), ' ');
  out = out.replaceAll(RegExp(r'عمار[ةه]\s*\d+'), ' ');
  out = out.replaceAll(RegExp(r'\s{2,}'), ' ');
  out = out.trim().replaceAll(RegExp(r'^[,\s،]+|[,\s،]+$'), '');
  return out;
}

/// v24: geocoding with fallbacks — tries the raw address, then a
/// unit-detail-stripped variant, then ", Egypt" / ", مصر" suffixes.
Future<LatLng?> geocodeAddressSmart(String address) async {
  final queries = <String>[address];
  final stripped = _stripUnitDetails(address);
  if (stripped.isNotEmpty && stripped != address) queries.add(stripped);
  final hasEgypt = address.toLowerCase().contains('egypt') ||
      address.contains('مصر');
  if (!hasEgypt) {
    queries.add('$address, Egypt');
    if (stripped.isNotEmpty && stripped != address) {
      queries.add('$stripped, Egypt');
    }
    queries.add('$address, مصر');
  }
  for (final q in queries) {
    try {
      final r = await geocodeAddress(q);
      if (r != null) return r;
    } catch (_) {}
  }
  return null;
}

/// v24: Nominatim reverse-geocoding — human-readable address for
/// coordinates, used to auto-fill the order notes when a share has
/// coordinates but no label. Best effort: null on any failure.
Future<String?> reverseGeocode(LatLng pos) async {
  final url = Uri.https('nominatim.openstreetmap.org', '/reverse', {
    'lat': '${pos.latitude}',
    'lon': '${pos.longitude}',
    'format': 'json',
    'accept-language': 'ar,en',
  });
  try {
    final resp = await http.get(url, headers: {
      'User-Agent': 'DeliveryFlow/24 (com.valor.deliveryflow)',
    }).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final name = '${map['display_name'] ?? ''}'.trim();
    return name.isEmpty ? null : name;
  } catch (_) {
    return null;
  }
}

/// Full share-to-order flow: parse the shared payload (geo: URI or
/// Google Maps link/text), geocode when it only carries an address,
/// reverse-geocode when it only carries coordinates (so notes are
/// never empty), auto-create today's order, then open the navigation
/// screen on it so the OSRM route draws and live GPS tracking works
/// exactly like a manually created order.
///
/// Loud blocking dialog on any failure — the dialog always shows the
/// exact received text so the user can see what was shared. Never a
/// broken order, never silent.
Future<void> handleSharedGeoUri(
  BuildContext context,
  WidgetRef ref,
  String raw,
) async {
  final l10n = AppLocalizations.of(context);
  final appLog = ref.read(appLogServiceProvider);

  // v27.7: log the raw payload exactly as received (trimmed, capped)
  // so any future share variant is diagnosable from the in-app log.
  final rawReceived = raw.trim();
  appLog.info(
    AppLogCategory.share,
    'Share received',
    detail: rawReceived.length > 500
        ? '${rawReceived.substring(0, 500)}…'
        : rawReceived,
  );

  /// v24: failure dialog that SHOWS the exact received address/label
  /// text — never a dead-end message without it.
  /// v24.2: optional [reason] — a short technical note explaining WHY
  /// the share failed (parse vs geocode vs exception), so field
  /// failures can be diagnosed from a screenshot.
  Future<void> failWithReceived(String received, [String? reason]) async {
    if (!context.mounted) return;
    final shown = received.length > 500
        ? '${received.substring(0, 500)}…'
        : received;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      // Root navigator: the share can arrive while any tab is visible.
      // Popping uses the dialog's own context (ctx), so it always
      // targets the right navigator.
      useRootNavigator: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final text = Theme.of(ctx).textTheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: scheme.error, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.geoShareFailedWithLabelTitle)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.geoShareReceivedText,
                style: text.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  shown.isEmpty ? '—' : shown,
                  style: text.bodyMedium,
                ),
              ),
              if (reason != null && reason.isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText(
                  '${l10n.geoShareFailureReason}: $reason',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.55),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.ok),
            ),
          ],
        );
      },
    );
  }

  // v24: short-link resolution may take a moment — do it before any UI.
  final GeoShareTarget? target;
  try {
    target = await parseShareInput(raw);
  } catch (e) {
    appLog.error(
      AppLogCategory.share,
      'Share parse threw',
      error: e,
      detail: 'received: ${raw.trim()}',
    );
    await failWithReceived(raw.trim(), 'parse: $e');
    return;
  }
  if (target == null) {
    appLog.warn(
      AppLogCategory.share,
      'Share parse found no coords/address',
      detail: 'received: ${raw.trim()}',
    );
    await failWithReceived(raw.trim(), 'parse: no coords/address found');
    return;
  }

  final LatLng dest;
  var label = target.label;
  if (target.hasCoords) {
    dest = LatLng(target.lat!, target.lng!);
    if (label.isEmpty) {
      // v24: never leave notes empty when we have a location —
      // reverse-geocode a human-readable address; fall back to the
      // coordinates themselves when offline.
      label = await reverseGeocode(dest) ??
          '${dest.latitude.toStringAsFixed(5)}, '
              '${dest.longitude.toStringAsFixed(5)}';
    }
  } else {
    // Address-only share: brief blocking loader while geocoding.
    // v21: REAL staged progress — shown → sent → received → done.
    // The bar advances only on real stages and hits 1.0 as the dialog
    // dismisses. No looping, no faking.
    if (!context.mounted) return;
    final geoStages = LoadingStages(4);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            ValueListenableBuilder<double>(
              valueListenable: geoStages.progress,
              builder: (_, p, __) =>
                  DeliveryLoadingBar(width: 120, progress: p),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.geoPreparingOrder)),
          ],
        ),
      ),
    );
    geoStages.advance(); // dialog shown
    LatLng? geocoded;
    try {
      geoStages.advance(); // request sent
      // v24: smart geocoding with Egypt/unit-detail fallbacks.
      geocoded = await geocodeAddressSmart(target.label);
      geoStages.advance(); // response received
    } catch (e) {
      appLog.warn(
        AppLogCategory.share,
        'Geocoding threw',
        error: e,
        detail: 'label: ${target.label}',
      );
      geocoded = null;
    }
    if (context.mounted) {
      // Matches the useRootNavigator: true of the loader dialog above.
      Navigator.of(context, rootNavigator: true).pop();
    }
    geoStages.advance(); // done — exactly 1.0 as we move on
    geoStages.dispose();
    if (geocoded == null) {
      appLog.warn(
        AppLogCategory.share,
        'Geocode: address not found',
        detail: 'label: ${target.label}',
      );
      await failWithReceived(target.label, 'geocode: address not found');
      return;
    }
    dest = geocoded;
  }

  final db = ref.read(databaseServiceProvider);
  final now = DateTime.now();
  final dateKey = WeekCalendar.dateKey(now);
  final entry = await db.addOrderEntry(
    dateKey: dateKey,
    timestampMillis: now.millisecondsSinceEpoch,
    notes: label,
  );
  appLog.info(
    AppLogCategory.share,
    'Share handled: order ${entry.id} created for $dateKey '
    '(coords: ${target.hasCoords})',
  );
  bumpDataVersion(ref);
  if (!context.mounted) return;

  // v25 middleman mode: instead of the in-app NavigationScreen, the
  // order is auto-started (tracking begins immediately, exactly like
  // pressing "بدأ التوصيل") and Google Maps opens with the destination.
  // Tracking keeps recording the full round trip in the background;
  // the persistent tracking notification brings him back to the order
  // to press "وصلت للعميل" / "وصلت للمارت".
  final settings = ref.read(settingsProvider);
  if (settings.autoNavMode == 1) {
    await _startMiddlemanTrip(context, ref, l10n,
        dateKey: dateKey,
        entryId: entry.id,
        dest: dest,
        label: label,
        phone: entry.phone,
        personalSpeedKmh: db.personalAvgSpeedKmh());
    return;
  }

  final shortId = entry.id.length > 6
      ? entry.id.substring(entry.id.length - 6)
      : entry.id;
  // Root navigator: covers the whole shell (bottom nav included) no
  // matter which tab is visible; back returns exactly where he was.
  await Navigator.of(context, rootNavigator: true).push(
    SmoothPageRoute(
      builder: (_) => NavigationScreen(
        dateKey: dateKey,
        entryId: entry.id,
        shortOrderId: shortId,
        destination: dest,
        statusLine: l10n.onWayToCustomer,
        address: label,
        phone: entry.phone,
        // v21: blended ETA — 50% his own measured riding speed.
        personalSpeedKmh: db.personalAvgSpeedKmh(),
      ),
    ),
  );
}

/// v25 middleman mode: auto-starts background tracking for the shared
/// order (same as "بدأ التوصيل"), then opens Google Maps with the
/// destination. Never silent: a tracking failure shows a loud blocking
/// dialog and Google Maps is NOT opened (an untracked trip defeats the
/// purpose). If Google Maps itself can't open, falls back to the
/// in-app NavigationScreen.
Future<void> _startMiddlemanTrip(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n, {
  required String dateKey,
  required String entryId,
  required LatLng dest,
  required String label,
  required String phone,
  required double? personalSpeedKmh,
}) async {
  final svc = ref.read(deliveryTrackingServiceProvider);
  try {
    // v27.8: pass the destination so the background isolate can run
    // the arrival geofence for this leg.
    await svc.startOutgoing(
      dateKey: dateKey,
      entryId: entryId,
      destLat: dest.latitude,
      destLng: dest.longitude,
    );
  } catch (e) {
    ref.read(appLogServiceProvider).error(
          AppLogCategory.share,
          'Middleman trip start FAILED for shared order $entryId',
          error: e,
        );
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.trackingFailedTitle),
        content: Text(e is StateError ? e.message : e.toString()),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    return;
  }
  bumpDataVersion(ref);
  if (!context.mounted) return;
  final url = Uri.parse(
    'https://www.google.com/maps/dir/?api=1'
    '&destination=${dest.latitude},${dest.longitude}',
  );
  var opened = false;
  try {
    opened = await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    // Google Maps unavailable — fall back to in-app navigation so the
    // trip is never stranded without guidance.
    final shortId =
        entryId.length > 6 ? entryId.substring(entryId.length - 6) : entryId;
    await Navigator.of(context, rootNavigator: true).push(
      SmoothPageRoute(
        builder: (_) => NavigationScreen(
          dateKey: dateKey,
          entryId: entryId,
          shortOrderId: shortId,
          destination: dest,
          statusLine: l10n.onWayToCustomer,
          address: label,
          phone: phone,
          personalSpeedKmh: personalSpeedKmh,
        ),
      ),
    );
  }
}
