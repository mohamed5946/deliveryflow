import 'dart:math' as math;

import 'package:flutter/material.dart';

/// v27.32: COMBINED DF monogram splash mark — rebuilt to match the
/// DailyFlutterUI reference video's ACTUAL motion. v27.31 got the
/// fill wrong (instant outline -> solid switch, blue F popping in
/// afterwards); Mohamed judged that entry "very very very bad
/// compared to the video". This version reproduces the video's
/// three beats, in order:
///
/// STAGE 1 — outline draw (~1000ms): a THIN WHITE outline path of
///   the bold D draws itself progressively, with a small GLOWING TIP
///   DOT travelling at the leading point of the stroke and small
///   ANCHOR DOTS at the path's corner points, like a vector path
///   being drawn.
/// STAGE 2 — diagonal fill sweep (~1000ms): a DIAGONAL wipe
///   boundary sweeps across the mark from the bottom-left toward
///   the top-right. Behind the sweep line the D is solid WHITE and
///   the blue F inside the bowl is ALREADY THERE; ahead of the line
///   the mark is still just the thin outline. The blue F is revealed
///   BY THE SAME SWEEP — it emerges progressively as the wipe
///   passes over it, never as a separate pop-in.
/// FINAL MARK: one large bold centered mark — solid WHITE D with
///   the BLUE stylized F nested inside its bowl (slanted stem +
///   top bar + mid bar), on a NEAR-BLACK background matching the
///   video (not the previous navy).
///
/// TOTAL ENTRY is exactly 2500ms (Mohamed's correction, superseding
/// the 2000ms note and the old 1.25s budget): draw 1000ms + sweep
/// 1000ms + name fade 500ms. The animation never blocks on network,
/// and under OS reduce-motion it shows the static final mark and
/// enters immediately. The old motorcycle entry stays removed;
/// motorcycle branding inside the app is untouched.

/// Splash stages in order. Pure function of animation progress so
/// widget tests can assert the sequence without pumping painters.
/// Fractions of the exact 2500ms total: draw 0–0.40, sweep
/// 0.40–0.80, name 0.80–1.00.
enum DfSplashStage { drawing, sweeping, name, exiting }

DfSplashStage dfSplashStageFor(double t) {
  if (t < 0.40) return DfSplashStage.drawing;
  if (t < 0.80) return DfSplashStage.sweeping;
  if (t < 1.0) return DfSplashStage.name;
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

/// Corner/apex points of the D path, shown as small anchor dots while
/// the outline is being drawn (like a vector path being drawn).
/// Public so tests can assert they sit on the D path's bounds.
List<Offset> monogramAnchorPoints() => const [
      Offset(24, 16),
      Offset(24, 144),
      Offset(72, 144),
      Offset(140, 80),
    ];

/// Diagonal sweep geometry, in mark space. The wipe boundary is the
/// line x - y == [sweepFrontFor]; it travels from the bottom-left
/// corner (x - y == -160) toward the top-right corner (x - y == 160)
/// as [sweepProgress] goes 0 -> 1. Points with x - y below the front
/// are BEHIND the sweep (solid); points above it are AHEAD of the
/// sweep (still thin outline).
double sweepFrontFor(double sweepProgress) =>
    -160 + sweepProgress.clamp(0.0, 1.0) * 320;

/// Whether [point] (mark space) has been revealed by the sweep at
/// [sweepProgress]. Pure, so tests can assert the F is revealed only
/// via the sweep — progressively, bottom-left parts first.
bool sweepReveals(double sweepProgress, Offset point) =>
    point.dx - point.dy <= sweepFrontFor(sweepProgress);

/// Clips [corners] (a polygon, in order) against the half-plane
/// x - y <= [front] when [keepBelow] is true, else x - y >= [front].
/// Sutherland–Hodgman; returns the clipped polygon (possibly empty).
List<Offset> _clipHalfPlane(
  List<Offset> corners,
  double front,
  bool keepBelow,
) {
  double value(Offset p) => p.dx - p.dy;
  bool inside(Offset p) => keepBelow ? value(p) <= front : value(p) >= front;
  Offset intersect(Offset a, Offset b) {
    final va = value(a);
    final vb = value(b);
    final t = (front - va) / (vb - va);
    return Offset(
      a.dx + (b.dx - a.dx) * t,
      a.dy + (b.dy - a.dy) * t,
    );
  }

  var out = <Offset>[];
  for (var i = 0; i < corners.length; i++) {
    final current = corners[i];
    final previous = corners[(i + corners.length - 1) % corners.length];
    final curIn = inside(current);
    final prevIn = inside(previous);
    if (curIn) {
      if (!prevIn) out.add(intersect(previous, current));
      out.add(current);
    } else if (prevIn) {
      out.add(intersect(previous, current));
    }
  }
  return out;
}

Path _polygonPath(List<Offset> points) {
  final p = Path();
  if (points.isEmpty) return p;
  p.moveTo(points.first.dx, points.first.dy);
  for (final pt in points.skip(1)) {
    p.lineTo(pt.dx, pt.dy);
  }
  p.close();
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

/// Point at the leading end of the drawn stroke (mark space), or null
/// when nothing has been drawn yet. Used for the glowing tip dot.
Offset? _tipPoint(Path path, double progress) {
  if (progress <= 0) return null;
  final metrics = path.computeMetrics().toList();
  var total = 0.0;
  for (final m in metrics) {
    total += m.length;
  }
  var remaining = total * progress.clamp(0.0, 1.0);
  for (final m in metrics) {
    if (remaining <= m.length) {
      return m.getTangentForOffset(remaining)?.position;
    }
    remaining -= m.length;
  }
  return null;
}

/// Fraction along the D path at which each anchor point is reached,
/// found by sampling the path and taking the nearest sample. Computed
/// once (the path is constant); anchors whose fraction is <= the
/// draw progress are shown.
List<double> _anchorArrivals() {
  final path = monogramDPath();
  final metrics = path.computeMetrics().toList();
  var total = 0.0;
  for (final m in metrics) {
    total += m.length;
  }
  final anchors = monogramAnchorPoints();
  final bestDist = List<double>.filled(anchors.length, double.infinity);
  final bestFrac = List<double>.filled(anchors.length, 1.0);
  var walked = 0.0;
  for (final m in metrics) {
    const steps = 200;
    for (var i = 0; i <= steps; i++) {
      final offset = m.length * i / steps;
      final pos = m.getTangentForOffset(offset)?.position;
      if (pos == null) continue;
      final frac = (walked + offset) / total;
      for (var a = 0; a < anchors.length; a++) {
        final d = (pos - anchors[a]).distanceSquared;
        if (d < bestDist[a]) {
          bestDist[a] = d;
          bestFrac[a] = frac;
        }
      }
    }
    walked += m.length;
  }
  return bestFrac;
}

class DfMonogramPainter extends CustomPainter {
  const DfMonogramPainter({
    required this.drawProgress,
    required this.sweepProgress,
    required this.fillBlue,
  });

  /// 0..1: how much of the thin white D outline has been drawn.
  final double drawProgress;

  /// 0..1: how far the diagonal wipe has travelled (bottom-left to
  /// top-right). Behind it the mark is solid (white D + blue F);
  /// ahead of it the mark is still just the thin outline.
  final double sweepProgress;

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

    final draw = drawProgress.clamp(0.0, 1.0);
    final sweep = sweepProgress.clamp(0.0, 1.0);
    final front = sweepFrontFor(sweep);
    const corners = [
      Offset(0, 0),
      Offset(160, 0),
      Offset(160, 160),
      Offset(0, 160),
    ];

    // AHEAD of the sweep: thin white outline + anchor dots + tip dot.
    // Clipped to the unrevealed half-plane so no outline halo sticks
    // out past the solid edge behind the sweep line.
    if (draw > 0) {
      final ahead = _clipHalfPlane(corners, front, false);
      canvas.save();
      canvas.clipPath(_polygonPath(ahead));
      final drawn =
          draw >= 1 ? monogramDPath() : _partialPath(monogramDPath(), draw);
      canvas.drawPath(
        drawn,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      // Anchor dots at corner points the stroke has already reached.
      final arrivals = _anchorArrivals();
      final anchors = monogramAnchorPoints();
      for (var i = 0; i < anchors.length; i++) {
        if (draw >= arrivals[i]) {
          canvas.drawCircle(
            anchors[i],
            2.5,
            Paint()..color = Colors.white,
          );
        }
      }
      // Glowing tip dot travelling at the stroke's leading point.
      if (draw < 1) {
        final tip = _tipPoint(monogramDPath(), draw);
        if (tip != null) {
          canvas.drawCircle(
            tip,
            9,
            Paint()..color = Colors.white.withValues(alpha: 0.25),
          );
          canvas.drawCircle(
            tip,
            5,
            Paint()..color = Colors.white.withValues(alpha: 0.55),
          );
          canvas.drawCircle(
            tip,
            3,
            Paint()..color = Colors.white,
          );
        }
      }
      canvas.restore();
    }

    // BEHIND the sweep: solid white D with the blue F inside it,
    // revealed by the SAME diagonal wipe — never a separate pop-in.
    if (sweep > 0) {
      final behind = _clipHalfPlane(corners, front, true);
      canvas.save();
      canvas.clipPath(_polygonPath(behind));
      canvas.drawPath(
        monogramDPath(),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        monogramFPath(),
        Paint()
          ..color = fillBlue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DfMonogramPainter old) =>
      old.drawProgress != drawProgress ||
      old.sweepProgress != sweepProgress ||
      old.fillBlue != fillBlue;
}

/// The combined DF mark itself. [drawProgress]/[sweepProgress] are
/// driven by the splash's single controller; pass 1/1 for the static
/// (reduce-motion) rendering.
class DfMonogram extends StatelessWidget {
  const DfMonogram({
    super.key,
    required this.drawProgress,
    required this.sweepProgress,
    required this.fillBlue,
  });

  final double drawProgress;
  final double sweepProgress;
  final Color fillBlue;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(180, 180),
        painter: DfMonogramPainter(
          drawProgress: drawProgress,
          sweepProgress: sweepProgress,
          fillBlue: fillBlue,
        ),
      ),
    );
  }
}
