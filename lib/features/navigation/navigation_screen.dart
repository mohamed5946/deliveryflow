import 'dart:async';

import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/tracking/route_snap_service.dart';
import '../../theme/design_system.dart';
import '../../theme/pressable.dart';
import '../daily_orders/phone_sheet.dart';

/// In-app navigation ("التوصيل الآن") — replaces the old external
/// Google Maps intent. Full-screen map with the courier's live
/// position (camera follows), the OSRM driving route to the customer
/// drawn in brand blue, and a bottom info card like the mockup.
///
/// The /route endpoint is CORRECT here (point-A-to-point-B
/// directions). Trip finalization still uses /match — untouched.
class NavigationScreen extends StatefulWidget {
  final String dateKey;
  final String entryId;
  final String shortOrderId;
  final LatLng destination;
  final String statusLine;
  final String address;
  final String phone;

  const NavigationScreen({
    super.key,
    required this.dateKey,
    required this.entryId,
    required this.shortOrderId,
    required this.destination,
    required this.statusLine,
    required this.address,
    required this.phone,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final MapController _mapController = MapController();
  final RouteSnapService _snap = RouteSnapService();
  StreamSubscription<Position>? _posSub;
  Timer? _routeTimer;
  LatLng? _current;
  List<LatLng> _routePoints = [];
  double? _remainingKm;
  int? _etaMin;
  bool _locating = true;
  bool _denied = false;
  bool _mapReady = false;
  bool _routeFailedNoteShown = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onPosition, onError: (_) {});
    // Refresh the route periodically as the courier moves.
    _routeTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _refreshRoute());
  }

  Future<void> _onPosition(Position p) async {
    final pos = LatLng(p.latitude, p.longitude);
    final first = _current == null;
    if (!mounted) return;
    setState(() {
      _current = pos;
      _locating = false;
    });
    if (_mapReady) {
      _mapController.move(pos, first ? 16.0 : _mapController.camera.zoom);
    }
    if (first) await _refreshRoute();
  }

  Future<void> _refreshRoute() async {
    final cur = _current;
    if (cur == null || !mounted) return;
    final dir = await _snap.fetchDirections(from: cur, to: widget.destination);
    if (!mounted) return;
    setState(() {
      if (dir != null) {
        _routePoints = dir.geometry;
        _remainingKm = dir.distanceKm;
        _etaMin = (dir.durationSec / 60).round();
      } else if (!_routeFailedNoteShown) {
        _routeFailedNoteShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context).navRouteFailed)),
        );
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _routeTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Pressable(
          scaleOnly: true,
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 10,
                ),
              ],
            ),
            child: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        title: Text(l10n.navigatingNow,
            style:
                text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const AuroraBackground(),
          if (_denied)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.locationPermissionRequired,
                    textAlign: TextAlign.center),
              ),
            )
          else
            Positioned.fill(
              child: RepaintBoundary(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: widget.destination,
                    initialZoom: 14,
                    onMapReady: () => _mapReady = true,
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
                    if (_routePoints.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            strokeWidth: 6,
                            color: LiquidPalette.primaryBlue,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        // Destination pin.
                        Marker(
                          point: widget.destination,
                          width: 44,
                          height: 44,
                          child: const Icon(
                            Icons.location_pin,
                            color: LiquidPalette.primaryBlue,
                            size: 44,
                          ),
                        ),
                        // Live courier position.
                        if (_current != null)
                          Marker(
                            point: _current!,
                            width: 52,
                            height: 52,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: LiquidPalette.primaryBlue,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.3),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.delivery_dining_rounded,
                                color: LiquidPalette.primaryBlue,
                                size: 26,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_locating && !_denied)
            Center(
              child: GlassCard(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(l10n.locatingYou),
                  ],
                ),
              ),
            ),
          // Bottom info card like the mockup.
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: _infoCard(context, l10n, text),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(
      BuildContext context, AppLocalizations l10n, TextTheme text) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      borderRadius: GlassTokens.radiusL,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LiquidPalette.brandGradientLg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('#${widget.shortOrderId}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.statusLine,
                    style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: LiquidPalette.primaryBlue)),
              ),
            ],
          ),
          if (widget.address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_rounded,
                    size: 16, color: LiquidPalette.primaryBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(widget.address,
                      style: text.bodySmall?.copyWith(
                          color: scheme.onSurface
                              .withValues(alpha: 0.75)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _chip(Icons.route_rounded,
                  _remainingKm == null ? '–' : '${_remainingKm!.toStringAsFixed(1)} ${l10n.kmUnit}'),
              const SizedBox(width: 8),
              _chip(Icons.schedule_rounded,
                  _etaMin == null ? '–' : '$_etaMin ${l10n.minute}'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GlassButton(
                  label: l10n.showDetails,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              if (widget.phone.isNotEmpty) ...[
                const SizedBox(width: 10),
                Pressable(
                  onTap: () =>
                      showCustomerPhoneSheet(context, widget.phone),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LiquidPalette.brandGradientLg,
                      boxShadow: [
                        BoxShadow(
                          color: LiquidPalette.primaryBlue
                              .withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.call_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String value) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: LiquidPalette.primaryBlue.withValues(alpha: 0.10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: LiquidPalette.primaryBlue),
          const SizedBox(width: 5),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: LiquidPalette.primaryBlue)),
        ],
      ),
    );
  }
}
