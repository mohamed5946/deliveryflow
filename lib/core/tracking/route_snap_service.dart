import 'dart:convert';

import 'package:http/http.dart' as http;

/// Snaps a GPS breadcrumb trail to real roads using the free OSRM
/// public API and returns the true road distance.
///
/// Why: raw GPS distance sums straight lines between fixes, which cuts
/// corners on winding roads and undercounts (user saw 2.0 km for a
/// real 2.8 km trip). OSRM matches the points to the road network and
/// returns the driven distance, like Google Maps.
///
/// Offline/no-internet: throws, and the caller falls back to the
/// GPS-summed distance.
class RouteSnapService {
  static const _base = 'https://router.project-osrm.org/route/v1/driving';

  /// Returns road distance in km for the given trail, or null when the
  /// trail is too short / the service is unreachable.
  Future<double?> snappedDistanceKm({
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
        '$_base/${coords.join(';')}?overview=false&geometries=geojson');
    try {
      final res = await http
          .get(url, headers: {'User-Agent': 'DeliveryFlow/1.0'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = json.decode(res.body) as Map<String, dynamic>;
      if (body['code'] != 'Ok') return null;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final meters = (routes.first['distance'] as num?)?.toDouble();
      if (meters == null || meters <= 0) return null;
      return meters / 1000.0;
    } catch (_) {
      return null;
    }
  }
}
