import 'dart:async';

import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/offline_maps/offline_map_service.dart';
import '../../theme/design_system.dart';
import '../../theme/pressable.dart';

/// Pick a rectangle to download for offline use.
///
/// The user pans/zooms the map; the region is the currently visible bounds.
/// Shows a real tile-count + size estimate, then downloads with REAL
/// progress (every bar tick = actually completed tiles) and cancel support.
class RegionPickerScreen extends StatefulWidget {
  const RegionPickerScreen({super.key});

  @override
  State<RegionPickerScreen> createState() => _RegionPickerScreenState();
}

class _RegionPickerScreenState extends State<RegionPickerScreen> {
  final MapController _mapController = MapController();
  StreamSubscription? _mapEvents;
  Timer? _estimateDebounce;
  int _estimateGen = 0;

  int _minZoom = OfflineMapService.defaultMinZoom;
  int _maxZoom = OfflineMapService.defaultMaxZoom;
  int? _tileCount;
  bool _estimating = false;

  RegionDownloadSession? _session;
  DownloadProgress? _progress;
  StreamSubscription<DownloadProgress>? _progressSub;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _mapEvents = _mapController.mapEventStream.listen((e) {
      if (e is MapEventMoveEnd) _scheduleEstimate();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleEstimate());
  }

  @override
  void dispose() {
    _mapEvents?.cancel();
    _estimateDebounce?.cancel();
    _progressSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _scheduleEstimate() {
    _estimateDebounce?.cancel();
    _estimateDebounce = Timer(const Duration(milliseconds: 700), () {
      if (mounted && _session == null) _runEstimate();
    });
  }

  Future<void> _runEstimate() async {
    final gen = ++_estimateGen;
    setState(() {
      _estimating = true;
      _tileCount = null;
    });
    try {
      final bounds = _mapController.camera.visibleBounds;
      final count =
          await OfflineMapService.instance.estimateTileCount(
        bounds: bounds,
        minZoom: _minZoom,
        maxZoom: _maxZoom,
      );
      if (!mounted || gen != _estimateGen) return;
      setState(() {
        _tileCount = count;
        _estimating = false;
      });
    } catch (_) {
      if (!mounted || gen != _estimateGen) return;
      setState(() => _estimating = false);
    }
  }

  void _changeZoom(bool isMin, int delta) {
    setState(() {
      if (isMin) {
        _minZoom = (_minZoom + delta).clamp(1, _maxZoom);
      } else {
        _maxZoom = (_maxZoom + delta).clamp(_minZoom, 18);
      }
    });
    _scheduleEstimate();
  }

  Future<void> _onDownloadPressed() async {
    final l10n = AppLocalizations.of(context);
    final svc = OfflineMapService.instance;
    final tileCount = _tileCount;
    if (tileCount == null || tileCount <= 0) return;

    // 1. Mobile-data warning (warn, don't block).
    final go = await showGlassDialog<bool>(
      context: context,
      title: Text(l10n.mobileDataWarnTitle),
      content: Text(l10n.mobileDataWarnMsg),
      barrierDismissible: false,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.continueDownload),
        ),
      ],
    );
    if (go != true || !mounted) return;

    // 2. Large-region confirmation (>500MB).
    final mb = OfflineMapService.estimateMiB(tileCount);
    if (mb > 500 && mounted) {
      final sure = await showGlassDialog<bool>(
        context: context,
        title: Text(l10n.largeRegionTitle),
        content: Text(l10n.largeRegionMsg(mb.toStringAsFixed(0))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child:
                Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.continueDownload),
          ),
        ],
      );
      if (sure != true || !mounted) return;
    }

    // 3. Start the real download.
    RegionDownloadSession session;
    try {
      final bounds = _mapController.camera.visibleBounds;
      final date =
          DateFormat('d MMM', l10n.localeName).format(DateTime.now());
      session = await svc.startDownload(
        bounds: bounds,
        minZoom: _minZoom,
        maxZoom: _maxZoom,
        label: l10n.regionLabel(date),
      );
    } catch (_) {
      if (!mounted) return;
      await showGlassDialog<void>(
        context: context,
        barrierDismissible: false,
        title: Text(l10n.offlineStorageError),
        content: Text(l10n.offlineStorageErrorMsg),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
      return;
    }

    setState(() {
      _session = session;
      _progress = null;
    });
    _progressSub = session.progress.listen(
      (p) {
        if (!mounted) return;
        setState(() => _progress = p);
        if (p.isComplete) _onDownloadComplete(session, p);
      },
      onError: (_) => _onDownloadError(session),
      onDone: () {
        // Stream ended without isComplete (e.g. cancelled externally).
        if (mounted && _session == session && !_finishing) {
          _onDownloadError(session);
        }
      },
    );
  }

  Future<void> _onDownloadComplete(
      RegionDownloadSession session, DownloadProgress last) async {
    if (_finishing) return;
    _finishing = true;
    await _progressSub?.cancel();
    _progressSub = null;
    try {
      await OfflineMapService.instance.completeDownload(session, last);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _session = null;
      _progress = null;
      _finishing = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context).downloadComplete)),
    );
    context.pop();
  }

  Future<void> _onDownloadError(RegionDownloadSession session) async {
    if (_finishing) return;
    _finishing = true;
    await _progressSub?.cancel();
    _progressSub = null;
    try {
      await OfflineMapService.instance.cancelDownload(session);
    } catch (_) {}
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _session = null;
      _progress = null;
      _finishing = false;
    });
    await showGlassDialog<void>(
      context: context,
      title: Text(l10n.downloadFailed),
      content: Text(l10n.downloadFailedMsg),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }

  Future<void> _onCancelPressed() async {
    final session = _session;
    if (session == null || _finishing) return;
    _finishing = true;
    await _progressSub?.cancel();
    _progressSub = null;
    try {
      await OfflineMapService.instance.cancelDownload(session);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _session = null;
      _progress = null;
      _finishing = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(AppLocalizations.of(context).downloadCancelled)),
    );
    _scheduleEstimate();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final svc = OfflineMapService.instance;
    final downloading = _session != null;

    return GlassScaffold(
      appBar: AppBar(title: Text(l10n.pickRegionTitle)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(30.0444, 31.2357),
              initialZoom: 11,
              minZoom: 3,
              maxZoom: 18,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              svc.baseTileLayer(),
              const OfflineRegionLayers(),
            ],
          ),
          // Hint pill.
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: _hintPill(l10n.pickRegionHint),
          ),
          // Bottom panel.
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: GlassCard(
              child: downloading
                  ? _downloadPanel(l10n)
                  : _pickPanel(l10n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hintPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(GlassTokens.radiusM),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  Widget _pickPanel(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
                child: _zoomStepper(
                    l10n.zoomFrom, _minZoom, () => _changeZoom(true, -1),
                    () => _changeZoom(true, 1))),
            const SizedBox(width: 8),
            Expanded(
                child: _zoomStepper(l10n.zoomTo, _maxZoom,
                    () => _changeZoom(false, -1), () => _changeZoom(false, 1))),
          ],
        ),
        const SizedBox(height: 10),
        // Real estimate (from FMTC's exact tile counter).
        SizedBox(
          height: 22,
          child: _estimating
              ? Text(l10n.estimatingRegion,
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant))
              : _tileCount == null
                  ? const SizedBox.shrink()
                  : Text(
                      l10n.regionEstimate(
                        OfflineMapService.estimateMiB(_tileCount!)
                            .toStringAsFixed(0),
                        '$_tileCount',
                      ),
                      style: text.bodySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold),
                    ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: (_tileCount != null && _tileCount! > 0)
                ? _onDownloadPressed
                : null,
            icon: const Icon(Icons.download_rounded),
            label: Text(l10n.useThisArea,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ],
    );
  }

  Widget _zoomStepper(
      String label, int value, VoidCallback onMinus, VoidCallback onPlus) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(GlassTokens.radiusS),
      ),
      child: Column(
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepBtn(Icons.remove_rounded, onMinus),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('$value',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              _stepBtn(Icons.add_rounded, onPlus),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon,
            size: 18, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  /// Download panel with REAL progress: every tick reflects actually
  /// completed tiles (cached + skipped) out of the exact total.
  Widget _downloadPanel(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final p = _progress;
    final total = p?.maxTiles ?? 0;
    final done = (p?.cachedTiles ?? 0) + (p?.skippedTiles ?? 0);
    final value = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final mb =
        (((p?.cachedSize ?? 0) + (p?.skippedSize ?? 0)) / 1024)
            .toStringAsFixed(1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.downloadingRegion,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 12,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.downloadProgress('$done', mb, '$total'),
          style: text.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _onCancelPressed,
          icon: const Icon(Icons.close_rounded),
          label: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error),
        ),
      ],
    );
  }
}
