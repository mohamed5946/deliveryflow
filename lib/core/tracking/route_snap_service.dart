import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Result of snapping a GPS trail to roads.
class SnappedRoute {
  /// Road distance in km.
  final double distanceKm;

  /// The actual road path (follows streets like Google Maps).
  final List<LatLng> geometry;

  const SnappedRoute({
    required this.distanceKm,
    required this.geometry,
  });
}

/// Point-to-point driving directions (the route you SHOULD take from
/// A to B). This is the correct use of the /route endpoint — unlike
/// trip finalization, which must use /match on the traveled trail.
class RouteDirections {
  /// Road distance in km.
  final double distanceKm;

  /// Duration in seconds.
  final double durationSec;

  /// Road geometry (list of [lng, lat] converted to LatLng).
  final List<LatLng> geometry;

  const RouteDirections({
    required this.distanceKm,
    required this.durationSec,
    required this.geometry,
  });
}

/// Snaps a GPS breadcrumb trail to real roads using the free OSRM
/// **map-matching** API (`/match/v1/driving`).
///
/// This measures the road distance of the route ACTUALLY traveled —
/// it snaps the recorded trace onto streets. It must NOT use the
/// `/route` (directions) endpoint: that computes the "ideal" route
/// through the waypoints and invents huge detours between noisy
/// points, massively inflating the distance.
///
/// Returns both the true road distance AND the road geometry (the
/// actual path on streets), so the map can draw the real driven
/// route instead of straight lines between sparse points.
///
/// Offline/no-internet/match failure: returns null, and the caller
/// falls back to the GPS-summed distance + raw trail.
class RouteSnapService {
  static const _base = 'https://router.project-osrm.org/match/v1/driving';

  Future<SnappedRoute?> snapRoute({
    required List<double> lat,
    required List<double> lng,
  }) async {
    final n = lat.length < lng.length ? lat.length : lng.length;
    if (n < 2) return null;

    // Downsample to keep the URL reasonable. Keep first/last always
    // for correct endpoints.
    final coords = <String>[];
    final step = n > 100 ? (n / 100).ceil() : 1;
    for (var i = 0; i < n; i += step) {
      coords.add('${lng[i]},${lat[i]}');
    }
    if ((n - 1) % step != 0) {
      coords.add('${lng[n - 1]},${lat[n - 1]}');
    }

    // radiuses: how far (meters) each trace point may be snapped.
    // Tolerates normal GPS noise without inventing detours.
    final radiuses = List.filled(coords.length, '50').join(';');

    final url = Uri.parse(
        '$_base/${coords.join(';')}?overview=full&geometries=geojson&radiuses=$radiuses');
    try {
      final res = await http
          .get(url, headers: {'User-Agent': 'DeliveryFlow/1.0'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final body = json.decode(res.body) as Map<String, dynamic>;
      if (body['code'] != 'Ok') return null;
      final matchings = body['matchings'] as List?;
      if (matchings == null || matchings.isEmpty) return null;

      // A trace with gaps comes back as several matchings — sum them
      // all and concatenate their geometries.
      double totalMeters = 0;
      final geometry = <LatLng>[];
      for (final m in matchings) {
        final matching = m as Map<String, dynamic>;
        totalMeters +=
            (matching['distance'] as num?)?.toDouble() ?? 0;
        try {
          final geoJson =
              matching['geometry'] as Map<String, dynamic>?;
          final coordsList = geoJson?['coordinates'] as List?;
          if (coordsList != null) {
            for (final c in coordsList) {
              final pair = c as List;
              geometry.add(LatLng(
                (pair[1] as num).toDouble(),
                (pair[0] as num).toDouble(),
              ));
            }
          }
        } catch (_) {}
      }
      if (totalMeters <= 0) return null;

      return SnappedRoute(
        distanceKm: totalMeters / 1000.0,
        geometry: geometry,
      );
    } catch (_) {
      return null;
    }
  }

  /// Backwards-compatible: distance only.
  Future<double?> snappedDistanceKm({
    required List<double> lat,
    required List<double> lng,
  }) async {
    final r = await snapRoute(lat: lat, lng: lng);
    return r?.distanceKm;
  }

  static const _routeBase =
      'https://router.project-osrm.org/route/v1/driving';

  /// Point-to-point driving directions from [from] to [to], with
  /// ALTERNATIVES (`alternatives=true`).
  ///
  /// Returns up to 3 routes, each with its own duration / distance /
  /// geometry. Used by the navigation screen to show route choices with
  /// ETAs. Same single-request volume as [fetchDirections] — just one
  /// extra query flag.
  ///
  /// Returns null when the request fails (caller shows the loud
  /// failure notice, per app convention — never silent).
  Future<List<RouteDirections>?> fetchRouteAlternatives({
    required LatLng from,
    required LatLng to,
  }) async {
    final url = Uri.parse(
        '$_routeBase/${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson&alternatives=true');
    try {
      final res = await http
          .get(url, headers: {'User-Agent': 'DeliveryFlow/1.0'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = json.decode(res.body) as Map<String, dynamic>;
      if (body['code'] != 'Ok') return null;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final out = <RouteDirections>[];
      for (final r in routes.take(3)) {
        final route = r as Map<String, dynamic>;
        final meters = (route['distance'] as num?)?.toDouble();
        final seconds = (route['duration'] as num?)?.toDouble();
        if (meters == null || meters <= 0) continue;
        final geometry = <LatLng>[];
        try {
          final geoJson =
              route['geometry'] as Map<String, dynamic>?;
          final coordsList = geoJson?['coordinates'] as List?;
          if (coordsList != null) {
            for (final c in coordsList) {
              final pair = c as List;
              geometry.add(LatLng(
                (pair[1] as num).toDouble(),
                (pair[0] as num).toDouble(),
              ));
            }
          }
        } catch (_) {}
        out.add(RouteDirections(
          distanceKm: meters / 1000.0,
          durationSec: seconds ?? 0,
          geometry: geometry,
        ));
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  /// Point-to-point driving directions from [from] to [to].
  ///
  /// Used ONLY for in-app navigation preview (show the road you should
  /// take). Never for trip finalization — that must use [snapRoute]
  /// (map matching) on the actually traveled trail.
  Future<RouteDirections?> fetchDirections({
    required LatLng from,
    required LatLng to,
  }) async {
    final alts = await fetchRouteAlternatives(from: from, to: to);
    if (alts == null || alts.isEmpty) return null;
    return alts.first;
  }
}
