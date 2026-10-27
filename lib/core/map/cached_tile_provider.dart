import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// v27.21 performance: disk-cached OSM tile provider for flutter_map.
///
/// Tiles are stored under `<cache>/map_tiles/<z>/<x>/<y>.png` and
/// served from disk on repeat visits, so reopening an order detail
/// (or any map screen) no longer re-downloads and re-rasterizes the
/// same tiles on every rebuild. On a cache miss the tile is fetched
/// over the network (with the provider's headers, including the
/// User-Agent flutter_map injects) and written to disk; a failed
/// fetch surfaces as a load error exactly like the plain network
/// provider, so a missing tile never silently becomes a wrong tile.
///
/// Cache headers: OSM tiles are effectively immutable per z/x/y, so
/// no expiry is applied — a tile file, once written, is trusted.
/// Corrupt/empty files are deleted and refetched on the next load.
///
/// This is a pure performance change: no new permissions, no new
/// API keys, no change to tile URLs or map appearance.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({super.headers});

  Future<Directory>? _cacheDirFuture;

  Future<Directory> _cacheDir() {
    _cacheDirFuture ??= getTemporaryDirectory()
        .then((base) => Directory('${base.path}/map_tiles'));
    return _cacheDirFuture!;
  }

  /// Cache file for one tile. Pure function of z/x/y — used by tests.
  static String cacheFilePath({
    required String basePath,
    required int z,
    required int x,
    required int y,
  }) =>
      '$basePath/$z/$x/$y.png';

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImage(
      provider: this,
      url: getTileUrl(coordinates, options),
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
    );
  }

  Future<Uint8List> _loadTile({
    required String url,
    required int z,
    required int x,
    required int y,
  }) async {
    final dir = await _cacheDir();
    final file = File(cacheFilePath(
      basePath: dir.path,
      z: z,
      x: x,
      y: y,
    ));
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) return bytes;
        await file.delete();
      }
    } catch (_) {
      // A broken cache entry must never block the map: fall through
      // to a network fetch below.
    }
    final response = await http.get(
      Uri.parse(url),
      headers: headers.isEmpty ? null : headers,
    );
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw HttpException(
        'Tile request failed: ${response.statusCode} for $url',
      );
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes, flush: false);
    } catch (_) {
      // Cache write failure is non-fatal: the tile is still usable
      // for this frame.
    }
    return response.bodyBytes;
  }
}

/// ImageProvider that decodes one cached/network tile.
class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  const _CachedTileImage({
    required this.provider,
    required this.url,
    required this.z,
    required this.x,
    required this.y,
  });

  final CachedTileProvider provider;
  final String url;
  final int z;
  final int x;
  final int y;

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_CachedTileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, chunkEvents, decode),
      chunkEvents: chunkEvents.stream,
      scale: 1.0,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _loadAsync(
    _CachedTileImage key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    late final ui.Codec codec;
    try {
      final bytes = await provider._loadTile(
        url: key.url,
        z: key.z,
        x: key.x,
        y: key.y,
      );
      chunkEvents.add(ImageChunkEvent(
        cumulativeBytesLoaded: bytes.length,
        expectedTotalBytes: bytes.length,
      ));
      codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } finally {
      await chunkEvents.close();
    }
    return codec;
  }

  @override
  bool operator ==(Object other) =>
      other is _CachedTileImage &&
      other.url == url &&
      other.z == z &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(url, z, x, y);
}
