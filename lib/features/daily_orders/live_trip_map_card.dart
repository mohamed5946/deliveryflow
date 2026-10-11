import 'dart:async';

import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/tracking/delivery_tracking_service.dart';
import '../../theme/design_system.dart';

/// Live mini-map for an actively tracked trip.
///
/// Reads the background isolate's progress file (`tracking_<orderId>.json`)
/// every 5 seconds and draws the traveled route as a polyline plus a
/// current-position marker. Works even when the app was reopened mid-trip,
/// because the file is written by the background isolate independently of
/// the main isolate's lifetime.
///
/// Updates are cheap: a 5s timer that only rebuilds when the km or the
/// point count actually changed.
class LiveTripMapCard extends ConsumerStatefulWidget {
  final String entryId;
  final bool isOutgoing;

  const LiveTripMapCard({
    super.key,
    required this.entryId,
    required this.isOutgoing,
  });

  @override
  ConsumerState<LiveTripMapCard> createState() => _LiveTripMapCardState();
}

class _LiveTripMapCardState extends ConsumerState<LiveTripMapCard> {
  Timer? _timer;
  LiveTripProgress? _progress;
  double _lastKm = -1;
  int _lastPoints = -1;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _tick(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    final svc = ref.read(deliveryTrackingServiceProvider);
    final p = await svc.readLiveProgress(widget.entryId);
    if (!mounted) return;
    final km = p?.km ?? -1;
    final points = p?.pointCount ?? -1;
    // Only rebuild when something actually changed.
    if (km != _lastKm || points != _lastPoints) {
      setState(() {
        _progress = p;
        _lastKm = km;
        _lastPoints = points;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final progress = _progress;
    final lineColor =
        widget.isOutgoing ? Colors.orange : Colors.blue;

    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LiveDot(color: lineColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.liveTripMapTitle,
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (progress != null)
                Text(
                  '${progress.km.toStringAsFixed(2)} ${l10n.kmUnit}',
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: lineColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 220,
              child: _buildMap(context, progress, lineColor, l10n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(BuildContext context, LiveTripProgress? progress,
      Color lineColor, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final n = progress?.pointCount ?? 0;
    if (progress == null || n == 0) {
      return Container(
        color: scheme.surface.withValues(alpha: 0.4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.waitingForGps,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      );
    }

    final points = List<LatLng>.generate(
      n,
      (i) => LatLng(progress.lat[i], progress.lng[i]),
    );
    final current = points.last;

    return FlutterMap(
      options: MapOptions(
        initialCenter: current,
        initialZoom: 15,
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
            if (points.length > 1)
              Polyline(
                points: points,
                strokeWidth: 5,
                color: lineColor,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: current,
              width: 44,
              height: 44,
              child: Container(
                decoration: BoxDecoration(
                  color: lineColor,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.navigation_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Small dot that actually pulses (repeating fade in/out).
class _LiveDot extends StatefulWidget {
  final Color color;

  const _LiveDot({required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.35,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
        ),
      ),
    );
  }
}
