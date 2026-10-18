import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';

/// Metadata for one user-downloaded offline map region.
///
/// The tiles themselves live in an FMTC store named [storeName]; this
/// record only describes the region so it can be listed, sized and deleted.
@immutable
class OfflineRegion {
  final String id;
  final String storeName;
  final String label;
  final int createdAtMs;
  final int minZoom;
  final int maxZoom;
  final double north;
  final double south;
  final double east;
  final double west;
  final int tileCount;
  final double sizeKiB;

  const OfflineRegion({
    required this.id,
    required this.storeName,
    required this.label,
    required this.createdAtMs,
    required this.minZoom,
    required this.maxZoom,
    required this.north,
    required this.south,
    required this.east,
    required this.west,
    required this.tileCount,
    required this.sizeKiB,
  });

  LatLngBounds get bounds => LatLngBounds(LatLng(south, west), LatLng(north, east));

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeName': storeName,
        'label': label,
        'createdAtMs': createdAtMs,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
        'north': north,
        'south': south,
        'east': east,
        'west': west,
        'tileCount': tileCount,
        'sizeKiB': sizeKiB,
      };

  factory OfflineRegion.fromMap(Map<dynamic, dynamic> m) => OfflineRegion(
        id: m['id'] as String,
        storeName: m['storeName'] as String,
        label: m['label'] as String,
        createdAtMs: (m['createdAtMs'] as num).toInt(),
        minZoom: (m['minZoom'] as num).toInt(),
        maxZoom: (m['maxZoom'] as num).toInt(),
        north: (m['north'] as num).toDouble(),
        south: (m['south'] as num).toDouble(),
        east: (m['east'] as num).toDouble(),
        west: (m['west'] as num).toDouble(),
        tileCount: (m['tileCount'] as num?)?.toInt() ?? 0,
        sizeKiB: (m['sizeKiB'] as num?)?.toDouble() ?? 0,
      );

  OfflineRegion copyWith({int? tileCount, double? sizeKiB}) => OfflineRegion(
        id: id,
        storeName: storeName,
        label: label,
        createdAtMs: createdAtMs,
        minZoom: minZoom,
        maxZoom: maxZoom,
        north: north,
        south: south,
        east: east,
        west: west,
        tileCount: tileCount ?? this.tileCount,
        sizeKiB: sizeKiB ?? this.sizeKiB,
      );
}

/// A download in progress: the metadata draft plus the real FMTC progress
/// stream. The draft is only persisted to Hive once the download completes.
class RegionDownloadSession {
  final OfflineRegion draft;
  final Stream<DownloadProgress> progress;

  const RegionDownloadSession({required this.draft, required this.progress});
}

/// Offline map tiles (flutter_map_tile_caching v9, ObjectBox backend).
///
/// Architecture — 100% public FMTC API:
/// - `mapStore`: browse cache (`cacheFirst`) used by the base [TileLayer].
/// - `offline_region_<id>`: one store per downloaded region. Each region
///   gets a stacked [TileLayer] with `CacheBehavior.cacheOnly` drawn ABOVE
///   the base layer: tiles present in a region store draw instantly (even
///   on weak internet); misses render transparent so lower layers show
///   through, and the base layer falls back to the network.
/// - Region metadata lives in the Hive box `offline_regions`.
class OfflineMapService {
  OfflineMapService._();
  static final OfflineMapService instance = OfflineMapService._();

  static const String urlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String userAgent = 'com.valor.deliveryflow';
  static const String mainStoreName = 'mapStore';

  static const int defaultMinZoom = 10;
  static const int defaultMaxZoom = 16;

  /// Average OSM raster tile size used for pre-download estimates.
  static const double avgTileKiB = 15;

  /// Whether FMTC initialised correctly. When false, maps fall back to
  /// plain network tiles and offline features are disabled in UI.
  bool fmtcReady = false;

  /// Currently known downloaded regions (newest first).
  final ValueNotifier<List<OfflineRegion>> regions =
      ValueNotifier<List<OfflineRegion>>([]);

  Box? _box;

  Future<void> init() async {
    try {
      _box = await Hive.openBox('offline_regions');
    } catch (_) {
      _box = null;
    }
    try {
      await FMTCObjectBoxBackend().initialise();
      const main = FMTCStore(mainStoreName);
      try {
        await main.manage.create();
      } catch (_) {
        // Already exists — ignore.
      }
      fmtcReady = await main.manage.ready;
    } catch (_) {
      fmtcReady = false;
    }
    await _loadRegions();
    await _cleanupOrphanStores();
  }

  Future<void> _loadRegions() async {
    final box = _box;
    if (box == null) {
      regions.value = [];
      return;
    }
    final list = <OfflineRegion>[];
    for (final key in box.keys) {
      try {
        final raw = box.get(key);
        if (raw is Map) list.add(OfflineRegion.fromMap(raw));
      } catch (_) {}
    }
    list.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    regions.value = list;
  }

  /// Delete FMTC stores that look like regions but have no metadata record
  /// (e.g. the app was killed mid-download).
  Future<void> _cleanupOrphanStores() async {
    if (!fmtcReady) return;
    try {
      final stores = await FMTCRoot.stats.storesAvailable;
      final known =
          regions.value.map((r) => r.storeName).toSet()..add(mainStoreName);
      for (final s in stores) {
        if (s.storeName.startsWith('offline_region_') &&
            !known.contains(s.storeName)) {
          try {
            await s.manage.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Base tile layer for every in-app map. Uses the FMTC browse cache when
  /// available, plain network tiles otherwise.
  TileLayer baseTileLayer() {
    if (fmtcReady) {
      const store = FMTCStore(mainStoreName);
      return TileLayer(
        urlTemplate: urlTemplate,
        userAgentPackageName: userAgent,
        tileProvider: store.getTileProvider(),
      );
    }
    return TileLayer(
      urlTemplate: urlTemplate,
      userAgentPackageName: userAgent,
    );
  }

  DownloadableRegion _toDownloadable({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
  }) =>
      RectangleRegion(bounds).toDownloadable(
        minZoom: minZoom,
        maxZoom: maxZoom,
        options: TileLayer(
          urlTemplate: urlTemplate,
          userAgentPackageName: userAgent,
        ),
      );

  /// Exact tile count for a region (runs in an isolate; may take a few
  /// seconds for large regions).
  Future<int> estimateTileCount({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
  }) {
    final downloadable = _toDownloadable(
        bounds: bounds, minZoom: minZoom, maxZoom: maxZoom);
    return const FMTCStore(mainStoreName).download.check(downloadable);
  }

  /// Rough MB estimate from a tile count (for display before downloading).
  static double estimateMiB(int tileCount) =>
      tileCount * avgTileKiB / 1024;

  /// Start downloading a region. Throws on storage errors (caller shows a
  /// loud dialog). Gentle on the tile server: 2 threads, 2 tiles/second.
  Future<RegionDownloadSession> startDownload({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required String label,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final storeName = 'offline_region_$id';
    final store = FMTCStore(storeName);
    await store.manage.create();
    final downloadable = _toDownloadable(
        bounds: bounds, minZoom: minZoom, maxZoom: maxZoom);
    final progress = store.download.startForeground(
      region: downloadable,
      parallelThreads: 2,
      rateLimit: 2,
      skipExistingTiles: true,
    );
    final draft = OfflineRegion(
      id: id,
      storeName: storeName,
      label: label,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      minZoom: minZoom,
      maxZoom: maxZoom,
      north: bounds.north,
      south: bounds.south,
      east: bounds.east,
      west: bounds.west,
      tileCount: 0,
      sizeKiB: 0,
    );
    return RegionDownloadSession(draft: draft, progress: progress);
  }

  /// Cancel an in-progress download and remove its partial store.
  Future<void> cancelDownload(RegionDownloadSession session) async {
    final store = FMTCStore(session.draft.storeName);
    try {
      await store.download.cancel();
    } catch (_) {}
    try {
      await store.manage.delete();
    } catch (_) {}
  }

  /// Persist a finished download's metadata and refresh the region list.
  Future<void> completeDownload(
      RegionDownloadSession session, DownloadProgress last) async {
    final store = FMTCStore(session.draft.storeName);
    int tileCount = last.cachedTiles + last.skippedTiles;
    double sizeKiB = last.cachedSize + last.skippedSize;
    try {
      final stats = await store.stats.all;
      tileCount = stats.length;
      sizeKiB = stats.size;
    } catch (_) {}
    final region =
        session.draft.copyWith(tileCount: tileCount, sizeKiB: sizeKiB);
    await _box?.put(region.id, region.toMap());
    await _loadRegions();
  }

  /// Delete one region: its tiles and its metadata record.
  Future<void> deleteRegion(OfflineRegion region) async {
    try {
      await FMTCStore(region.storeName).manage.delete();
    } catch (_) {}
    await _box?.delete(region.id);
    await _loadRegions();
  }

  /// Delete every downloaded region.
  Future<void> clearAll() async {
    for (final r in List<OfflineRegion>.of(regions.value)) {
      await deleteRegion(r);
    }
  }
}

/// Stacked region overlay layers for in-app maps.
///
/// One `cacheOnly` TileLayer per downloaded region, drawn above the base
/// layer: a tile present in a region store renders instantly (even with weak
/// or no internet); a missing tile errors to transparent so the layers
/// below show through. Rebuilds automatically when regions change.
class OfflineRegionLayers extends StatelessWidget {
  const OfflineRegionLayers({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = OfflineMapService.instance;
    if (!svc.fmtcReady) return const SizedBox.shrink();
    return ValueListenableBuilder<List<OfflineRegion>>(
      valueListenable: svc.regions,
      builder: (context, regions, _) {
        if (regions.isEmpty) return const SizedBox.shrink();
        return Stack(
          children: [
            for (final r in regions)
              TileLayer(
                urlTemplate: OfflineMapService.urlTemplate,
                userAgentPackageName: OfflineMapService.userAgent,
                tileProvider:
                    FMTCStore(r.storeName).getTileProvider(
                  settings: FMTCTileProviderSettings(
                    behavior: CacheBehavior.cacheOnly,
                    // Don't clobber the ambient global settings instance.
                    setInstance: false,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
