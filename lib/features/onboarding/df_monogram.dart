import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// v27.30: DF monogram splash mark, modelled on the DailyFlutterUI
/// reference intro Mohamed sent: a letter logo that draws itself
/// stroke-by-stroke, then fills, then the app name appears.
///
/// CORRECTED colour spec (supersedes any earlier note): the drawn
/// stroke is WHITE for both letters; then the D fills WHITE and the
/// F fills BLUE (LiquidPalette.primaryBlue). The splash background is
/// dark navy, so both the white stroke/fill and the blue fill read
/// clearly at every stage — never white-on-white or blue-on-blue.

/// Splash stages in order. Pure function of animation progress so
/// widget tests can assert the sequence without pumping painters.
enum DfSplashStage { drawing, filling, name, exiting }

DfSplashStage dfSplashStageFor(double t) {
  if (t < 0.56) return DfSplashStage.drawing;
  if (t < 0.80) return DfSplashStage.filling;
  if (t < 0.92) return DfSplashStage.name;
  return DfSplashStage.exiting;
}

/// The monogram's own coordinate space (215 x 120). The painter scales
/// it uniformly into whatever box it is given.
const Size _kMarkSpace = Size(215, 120);

/// D as one closed blob: stem + bowl. Stroking it draws the D outline;
/// filling it paints the solid D.
Path _dPath() {
  final p = Path();
  p.moveTo(20, 10);
  p.lineTo(20, 110);
  p.lineTo(60, 110);
  p.cubicTo(95, 110, 115, 88, 115, 60);
  p.cubicTo(115, 32, 95, 10, 60, 10);
  p.close();
  return p;
}

/// F as three strokes: stem, top bar, mid bar.
Path _fPath() {
  final p = Path();
  p.moveTo(150, 10);
  p.lineTo(150, 110);
  p.moveTo(150, 10);
  p.lineTo(195, 10);
  p.moveTo(150, 60);
  p.lineTo(178, 60);
  return p;
}

/// Draws the first [progress] fraction of [paths], in order, as one
/// continuous stroke (D first, then F).
Path _partialPaths(List<Path> paths, double progress) {
  final out = Path();
  if (progress <= 0) return out;
  final metrics = <ui.PathMetric>[];
  var total = 0.0;
  for (final path in paths) {
    for (final m in path.computeMetrics()) {
      metrics.add(m);
      total += m.length;
    }
  }
  var remaining = total * progress.clamp(0.0, 1.0);
  for (final m in metrics) {
    if (remaining <= 0) break;
    final take = math.min(m.length, remaining);
    out.addPath(m.extractPath(0, take), Offset.zero);
    remaining -= take;
  }
  return out;
}

class DfMonogramPainter extends CustomPainter {
  const DfMonogramPainter({
    required this.drawProgress,
    required this.fillProgress,
    required this.fillBlue,
  });

  /// 0..1: how much of the white stroke has been drawn.
  final double drawProgress;

  /// 0..1: how much of the solid fill has faded in (stroke fades out
  /// by the same amount).
  final double fillProgress;

  final Color fillBlue;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / _kMarkSpace.width,
      size.height / _kMarkSpace.height,
    );
    final dx = (size.width - _kMarkSpace.width * scale) / 2;
    final dy = (size.height - _kMarkSpace.height * scale) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);

    final fill = fillProgress.clamp(0.0, 1.0);
    final strokeAlpha = (1.0 - fill).clamp(0.0, 1.0);

    // Solid fills fade in: D white, F blue (thick strokes).
    if (fill > 0) {
      canvas.drawPath(
        _dPath(),
        Paint()
          ..color = Colors.white.withValues(alpha: fill)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        _fPath(),
        Paint()
          ..color = fillBlue.withValues(alpha: fill)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // White stroke draws first, then fades out as the fill lands.
    if (strokeAlpha > 0 && drawProgress > 0) {
      final drawn = _partialPaths(
        [_dPath(), _fPath()],
        drawProgress.clamp(0.0, 1.0),
      );
      canvas.drawPath(
        drawn,
        Paint()
          ..color = Colors.white.withValues(alpha: strokeAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DfMonogramPainter old) =>
      old.drawProgress != drawProgress ||
      old.fillProgress != fillProgress ||
      old.fillBlue != fillBlue;
}

/// The DF mark itself. [drawProgress]/[fillProgress] are driven by the
/// splash's single controller; pass 1/1 for the static (reduce-motion)
/// rendering.
class DfMonogram extends StatelessWidget {
  const DfMonogram({
    super.key,
    required this.drawProgress,
    required this.fillProgress,
    required this.fillBlue,
  });

  final double drawProgress;
  final double fillProgress;
  final Color fillBlue;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(200, 112),
        painter: DfMonogramPainter(
          drawProgress: drawProgress,
          fillProgress: fillProgress,
          fillBlue: fillBlue,
        ),
      ),
    );
  }
}
