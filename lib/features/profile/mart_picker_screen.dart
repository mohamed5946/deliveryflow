import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/database/models.dart';
import '../../core/logging/app_log_service.dart';
import '../../core/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/design_system.dart';
import '../../theme/top_snack_bar.dart';

/// v27.9: pin the mart by hand — the mutation the picker's confirm
/// button applies through the settings notifier. Sets the coordinates
/// and raises the manual flag, which FREEZES mart learning
/// (see MartLearner): automatic observations must never refine or
/// replace a point the courier placed himself.
UserSettings applyManualMart(UserSettings s, double lat, double lng) => s
  ..martLat = lat
  ..martLng = lng
  ..martManual = true;

/// v27.9: wipe the mart completely — coordinates, the manual flag and
/// the learner's pending candidate — so automatic learning starts again
/// from scratch. (Same field set the v27.8 inspect dialog cleared,
/// plus the manual flag.)
UserSettings applyClearMart(UserSettings s) => s
  ..martLat = null
  ..martLng = null
  ..martObservationCount = 0
  ..martCandidateLat = null
  ..martCandidateLng = null
  ..martCandidateCount = 0
  ..martManual = false;

/// v27.9: «حدد المارت على الخريطة» — full-screen map picker for the
/// mart location, opened from the Profile «موقع المارت» row.
///
/// A pin is FIXED at the map centre; the courier pans the map under it
/// (far more reliable on a phone than dragging a marker). Confirming
/// saves the current centre as a MANUAL mart. The saved point — manual
/// or learned — is what the tracking init data already passes as the
/// return-leg arrival geofence target, so nothing downstream changes.
class MartPickerScreen extends ConsumerStatefulWidget {
  const MartPickerScreen({super.key});

  @override
  ConsumerState<MartPickerScreen> createState() => _MartPickerScreenState();
}

class _MartPickerScreenState extends ConsumerState<MartPickerScreen> {
  /// Wide Greater-Cairo view used only when there is no saved mart and
  /// no GPS fix — the screen must always open on *something* usable.
  static const _fallbackCenter = LatLng(30.03, 31.02);
  static const _fallbackZoom = 10.0;
  static const _pinZoom = 16.5;

  final MapController _mapController = MapController();

  /// Current map centre (the point the pin sits on) — drives the
  /// coordinate readout under the map.
  LatLng _center = _fallbackCenter;

  /// True once the user has panned the map himself: a late one-shot GPS
  /// fix must not yank the map away from where he is aiming.
  bool _userMoved = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    if (settings.hasMart) {
      _center = LatLng(settings.martLat!, settings.martLng!);
    } else {
      // No saved mart: opportunistically centre on where he is now.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _goToMyLocation(respectPan: true));
    }
  }

  /// One-shot GPS fix (best effort — every failure path just returns
  /// null; the map keeps whatever it is already showing).
  Future<LatLng?> _oneShotPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _goToMyLocation({bool respectPan = false}) async {
    if (_locating) return;
    setState(() => _locating = true);
    final target = await _oneShotPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (target == null) {
      if (!respectPan) {
        showTopSnackBar(
          context,
          AppLocalizations.of(context).martPickerLocationUnavailable,
        );
      }
      return;
    }
    if (respectPan && _userMoved) return;
    _mapController.move(target, _pinZoom);
  }

  Future<void> _confirm() async {
    final center = _mapController.camera.center;
    await ref
        .read(settingsProvider.notifier)
        .update((s) => applyManualMart(s, center.latitude, center.longitude));
    ref.read(appLogServiceProvider).info(
          AppLogCategory.settings,
          'Mart location set manually: ${center.latitude}, '
          '${center.longitude}',
        );
    if (!mounted) return;
    showTopSnackBar(context, AppLocalizations.of(context).done);
    Navigator.of(context).pop();
  }

  Future<void> _clear() async {
    await ref.read(settingsProvider.notifier).update(applyClearMart);
    ref.read(appLogServiceProvider).info(
          AppLogCategory.settings,
          'Mart location cleared by user',
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final hasMart = settings.hasMart;

    return GlassScaffold(
      appBar: AppBar(title: Text(l10n.martLocationLabel)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: hasMart ? _pinZoom : _fallbackZoom,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                    onPositionChanged: (pos, hasGesture) {
                      if (!mounted || pos.center == null) return;
                      setState(() {
                        _center = pos.center!;
                        if (hasGesture) _userMoved = true;
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.valor.deliveryflow',
                    ),
                  ],
                ),
                // The fixed pin: its TIP sits exactly on the map centre
                // (bottom padding lifts the icon by half its size).
                IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 44),
                      child: Icon(
                        Icons.location_pin,
                        size: 48,
                        color: scheme.error,
                        shadows: const [
                          Shadow(color: Colors.black38, blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.martPickerHint,
                  textAlign: TextAlign.center,
                  style:
                      text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_center.latitude.toStringAsFixed(5)}, '
                  '${_center.longitude.toStringAsFixed(5)}',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (hasMart && settings.martManual)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l10n.martPickerManual,
                      textAlign: TextAlign.center,
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.65)),
                    ),
                  )
                else if (hasMart && settings.martObservationCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l10n.martObservations(settings.martObservationCount),
                      textAlign: TextAlign.center,
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.65)),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l10n.martPickerConfirm),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed:
                      _locating ? null : () => _goToMyLocation(),
                  icon: _locating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded),
                  label: Text(l10n.martPickerUseMyLocation),
                ),
                if (hasMart)
                  TextButton(
                    onPressed: _clear,
                    child: Text(
                      l10n.martPickerClear,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
