import 'dart:math' as math;

import 'package:flutter/material.dart';

/// v27.31: COMBINED DF monogram splash mark — ONE mark, exactly as in
/// the DailyFlutterUI reference video Mohamed sent (frames verified by
/// the parent), replacing the v27.30 side-by-side D + F letters.
///
/// The mark, in order:
/// 1. A thin WHITE line draws the outline path of a bold D
///    (stroke-draw path animation, top-to-bottom with the D's curve).
/// 2. The D then FILLS solid WHITE (bold white D block).
/// 3. Inside the D's bowl, a BLUE stylized F appears (slanted stem
///    with a top bar + a mid bar, nested inside the D — the video's
///    final mark: white D, blue F inside it).
///
/// The splash background is dark navy, so the white stroke/D-fill and
/// the blue F-fill all read clearly at every stage — never
/// white-on-white or blue-on-blue. The old side-by-side mark is gone;
/// exactly one mark exists, never two stacked marks.

/// Splash stages in order. Pure function of animation progress so
/// widget tests can assert the sequence without pumping painters.
enum DfSplashStage { drawing, filling, name, exiting }

DfSplashStage dfSplashStageFor(double t) {
  if (t < 0.56) return DfSplashStage.drawing;
  if (t < 0.80) return DfSplashStage.filling;
  if (t < 0.92) return DfSplashStage.name;
  return DfSplashStage.exiting;
}

/// The monogram's own coordinate space (160 x 160). The painter scales
/// it uniformly into whatever box it is given.
const Size _kMarkSpace = Size(160, 160);

/// The bold D as one closed blob: stem + bowl. Stroking it draws the D
/// outline; filling it paints the solid white D. Public so widget tests
/// can assert the F sits geometrically inside it.
Path monogramDPath() {
  final p = Path();
  p.moveTo(24, 16);
  p.lineTo(24, 144);
  p.lineTo(72, 144);
  p.cubicTo(120, 144, 140, 118, 140, 80);
  p.cubicTo(140, 42, 120, 16, 72, 16);
  p.close();
  return p;
}

/// The stylized F nested inside the D's bowl: slanted stem, top bar,
/// mid bar. Painted in blue on top of the solid white D. Its bounds
/// sit strictly inside the D's bounds (see the widget test).
Path monogramFPath() {
  final p = Path();
  // Slanted stem (top-right to bottom-left, like the video's mark).
  p.moveTo(72, 50);
  p.lineTo(62, 118);
  // Top bar.
  p.moveTo(72, 50);
  p.lineTo(112, 50);
  // Mid bar.
  p.moveTo(68, 84);
  p.lineTo(100, 84);
  return p;
}

/// Draws the first [progress] fraction of [path] as one stroke.
Path _partialPath(Path path, double progress) {
  final out = Path();
  if (progress <= 0) return out;
  final metrics = path.computeMetrics().toList();
  var total = 0.0;
  for (final m in metrics) {
    total += m.length;
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

  /// 0..1: how much of the white D outline has been drawn.
  final double drawProgress;

  /// 0..1: how much of the solid fill has faded in (stroke fades out
  /// by the same amount; the blue F fades in during the second part
  /// of the fill so the order is stroke -> white D -> blue F).
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
    // F appears once the D fill is a quarter in, fully in by fill end.
    final fAlpha = ((fill - 0.25) / 0.75).clamp(0.0, 1.0);

    // Solid white D fades in.
    if (fill > 0) {
      canvas.drawPath(
        monogramDPath(),
        Paint()
          ..color = Colors.white.withValues(alpha: fill)
          ..style = PaintingStyle.fill,
      );
    }

    // Blue F inside the D's bowl fades in after the D fill starts.
    if (fAlpha > 0) {
      canvas.drawPath(
        monogramFPath(),
        Paint()
          ..color = fillBlue.withValues(alpha: fAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // White D outline draws first, then fades out as the fill lands.
    if (strokeAlpha > 0 && drawProgress > 0) {
      final drawn = _partialPath(
        monogramDPath(),
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

/// The combined DF mark itself. [drawProgress]/[fillProgress] are driven
/// by the splash's single controller; pass 1/1 for the static
/// (reduce-motion) rendering.
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
        size: const Size(180, 180),
        painter: DfMonogramPainter(
          drawProgress: drawProgress,
          fillProgress: fillProgress,
          fillBlue: fillBlue,
        ),
      ),
    );
  }
}
