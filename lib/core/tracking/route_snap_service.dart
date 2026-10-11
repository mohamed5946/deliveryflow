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

/// Snaps a GPS breadcrumb trail to real roads using the free OSRM
/// public API.
///
/// Returns both the true road distance AND the road geometry (the
/// actual path on streets), so the map can draw the real driven
/// route instead of straight lines between sparse points.
///
/// Offline/no-internet: returns null, and the caller falls back to
/// the GPS-summed distance + raw trail.
class RouteSnapService {
  static const _base = 'https://router.project-osrm.org/route/v1/driving';

  Future<SnappedRoute?> snapRoute({
    required List<double> lat,
    required List<double> lng,
  }) async {
    final n = lat.length < lng.length ? lat.length : lng.length;
    if (n < 2) return null;

    // Downsample to keep the URL reasonable (OSRM handles ~100 points
    // fine). Keep first/last always for correct endpoints.
    final coords = <String>[];
    final step = n > 100 ? (n / 100).ceil() : 1;
    for (var i = 0; i < n; i += step) {
      coords.add('${lng[i]},${lat[i]}');
    }
    if ((n - 1) % step != 0) {
      coords.add('${lng[n - 1]},${lat[n - 1]}');
    }

    final url = Uri.parse(
        '$_base/${coords.join(';')}?overview=full&geometries=geojson');
    try {
      final res = await http
          .get(url, headers: {'User-Agent': 'DeliveryFlow/1.0'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final body = json.decode(res.body) as Map<String, dynamic>;
      if (body['code'] != 'Ok') return null;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final route = routes.first as Map<String, dynamic>;
      final meters = (route['distance'] as num?)?.toDouble();
      if (meters == null || meters <= 0) return null;

      // Extract the road geometry (list of [lng, lat] pairs).
      final geometry = <LatLng>[];
      try {
        final geoJson = route['geometry'] as Map<String, dynamic>?;
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

      return SnappedRoute(
        distanceKm: meters / 1000.0,
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
}
