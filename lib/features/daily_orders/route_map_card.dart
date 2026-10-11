import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/database/models.dart';
import '../../theme/design_system.dart';

/// Route map for a completed (or in-progress) order.
///
/// Shows:
/// - Mart marker (start & end point — same location)
/// - Customer marker (delivery point)
/// - Orange polyline: mart → customer (outgoing)
/// - Blue polyline: customer → mart (return)
///
/// Tiles load from OpenStreetMap and need internet; the recorded
/// route itself is stored offline.
class RouteMapCard extends StatelessWidget {
  final OrderEntry entry;

  const RouteMapCard({super.key, required this.entry});

  List<LatLng> _points(List<double> lat, List<double> lng) {
    final n = lat.length < lng.length ? lat.length : lng.length;
    return List.generate(n, (i) => LatLng(lat[i], lng[i]));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final outPoints = _points(entry.displayOutLat, entry.displayOutLng);
    final backPoints = _points(entry.displayBackLat, entry.displayBackLng);

    if (outPoints.isEmpty && backPoints.isEmpty) {
      return GlassCard(
        child: Row(
          children: [
            Icon(Icons.map_outlined,
                color: scheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l10n.noRouteData,
                  style: text.bodySmall?.copyWith(
                      color: scheme.onSurface
                          .withValues(alpha: 0.6))),
            ),
          ],
        ),
      );
    }

    final all = [...outPoints, ...backPoints];
    final bounds = LatLngBounds.fromPoints(all);
    final center = bounds.center;

    final markers = <Marker>[];
    if (outPoints.isNotEmpty) {
      // Mart = start.
      markers.add(_marker(
        outPoints.first,
        Icons.store_rounded,
        Colors.green,
        l10n.martLabel,
      ));
    }
    if (outPoints.isNotEmpty) {
      // Customer = end of outgoing leg.
      markers.add(_marker(
        outPoints.last,
        Icons.person_pin_rounded,
        Colors.orange,
        l10n.customerLabel,
      ));
    }
    if (backPoints.isNotEmpty) {
      // Mart again = end of return leg.
      markers.add(_marker(
        backPoints.last,
        Icons.store_rounded,
        Colors.green,
        l10n.martLabel,
      ));
    }

    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded,
                  size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(l10n.routeMapTitle,
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 260,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 14,
                  initialCameraFit: CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(40),
                  ),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.valor.deliveryflow',
                  ),
                  PolylineLayer(
                    polylines: [
                      if (outPoints.length > 1)
                        Polyline(
                          points: outPoints,
                          strokeWidth: 4,
                          color: Colors.orange,
                        ),
                      if (backPoints.length > 1)
                        Polyline(
                          points: backPoints,
                          strokeWidth: 4,
                          color: Colors.blue,
                        ),
                    ],
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _legendDot(Colors.orange, l10n.outgoingLegShort),
              const SizedBox(width: 16),
              _legendDot(Colors.blue, l10n.returnLegShort),
              const SizedBox(width: 16),
              _legendDot(Colors.green, l10n.martLabel),
            ],
          ),
        ],
      ),
    );
  }

  Marker _marker(
      LatLng point, IconData icon, Color color, String tooltip) {
    return Marker(
      point: point,
      width: 40,
      height: 40,
      child: Tooltip(
        message: tooltip,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 6,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
