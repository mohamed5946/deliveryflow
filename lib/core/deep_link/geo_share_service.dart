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

/// Result of parsing a geo: URI shared from another app
/// (e.g. navigation shared from the Amazon Flex driver app).
class GeoShareTarget {
  /// Coordinates when the URI carries them; null for address-only
  /// shares (those need geocoding first).
  final double? lat;
  final double? lng;

  /// Human label / address from the `q=` parameter (may be empty).
  final String label;

  const GeoShareTarget({this.lat, this.lng, this.label = ''});

  /// True when usable coordinates are present (0,0 counts as absent —
  /// it is the conventional "no coordinates" placeholder).
  bool get hasCoords =>
      lat != null && lng != null && !(lat == 0 && lng == 0);
}

/// Reads geo: VIEW intents captured by MainActivity, on cold start and
/// via onNewIntent while already running. Each URI is delivered exactly
/// once (the native side consumes it on read).
class GeoIntentReceiver {
  static const _channel =
      MethodChannel('com.valor.deliveryflow/nav_intent');

  /// Returns the pending geo: URI, or null when nothing was shared.
  Future<String?> takeNavUri() async {
    try {
      final uri = await _channel.invokeMethod<String>('getNavUri');
      if (uri == null || !uri.startsWith('geo:')) return null;
      return uri;
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

/// Resolves a free-text address to coordinates via Nominatim
/// (OpenStreetMap). Returns null when the address can't be resolved.
Future<LatLng?> geocodeAddress(String address) async {
  final url = Uri.https('nominatim.openstreetmap.org', '/search', {
    'q': address,
    'format': 'json',
    'limit': '1',
  });
  final resp = await http
      .get(url, headers: {
        'User-Agent': 'DeliveryFlow/19 (com.valor.deliveryflow)',
      })
      .timeout(const Duration(seconds: 15));
  if (resp.statusCode != 200) return null;
  final list = jsonDecode(resp.body) as List<dynamic>;
  if (list.isEmpty) return null;
  final first = list.first as Map<String, dynamic>;
  final lat = double.tryParse('${first['lat']}');
  final lng = double.tryParse('${first['lon']}');
  if (lat == null || lng == null) return null;
  return LatLng(lat, lng);
}

/// Full share-to-order flow: parse the geo: URI, geocode when it only
/// carries an address, auto-create today's order, then open the
/// navigation screen on it so the OSRM route draws and live GPS
/// tracking works exactly like a manually created order.
///
/// Loud blocking dialog on any failure — never a broken order, never
/// silent.
Future<void> handleSharedGeoUri(
  BuildContext context,
  WidgetRef ref,
  String raw,
) async {
  final l10n = AppLocalizations.of(context);

  Future<void> fail(String message) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      // Root navigator: the share can arrive while any tab is visible.
      // Popping uses the dialog's own context (ctx), so it always
      // targets the right navigator.
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: Theme.of(ctx).colorScheme.error, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(l10n.geoShareFailedTitle)),
          ],
        ),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  final target = parseGeoUri(raw);
  if (target == null) {
    await fail(l10n.geoShareFailedBody);
    return;
  }

  final LatLng dest;
  if (target.hasCoords) {
    dest = LatLng(target.lat!, target.lng!);
  } else {
    // Address-only share: brief blocking loader while geocoding.
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const DeliveryLoadingBar(width: 120),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.geoPreparingOrder)),
          ],
        ),
      ),
    );
    LatLng? geocoded;
    try {
      geocoded = await geocodeAddress(target.label);
    } catch (_) {
      geocoded = null;
    }
    if (context.mounted) {
      // Matches the useRootNavigator: true of the loader dialog above.
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (geocoded == null) {
      await fail(l10n.geoAddressNotFound);
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
    notes: target.label,
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
        address: target.label,
        phone: entry.phone,
      ),
    ),
  );
}
