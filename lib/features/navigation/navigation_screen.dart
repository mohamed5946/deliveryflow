import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/tracking/route_snap_service.dart';
import '../../core/offline_maps/offline_map_service.dart';
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

  /// The courier's own average riding speed (km/h) measured from his
  /// completed trip history, or null when there is no history yet.
  /// Used to blend the ETA: 50% personal speed + 50% server estimate.
  final double? personalSpeedKmh;

  const NavigationScreen({
    super.key,
    required this.dateKey,
    required this.entryId,
    required this.shortOrderId,
    required this.destination,
    required this.statusLine,
    required this.address,
    required this.phone,
    this.personalSpeedKmh,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

/// Map camera perspective modes for the navigation screen.
enum _MapMode {
  /// Classic north-up follow (v19 behavior).
  northUp,

  /// Heading-up: map rotates so the direction of travel points up,
  /// scooter framed at the lower third like Google Maps navigation.
  headingUp,

  /// Follow cam (v24 "منظور المتابعة"): heading-up rotation, but the
  /// camera aims ~50m ahead of the scooter along the GPS bearing, so
  /// the scooter marker renders BELOW screen center with more of the
  /// road ahead visible. 2D only, no tilt.
  followCam,

  /// Overview: whole active route fitted on screen, follow paused.
  overview,
}

class _NavigationScreenState extends State<NavigationScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final RouteSnapService _snap = RouteSnapService();
  StreamSubscription<Position>? _posSub;
  Timer? _routeTimer;
  LatLng? _current;
  List<LatLng> _routePoints = [];
  double? _remainingKm;
  int? _etaMin;
  bool _denied = false;
  bool _mapReady = false;
  bool _routeFailedNoteShown = false;
  // Camera-follow mode: ON by default. A manual pan/zoom pauses it and
  // shows the recenter button; tapping the button resumes follow.
  bool _following = true;
  static const double _followZoom = 16.0;

  // ---- v21: Google-Maps-style nav camera ----
  /// Camera glide animation: smooth follow on every GPS fix, no jumps.
  AnimationController? _camAnim;

  // ---- v22: map-lag fix ("الخريطة بتعلق") ----
  /// Live scooter position. Updated on EVERY GPS fix WITHOUT setState —
  /// only the scooter marker (a ValueListenableBuilder) rebuilds, never
  /// the whole screen. The camera moves via the MapController directly.
  final ValueNotifier<LatLng?> _positionN = ValueNotifier<LatLng?>(null);

  /// Last automatic camera-glide start (epoch ms) for the 900ms throttle.
  int _lastCamMoveMs = 0;

  /// Throttle for automatic camera glides: at most one per 900ms. GPS
  /// fixes arrive ~2x/sec at riding speed (distanceFilter 5m); firing a
  /// new 450ms glide animation on every fix queued overlapping animations
  /// and was the main visible stutter. User-initiated moves (recenter,
  /// perspective switch) bypass the throttle.

  // ---- v21: off-route auto re-route ----
  /// Non-blocking "recalculating" pill state.
  bool _rerouting = false;

  /// Consecutive GPS fixes >60m off the active route.
  int _deviationCount = 0;

  /// Throttle: at most one automatic re-route per 30s.
  DateTime? _lastRerouteAt;

  // ---- v21: real staged nav loading ----
  /// 0.25 permission OK → 0.5 first GPS fix → 0.75 route request sent →
  /// 1.0 route drawn. Advances ONLY on real stages, never by timer.
  double _navProgress = 0;

  /// True once the first route is drawn (or its loud failure shown).
  bool _routeReady = false;

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
  // v21: heading-up is the DEFAULT (Google-Maps-style nav camera).
  _MapMode _mapMode = _MapMode.headingUp;
  _MapMode _modeBeforeOverview = _MapMode.headingUp;

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
    // v21 stage 1/4: permission + location service OK.
    if (mounted) setState(() => _navProgress = 0.25);
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
    _current = pos;
    // v22: scoped rebuild — only the scooter marker listens to this
    // notifier, never the whole screen (this was the map-lag root cause:
    // a full-screen setState on every GPS fix, ~2x/sec at riding speed).
    _positionN.value = pos;
    // v21 stage 2/4: first real GPS fix acquired (screen-level state).
    if (first && mounted) setState(() => _navProgress = 0.5);
    // Continuous camera follow per perspective mode (v21: smooth glide,
    // v22: throttled to one glide per 900ms).
    _updateFollowCamera(pos);
    // v21: off-route detection → automatic re-route.
    _checkDeviation(pos, p.speed);
    if (first) await _refreshRoute(initial: true);
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
    _updateFollowCamera(cur, immediate: true);
  }

  /// v24: "Open in Google Maps" fallback — opens the current destination
  /// in Google Maps via url_launcher. In-app navigation stays primary;
  /// this never throws and never breaks the screen when the launch
  /// fails (e.g. no Maps installed) — it simply does nothing.
  Future<void> _openInGoogleMaps() async {
    final d = widget.destination;
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${d.latitude},${d.longitude}',
    );
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ---- v21: Google-Maps-style nav camera ----

  /// Moves the camera for the current perspective mode. Called on every
  /// accepted GPS fix while following, on recenter, and on perspective
  /// switches. Never throws: a failed move is retried on the next fix.
  ///
  /// v22: automatic (per-fix) glides are throttled to one per 900ms —
  /// overlapping 450ms animations were the main map stutter. Pass
  /// [immediate] for user-initiated moves (recenter) that must not wait.
  void _updateFollowCamera(LatLng pos, {bool immediate = false}) {
    if (!_following || !_mapReady || !mounted) return;
    if (_mapMode == _MapMode.overview) return;
    if (!immediate) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastCamMoveMs < 900) return;
      _lastCamMoveMs = now;
    }
    try {
      if (_mapMode == _MapMode.headingUp) {
        // flutter_map rotation is degrees with 0° = North, so
        // rotation == bearing gives heading-up.
        _glideCamera(_headingUpTarget(pos, _lastBearing), _followZoom,
            _lastBearing);
      } else if (_mapMode == _MapMode.followCam) {
        // v24 follow cam: same heading-up rotation, camera aimed ahead.
        _glideCamera(
            _followCamTarget(pos, _lastBearing), _followZoom, _lastBearing);
      } else {
        // North-up keeps whatever rotation the map currently has.
        double rot = 0;
        try {
          rot = _mapController.camera.rotation;
        } catch (_) {}
        _glideCamera(pos, _followZoom, rot);
      }
    } catch (_) {}
  }

  /// Heading-up framing (v21.1): the scooter renders at the vertical
  /// center of the screen. v21 aimed the camera at a point ahead of the
  /// scooter (~68% down the screen), but the bottom order card + nav bar
  /// covered the scooter there ("المتسيكل مستخبي تحت"). Aiming directly
  /// at the scooter puts it at true screen center (50%), safely above
  /// the bottom card. Heading-up rotation is applied by the caller.
  LatLng _headingUpTarget(LatLng pos, double bearing) => pos;

  /// Follow-cam framing (v24): the scooter renders below screen center
  /// so more of the road ahead is visible. With heading-up rotation
  /// (rotation == bearing), aiming the camera at a point AHEAD of the
  /// scooter along the bearing pushes the scooter marker below center.
  /// The v21.1 lesson holds: the marker must never hide behind the
  /// bottom order card, so the aim point stays above the scooter on
  /// screen, never at it.
  ///
  /// The forward offset scales with zoom: ~50m at city zoom (16),
  /// doubling per zoom-out step so the framing stays proportional.
  LatLng _followCamTarget(LatLng pos, double bearing) {
    double zoom = _followZoom;
    try {
      zoom = _mapController.camera.zoom;
    } catch (_) {}
    final double meters = (50 * math.pow(2, 16 - zoom)).toDouble();
    final rad = bearing * math.pi / 180;
    const mPerDegLat = 111320.0;
    final dLat = meters * math.cos(rad) / mPerDegLat;
    final dLng = meters *
        math.sin(rad) /
        (mPerDegLat * math.cos(pos.latitude * math.pi / 180).abs().clamp(0.2, 1));
    return LatLng(pos.latitude + dLat, pos.longitude + dLng);
  }

  /// Glides the camera to [target] over ~450ms instead of jumping.
  /// Rotation takes the shortest arc. A new GPS fix restarts the glide
  /// from the current camera state, so motion stays continuous.
  void _glideCamera(LatLng target, double zoom, double rotation) {
    if (!_mapReady || !mounted) return;
    try {
      final cam = _mapController.camera;
      final fromC = cam.center;
      final fromR = cam.rotation;
      var dR = (rotation - fromR) % 360;
      if (dR > 180) dR -= 360;
      if (dR < -180) dR += 360;
      _camAnim?.dispose();
      final anim = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 450),
      );
      _camAnim = anim;
      anim.addListener(() {
        if (!mounted) return;
        final t = Curves.easeOut.transform(anim.value);
        final lat =
            fromC.latitude + (target.latitude - fromC.latitude) * t;
        final lng =
            fromC.longitude + (target.longitude - fromC.longitude) * t;
        try {
          _mapController.moveAndRotate(
              LatLng(lat, lng), zoom, fromR + dR * t);
        } catch (_) {}
      });
      anim.forward();
    } catch (_) {
      try {
        _mapController.moveAndRotate(target, zoom, rotation);
      } catch (_) {}
    }
  }

  // ---- v21: off-route auto re-route ----

  /// Minimum distance (meters) from [p] to the active route polyline,
  /// via point-to-segment projection (equirectangular — accurate well
  /// under 1 km, and we only care about the 60 m threshold).
  double _distanceToRoute(LatLng p) {
    double minD = double.infinity;
    final pts = _routePoints;
    final latR = p.latitude * math.pi / 180;
    final cosLat = math.cos(latR);
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final ax = (a.longitude - p.longitude) * cosLat;
      final ay = a.latitude - p.latitude;
      final bx = (b.longitude - p.longitude) * cosLat;
      final by = b.latitude - p.latitude;
      final abx = bx - ax, aby = by - ay;
      final denom = abx * abx + aby * aby;
      var t = denom == 0 ? 0.0 : -((ax * abx + ay * aby) / denom);
      t = t.clamp(0.0, 1.0);
      final cx = ax + abx * t, cy = ay + aby * t;
      final mx = cx * 111320 * cosLat;
      final my = cy * 110540;
      final dist = math.sqrt(mx * mx + my * my);
      if (dist < minD) minD = dist;
    }
    return minD;
  }

  /// Off-route detection: more than 60 m from the active route for 3
  /// fixes in a row (while actually moving) triggers one automatic
  /// re-route from the current position. Throttled to one re-route
  /// per 30 s so OSRM is never spammed.
  void _checkDeviation(LatLng pos, double speed) {
    if (_routePoints.length < 2 || _rerouting || speed <= 2) return;
    if (_distanceToRoute(pos) > 60) {
      _deviationCount++;
    } else {
      _deviationCount = 0;
      return;
    }
    if (_deviationCount < 3) return;
    _deviationCount = 0;
    final now = DateTime.now();
    if (_lastRerouteAt != null &&
        now.difference(_lastRerouteAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastRerouteAt = now;
    _autoReroute();
  }

  Future<void> _autoReroute() async {
    if (!mounted || _rerouting) return;
    setState(() => _rerouting = true);
    await _refreshRoute(fromReroute: true);
    if (mounted) setState(() => _rerouting = false);
  }

  Future<void> _refreshRoute(
      {bool initial = false, bool fromReroute = false}) async {
    final cur = _current;
    if (cur == null || !mounted) return;
    // v21 stage 3/4: route request sent to OSRM.
    if (initial && mounted) setState(() => _navProgress = 0.75);
    final alts = await _snap.fetchRouteAlternatives(
        from: cur, to: widget.destination);
    if (!mounted) return;
    setState(() {
      if (alts != null && alts.isNotEmpty) {
        final countChanged = alts.length != _routes.length;
        _routes = alts;
        _computeRouteStats();
        if (fromReroute || countChanged) {
          // Fresh alternatives (or an off-route re-route): auto-select
          // the recommended route (shortest = fuel saver).
          _selectedRoute = _shortestIdx;
        } else {
          // Keep the user's manual selection stable across refreshes.
          _selectedRoute = _selectedRoute.clamp(0, _routes.length - 1);
        }
        _applySelectedRoute();
        if (initial) {
          // v21 stage 4/4: route drawn — the bar hits 1.0 exactly as
          // the map becomes ready, then dismisses.
          _navProgress = 1.0;
          _routeReady = true;
        }
      } else {
        if (initial) {
          // Loud failure shown, but the map itself is still usable.
          _navProgress = 1.0;
          _routeReady = true;
        }
        if (!_routeFailedNoteShown) {
          _routeFailedNoteShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(AppLocalizations.of(context).navRouteFailed)),
          );
        }
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
    _etaMin = _blendedEtaMin(sel);
  }

  /// Blended ETA for a route: 50% the courier's own measured riding
  /// speed (from his completed trip history) + 50% the server's
  /// implied speed for this route. Falls back to 100% server estimate
  /// when there is no trip history yet.
  ///
  /// HONESTY NOTE: there is NO live-traffic data source — OSRM has
  /// none, and we claim none anywhere. The personal-speed half
  /// implicitly embeds the real traffic he rides through, because it
  /// is measured from his actual trips (distance / moving time).
  /// Distance stays the real OSRM road distance — only TIME is
  /// blended.
  int _blendedEtaMin(RouteDirections r) {
    double? serverSpeed;
    if (r.durationSec > 0) {
      serverSpeed = r.distanceKm / (r.durationSec / 3600.0);
    }
    final personal = widget.personalSpeedKmh;
    final double speed;
    if (personal != null &&
        personal > 0 &&
        serverSpeed != null &&
        serverSpeed > 0) {
      speed = 0.5 * personal + 0.5 * serverSpeed;
    } else if (personal != null && personal > 0) {
      speed = personal;
    } else if (serverSpeed != null && serverSpeed > 0) {
      speed = serverSpeed;
    } else {
      return (r.durationSec / 60).round();
    }
    // One bad history batch can never break the ETA.
    final clamped = speed.clamp(10.0, 80.0);
    return (r.distanceKm / clamped * 60).round();
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

  /// Cycles perspective: north-up -> heading-up -> follow cam ->
  /// overview -> north-up.
  void _cycleMapMode() {
    if (!mounted) return;
    setState(() {
      switch (_mapMode) {
        case _MapMode.northUp:
          _mapMode = _MapMode.headingUp;
          break;
        case _MapMode.headingUp:
          _mapMode = _MapMode.followCam;
          break;
        case _MapMode.followCam:
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
          if (_following) _glideCamera(cur, _followZoom, 0);
          break;
        case _MapMode.headingUp:
          if (_following) {
            _glideCamera(_headingUpTarget(cur, _lastBearing),
                _followZoom, _lastBearing);
          } else {
            _mapController.rotate(_lastBearing);
          }
          break;
        case _MapMode.followCam:
          // v24 follow cam: heading-up rotation, camera aimed ahead.
          if (_following) {
            _glideCamera(_followCamTarget(cur, _lastBearing),
                _followZoom, _lastBearing);
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

  /// v22: decimate drawn geometry (DRAWING ONLY — distance math uses the
  /// raw data). OSRM alternatives can carry thousands of points; repainting
  /// them all on every frame was part of the map stutter. Strided sampling
  /// keeps the shape; first/last points are always kept.
  List<LatLng> _decimateForDraw(List<LatLng> pts, [int max = 600]) {
    if (pts.length <= max) return pts;
    final stride = (pts.length / max).ceil();
    final out = <LatLng>[];
    for (var i = 0; i < pts.length; i += stride) {
      out.add(pts[i]);
    }
    if (out.last != pts.last) out.add(pts.last);
    return out;
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
        points: _decimateForDraw(_routes[i].geometry),
        strokeWidth: 5,
        color: altColor,
      ));
    }
    if (_routePoints.length > 1) {
      lines.add(Polyline(
        points: _decimateForDraw(_routePoints),
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
      final mins = _blendedEtaMin(r);
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
      case _MapMode.followCam:
        return Icons.videocam_outlined;
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
      case _MapMode.followCam:
        return l10n.mapModeFollowCam;
      case _MapMode.overview:
        return l10n.mapModeOverview;
    }
  }

  /// Recommendation banner text for the shortest (fuel-saver) route.
  /// Fuel saving is inferred from shorter distance, not measured.
  String _recommendationText(AppLocalizations l10n) {
    final rec = _routes[_shortestIdx];
    final km = rec.distanceKm.toStringAsFixed(1);
    final min = _blendedEtaMin(rec).toString();
    if (_fastestIdx == _shortestIdx) {
      return l10n.routeRecommendBoth(km, min);
    }
    return l10n.routeRecommendShortest(km, min);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _routeTimer?.cancel();
    _camAnim?.dispose();
    _positionN.dispose();
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
                    // Base tiles: FMTC browse cache (instant when cached),
                    // network fallback. Region overlays (downloaded offline
                    // areas) draw above and serve instantly even offline.
                    OfflineMapService.instance.baseTileLayer(),
                    const OfflineRegionLayers(),
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
                      ],
                    ),
                    // v22: live courier position — rebuilds ONLY on GPS
                    // fixes via the notifier, never on route/card state.
                    // (Previously the whole screen rebuilt per fix.)
                    ValueListenableBuilder<LatLng?>(
                      valueListenable: _positionN,
                      builder: (context, pos, _) {
                        if (pos == null) return const SizedBox.shrink();
                        return MarkerLayer(
                          markers: [
                            Marker(
                              point: pos,
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
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          // v21: real staged loading — the bar advances ONLY on real
          // stages (permission → GPS fix → request → drawn) and hits
          // 1.0 exactly when the map is ready. No looping, no faking.
          if (!_routeReady && !_denied)
            Center(
              child: GlassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DeliveryLoadingBar(
                        width: 170, progress: _navProgress),
                    const SizedBox(height: 10),
                    Text(l10n.locatingYou),
                  ],
                ),
              ),
            ),
          // v21: off-route re-route — small NON-BLOCKING pill while the
          // new route is fetched. Never a blocking dialog for this
          // routine case; loud dialogs stay for real failures.
          if (_rerouting && !_denied)
            Positioned(
              top: MediaQuery.of(context).padding.top + 118,
              left: 0,
              right: 0,
              child: Center(
                child: GlassCard(
                  borderRadius: GlassTokens.radiusM,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const DeliveryLoadingBar(
                          width: 90, progress: 0.5),
                      const SizedBox(width: 10),
                      Text(
                        l10n.reroutingNow,
                        style: text.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
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
          // follow cam -> overview. Always live, never a dead button.
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
          // v24: "Open in Google Maps" fallback pill — sits with the
          // map controls above the perspective toggle. Opens the current
          // destination in Google Maps; in-app navigation stays primary.
          if (!_denied)
            Positioned(
              right: 16,
              bottom: 354,
              child: Pressable(
                onTap: _openInGoogleMaps,
                child: Tooltip(
                  message: l10n.openInGoogleMaps,
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
                        const Icon(
                          Icons.directions_rounded,
                          size: 20,
                          color: LiquidPalette.primaryBlue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.openInGoogleMaps,
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
