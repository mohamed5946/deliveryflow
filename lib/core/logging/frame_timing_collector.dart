import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';

/// v27.21 performance measurement: cheap frame-timing collector.
///
/// Registers ONE [SchedulerBinding.addTimingsCallback] and keeps only
/// the last 120 frames' total durations. No per-frame logging, no
/// setState, no widget rebuilds — the callback only appends a number
/// to a fixed-size queue. The diagnostics log screen reads a snapshot
/// on demand (refresh button), so collection costs nothing visible.
///
/// Average FPS is computed from the mean frame duration over the
/// kept window; the worst frame is the longest single frame in it.
/// With no frames recorded yet, both read as 0 (shown as "—" by UI).
class FrameTimingCollector {
  FrameTimingCollector({this.maxFrames = 120});

  final int maxFrames;
  final Queue<Duration> _frames = Queue<Duration>();
  bool _started = false;

  /// Start collecting (idempotent). Call once from main().
  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    for (final t in timings) {
      _frames.addLast(t.totalSpan);
      while (_frames.length > maxFrames) {
        _frames.removeFirst();
      }
    }
  }

  /// Test seam: feed synthetic timings without a SchedulerBinding.
  void recordTestTimings(Iterable<Duration> durations) {
    for (final d in durations) {
      _frames.addLast(d);
      while (_frames.length > maxFrames) {
        _frames.removeFirst();
      }
    }
  }

  int get frameCount => _frames.length;

  /// Mean FPS over the kept window, rounded down. 0 when empty.
  int get averageFps {
    if (_frames.isEmpty) return 0;
    var totalUs = 0;
    for (final f in _frames) {
      totalUs += f.inMicroseconds;
    }
    final meanUs = totalUs / _frames.length;
    if (meanUs <= 0) return 0;
    return (1000000 / meanUs).floor();
  }

  /// Longest single frame in the kept window, in whole milliseconds.
  int get worstFrameMs {
    var worst = 0;
    for (final f in _frames) {
      if (f.inMilliseconds > worst) worst = f.inMilliseconds;
    }
    return worst;
  }
}

/// App-wide collector, started from main().
final frameTimingCollector = FrameTimingCollector();
