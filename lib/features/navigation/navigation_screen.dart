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

/// Map camera perspective modes for the navigation screen.
enum _MapMode {
  /// Classic north-up follow (v19 behavior).
  northUp,

  /// Heading-up: map rotates so the direction of travel points up.
  headingUp,

  /// Overview: whole active route fitted on screen, follow paused.
  overview,
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
  // Camera-follow mode: ON by default. A manual pan/zoom pauses it and
  // shows the recenter button; tapping the button resumes follow.
  bool _following = true;
  static const double _followZoom = 16.0;

  // ---- v20: alternative routes ----
  /// Up to 3 OSRM route alternatives for the current position.
  List<RouteDirections> _routes = [];

  /// Index of the user-selected (actively tracked) route.
  int _selectedRoute = 0;

  /// Indices of the fastest / shortest alternatives (for badges).
  int _fastestIdx = 0;
  int _shortestIdx = 0;

  /// Recommendation banner dismissed by the user (per screen open).
  bool _recDismissed = false;

  // ---- v20: map perspectives ----
  _MapMode _mapMode = _MapMode.northUp;
  _MapMode _modeBeforeOverview = _MapMode.northUp;

  /// Last stable GPS bearing (degrees clockwise from north). Only
  /// updated from GPS heading while actually moving, to avoid jitter
  /// when stopped.
  double _lastBearing = 0;

  /// MapOptions hoisted out of build: rebuilding it on every position
  /// update used to churn didUpdateWidget/setOptions on each GPS fix,
  /// which is what broke camera follow on-device.
  late final MapOptions _mapOptions = MapOptions(
    initialCenter: widget.destination,
    initialZoom: 14,
    onMapReady: () => _mapReady = true,
    onPositionChanged: (pos, hasGesture) {
      if (hasGesture && mounted) {
        if (_mapMode == _MapMode.overview) {
          // Any manual interaction leaves overview and goes back to
          // the previous perspective mode.
          setState(() => _mapMode = _modeBeforeOverview);
        } else if (_following) {
          setState(() => _following = false);
        }
      }
    },
    interactionOptions: const InteractionOptions(
      flags: InteractiveFlag.all,
    ),
  );

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
    // Stable bearing: trust GPS heading only while actually moving
    // (speed > 2 m/s); ignore tiny changes to avoid camera jitter.
    if (p.speed > 2 && p.heading >= 0 && p.heading <= 360) {
      if (_bearingDiff(p.heading, _lastBearing).abs() > 8) {
        _lastBearing = p.heading;
      }
    }
    setState(() {
      _current = pos;
      _locating = false;
    });
    // Continuous camera follow (fixed zoom), per perspective mode.
    // Guarded so a single failed move can never wedge the camera:
    // the next GPS fix retries.
    if (_following && _mapReady && _mapMode != _MapMode.overview) {
      try {
        if (_mapMode == _MapMode.headingUp) {
          // flutter_map rotation is degrees with 0° = North, so
          // rotation == bearing gives heading-up.
          _mapController.moveAndRotate(pos, _followZoom, _lastBearing);
        } else {
          _mapController.move(pos, _followZoom);
        }
      } catch (_) {}
    }
    if (first) await _refreshRoute();
  }

  /// Smallest signed difference between two bearings in degrees.
  double _bearingDiff(double a, double b) {
    var d = (a - b) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  void _recenter() {
    final cur = _current;
    if (cur == null || !mounted) return;
    setState(() => _following = true);
    if (_mapReady) {
      try {
        _mapController.move(cur, _followZoom);
      } catch (_) {}
    }
  }

  Future<void> _refreshRoute() async {
    final cur = _current;
    if (cur == null || !mounted) return;
    final alts = await _snap.fetchRouteAlternatives(
        from: cur, to: widget.destination);
    if (!mounted) return;
    setState(() {
      if (alts != null && alts.isNotEmpty) {
        final countChanged = alts.length != _routes.length;
        _routes = alts;
        _computeRouteStats();
        if (countChanged) {
          // New set of alternatives: auto-select the recommended one
          // (shortest = fuel saver).
          _selectedRoute = _shortestIdx;
        } else {
          // Keep the user's manual selection stable across refreshes.
          _selectedRoute = _selectedRoute.clamp(0, _routes.length - 1);
        }
        _applySelectedRoute();
      } else if (!_routeFailedNoteShown) {
        _routeFailedNoteShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context).navRouteFailed)),
        );
      }
    });
    // Keep overview fitted to the fresh geometry.
    if (_mapMode == _MapMode.overview && _mapReady && mounted) {
      _fitOverview();
    }
  }

  /// Finds the fastest (min duration) and shortest (min distance)
  /// alternative indices for badges + recommendation.
  void _computeRouteStats() {
    var fastest = 0;
    var shortest = 0;
    for (var i = 1; i < _routes.length; i++) {
      if (_routes[i].durationSec < _routes[fastest].durationSec) {
        fastest = i;
      }
      if (_routes[i].distanceKm < _routes[shortest].distanceKm) {
        shortest = i;
      }
    }
    _fastestIdx = fastest;
    _shortestIdx = shortest;
  }

  /// Applies the currently selected route to the drawn geometry and
  /// the bottom info card.
  void _applySelectedRoute() {
    final sel = _routes[_selectedRoute];
    _routePoints = sel.geometry;
    _remainingKm = sel.distanceKm;
    _etaMin = (sel.durationSec / 60).round();
  }

  /// User taps a route chip: make it the actively tracked route.
  void _selectRoute(int i) {
    if (i == _selectedRoute || i < 0 || i >= _routes.length) return;
    if (!mounted) return;
    setState(() {
      _selectedRoute = i;
      _applySelectedRoute();
    });
    if (_mapMode == _MapMode.overview && _mapReady) {
      _fitOverview();
    }
  }

  /// Cycles perspective: north-up -> heading-up -> overview -> north-up.
  void _cycleMapMode() {
    if (!mounted) return;
    setState(() {
      switch (_mapMode) {
        case _MapMode.northUp:
          _mapMode = _MapMode.headingUp;
          break;
        case _MapMode.headingUp:
          _modeBeforeOverview = _mapMode;
          _mapMode = _MapMode.overview;
          break;
        case _MapMode.overview:
          _mapMode = _modeBeforeOverview;
          break;
      }
    });
    _applyModeCamera();
  }

  /// Moves the camera immediately after a perspective switch.
  void _applyModeCamera() {
    final cur = _current;
    if (!_mapReady || cur == null || !mounted) return;
    try {
      switch (_mapMode) {
        case _MapMode.northUp:
          _mapController.rotate(0);
          if (_following) _mapController.move(cur, _followZoom);
          break;
        case _MapMode.headingUp:
          if (_following) {
            _mapController.moveAndRotate(cur, _followZoom, _lastBearing);
          } else {
            _mapController.rotate(_lastBearing);
          }
          break;
        case _MapMode.overview:
          _fitOverview();
          break;
      }
    } catch (_) {}
  }

  /// Fits the whole active route (+ scooter) on screen.
  void _fitOverview() {
    final pts = <LatLng>[..._routePoints];
    if (_current != null) pts.add(_current!);
    if (pts.length < 2 || !mounted) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts),
          padding: const EdgeInsets.all(56),
        ),
      );
    } catch (_) {}
  }

  /// Polylines: alternatives in grey underneath, the selected route in
  /// brand blue (#0A84FF), thicker, on top.
  List<Polyline> _routePolylines(BuildContext context) {
    final lines = <Polyline>[];
    final altColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35);
    for (var i = 0; i < _routes.length; i++) {
      if (i == _selectedRoute) continue;
      if (_routes[i].geometry.length < 2) continue;
      lines.add(Polyline(
        points: _routes[i].geometry,
        strokeWidth: 5,
        color: altColor,
      ));
    }
    if (_routePoints.length > 1) {
      lines.add(Polyline(
        points: _routePoints,
        strokeWidth: 7,
        color: LiquidPalette.primaryBlue,
      ));
    }
    return lines;
  }

  /// Badge shown on a route chip: fastest / shortest / both.
  String _routeBadge(int i) {
    final both = i == _fastestIdx && i == _shortestIdx;
    if (both) return '✅ ';
    if (i == _fastestIdx) return '⚡ ';
    if (i == _shortestIdx) return '⛽ ';
    return '';
  }

  /// Tappable ETA chips, one per alternative, near each route's
  /// midpoint. Tapping selects that route for tracking.
  List<Marker> _routeChipMarkers(
      BuildContext context, AppLocalizations l10n) {
    final markers = <Marker>[];
    final scheme = Theme.of(context).colorScheme;
    for (var i = 0; i < _routes.length; i++) {
      final geo = _routes[i].geometry;
      if (geo.length < 3) continue;
      final r = _routes[i];
      final mins = (r.durationSec / 60).round();
      final selected = i == _selectedRoute;
      markers.add(
        Marker(
          point: geo[geo.length ~/ 2],
          width: 170,
          height: 44,
          child: GestureDetector(
            onTap: () => _selectRoute(i),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: selected
                    ? LiquidPalette.primaryBlue
                    : scheme.surface.withValues(alpha: 0.95),
                border: Border.all(
                  color: selected
                      ? LiquidPalette.primaryBlue
                      : scheme.onSurface.withValues(alpha: 0.25),
                  width: selected ? 0 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${_routeBadge(i)}$mins ${l10n.minute} • '
                  '${r.distanceKm.toStringAsFixed(1)} ${l10n.kmUnit}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? Colors.white
                        : LiquidPalette.primaryBlue,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  IconData get _modeIcon {
    switch (_mapMode) {
      case _MapMode.northUp:
        return Icons.explore_outlined;
      case _MapMode.headingUp:
        return Icons.navigation_rounded;
      case _MapMode.overview:
        return Icons.map_rounded;
    }
  }

  String _modeLabel(AppLocalizations l10n) {
    switch (_mapMode) {
      case _MapMode.northUp:
        return l10n.mapModeNorthUp;
      case _MapMode.headingUp:
        return l10n.mapModeHeadingUp;
      case _MapMode.overview:
        return l10n.mapModeOverview;
    }
  }

  /// Recommendation banner text for the shortest (fuel-saver) route.
  /// Fuel saving is inferred from shorter distance, not measured.
  String _recommendationText(AppLocalizations l10n) {
    final rec = _routes[_shortestIdx];
    final km = rec.distanceKm.toStringAsFixed(1);
    final min = (rec.durationSec / 60).round().toString();
    if (_fastestIdx == _shortestIdx) {
      return l10n.routeRecommendBoth(km, min);
    }
    return l10n.routeRecommendShortest(km, min);
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
                  options: _mapOptions,
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.valor.deliveryflow',
                    ),
                    // Route alternatives: non-selected in grey underneath,
                    // selected in brand blue on top.
                    if (_routePoints.length > 1)
                      PolylineLayer(
                        polylines: _routePolylines(context),
                      ),
                    MarkerLayer(
                      markers: [
                        ..._routeChipMarkers(context, l10n),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const DeliveryLoadingBar(width: 170),
                    const SizedBox(height: 10),
                    Text(l10n.locatingYou),
                  ],
                ),
              ),
            ),
          // Recenter button: appears when the user pans/zooms manually
          // (follow paused); tapping resumes camera follow.
          if (!_following && _current != null && !_denied)
            Positioned(
              right: 16,
              bottom: 210,
              child: Pressable(
                onTap: _recenter,
                child: Tooltip(
                  message: l10n.recenter,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          Theme.of(context).scaffoldBackgroundColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: LiquidPalette.primaryBlue,
                    ),
                  ),
                ),
              ),
            ),
          // Perspective toggle: cycles north-up -> heading-up ->
          // overview. Always live, never a dead button.
          if (!_denied)
            Positioned(
              right: 16,
              bottom: 282,
              child: Pressable(
                onTap: _cycleMapMode,
                child: Tooltip(
                  message: _modeLabel(l10n),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      color:
                          Theme.of(context).scaffoldBackgroundColor,
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.black.withValues(alpha: 0.2),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _modeIcon,
                          size: 20,
                          color: LiquidPalette.primaryBlue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _modeLabel(l10n),
                          style: text.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: LiquidPalette.primaryBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Smart recommendation banner: fastest / shortest route.
          // Dismissible, never blocking.
          if (_routes.length >= 2 && !_recDismissed && !_denied)
            Positioned(
              top: MediaQuery.of(context).padding.top + 62,
              left: 16,
              right: 16,
              child: GlassCard(
                borderRadius: GlassTokens.radiusM,
                child: Row(
                  children: [
                    const Icon(
                      Icons.thumb_up_alt_rounded,
                      size: 20,
                      color: LiquidPalette.primaryBlue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _recommendationText(l10n),
                        style: text.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    Pressable(
                      onTap: () =>
                          setState(() => _recDismissed = true),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded, size: 18),
                      ),
                    ),
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
