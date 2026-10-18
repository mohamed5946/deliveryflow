import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../features/navigation/navigation_screen.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/design_system.dart';
import '../../theme/page_transitions.dart';
import '../date_time/week_calendar.dart';
import '../providers.dart';

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
      label = Uri.decodeComponent(kv[1].replaceAll('+', ' ')).trim();
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
        label = Uri.decodeComponent(placeMatch.group(1)!)
            .replaceAll('+', ' ')
            .replaceAll('_', ' ')
            .trim();
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
    final v = Uri.decodeComponent(searchMatch.group(1)!)
        .replaceAll('+', ' ')
        .trim();
    if (v.isNotEmpty) return _coordsOrLabel(v);
  }

  // /place/<name> without coordinates — geocode the name.
  final placeOnly = RegExp(r'/place/([^/?#@]+)').firstMatch(uri.path);
  if (placeOnly != null) {
    final v = Uri.decodeComponent(placeOnly.group(1)!)
        .replaceAll('+', ' ')
        .replaceAll('_', ' ')
        .trim();
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

/// v24: unified share entry point. Accepts:
/// - `geo:` URIs,
/// - Google Maps URLs (`maps.google.com/?q=`, `google.com/maps/search/`,
///   `goo.gl/maps/…`, `maps.app.goo.gl/…` — short links are resolved
///   via HTTP redirects first),
/// - share-sheet text wrapping any of the above (first URL wins).
/// Returns null when nothing usable is found.
Future<GeoShareTarget?> parseShareInput(String raw) async {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(text);
  var candidate = (urlMatch?.group(0) ?? text).trim();
  // Strip trailing punctuation the share text may have glued on.
  candidate = candidate.replaceAll(RegExp(r'[.,;)\]]+$'), '');
  if (candidate.startsWith('geo:')) return parseGeoUri(candidate);
  if (!_looksLikeMapsUrl(candidate)) return null;
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
  return _parseGoogleMapsUrl(finalUrl);
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

  /// v24: failure dialog that SHOWS the exact received address/label
  /// text — never a dead-end message without it.
  Future<void> failWithReceived(String received) async {
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
  } catch (_) {
    await failWithReceived(raw.trim());
    return;
  }
  if (target == null) {
    await failWithReceived(raw.trim());
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
    } catch (_) {
      geocoded = null;
    }
    if (context.mounted) {
      // Matches the useRootNavigator: true of the loader dialog above.
      Navigator.of(context, rootNavigator: true).pop();
    }
    geoStages.advance(); // done — exactly 1.0 as we move on
    geoStages.dispose();
    if (geocoded == null) {
      await failWithReceived(target.label);
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
  bumpDataVersion(ref);
  if (!context.mounted) return;

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
