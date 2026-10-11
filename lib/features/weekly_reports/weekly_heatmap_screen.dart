import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';

/// Weekly heatmap: visualizes the most-traveled roads and places.
///
/// Collects all recorded route points (snapped road geometry preferred)
/// from the current week's orders and renders them as overlapping
/// semi-transparent circles — areas with more overlap appear "hotter".
class WeeklyHeatmapScreen extends ConsumerWidget {
  const WeeklyHeatmapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final db = ref.watch(databaseServiceProvider);
    ref.watch(dataVersionProvider);
    final weekStart = WeekCalendar.weekStart(DateTime.now());

    // Collect all route points from this week's orders.
    final points = <LatLng>[];
    for (var i = 0; i < 7; i++) {
      final day = weekStart.add(Duration(days: i));
      final key = WeekCalendar.dateKey(day);
      final record = db.orderRecord(key);
      if (record == null) continue;
      for (final entry in record.entries) {
        if (!entry.isCompleted) continue;
        _addPoints(points, entry.displayOutLat, entry.displayOutLng);
        _addPoints(points, entry.displayBackLat, entry.displayBackLng);
      }
    }

    return GlassScaffold(
      appBar: AppBar(title: Text(l10n.weeklyHeatmap)),
      body: points.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined,
                        size: 64,
                        color:
                            scheme.onSurface.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text(l10n.noHeatmapData,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(
                            color: scheme.onSurface
                                .withValues(alpha: 0.6))),
                  ],
                ),
              ),
            )
          : Padding(
              padding: GlassTokens.screenPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GlassCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.local_fire_department_rounded,
                            color: Colors.red.shade400),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.heatmapSubtitle(points.length),
                            style: text.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: _centerOf(points),
                          initialZoom: 12,
                          interactionOptions:
                              const InteractionOptions(
                            flags: InteractiveFlag.all,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName:
                                'com.valor.deliveryflow',
                          ),
                          CircleLayer(
                            circles: points
                                .map((p) => CircleMarker(
                                      point: p,
                                      radius: 30,
                                      useRadiusInMeter: true,
                                      color: Colors.red.withValues(
                                          alpha: 0.12),
                                      borderStrokeWidth: 0,
                                    ))
                                .toList(),
                          ),
                          CircleLayer(
                            circles: points
                                .map((p) => CircleMarker(
                                      point: p,
                                      radius: 12,
                                      useRadiusInMeter: true,
                                      color: Colors.orange.withValues(
                                          alpha: 0.18),
                                      borderStrokeWidth: 0,
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _legend(context, l10n),
                ],
              ),
            ),
    );
  }

  void _addPoints(
      List<LatLng> out, List<double> lat, List<double> lng) {
    final n = lat.length < lng.length ? lat.length : lng.length;
    // Downsample for performance: max ~500 points per entry.
    final step = n > 500 ? (n / 500).ceil() : 1;
    for (var i = 0; i < n; i += step) {
      out.add(LatLng(lat[i], lng[i]));
    }
  }

  LatLng _centerOf(List<LatLng> points) {
    var latSum = 0.0, lngSum = 0.0;
    for (final p in points) {
      latSum += p.latitude;
      lngSum += p.longitude;
    }
    return LatLng(latSum / points.length, lngSum / points.length);
  }

  Widget _legend(BuildContext context, AppLocalizations l10n) {
    return GlassCard(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _legendItem(Colors.red.withValues(alpha: 0.5),
              l10n.heatmapHot),
          _legendItem(Colors.orange.withValues(alpha: 0.5),
              l10n.heatmapWarm),
          _legendItem(
              Colors.grey.withValues(alpha: 0.3), l10n.heatmapCold),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
