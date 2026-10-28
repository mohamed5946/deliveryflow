import 'dart:math' as math;

import 'package:flutter/material.dart';

/// v27.24: "bin eats the label" delete button. Reworked in v27.28 after a
/// field report: the old version only faded letters in place, so on a
/// real phone the flight was invisible ("letters just disappear").
///
/// Reworked again in v27.29 after Mohamed field-tested v27.28 and
/// corrected it twice, precisely:
/// 1. The idle bin must NOT show a floating red line above it. The v27.28
///    bin was a detached bar (the "lid") floating over an outline icon —
///    Mohamed pointed at that bar in a screenshot and said he does not
///    want that line there at all. The v27.29 bin is drawn as ONE bin:
///    an open-top body with a single lid sitting flush on its rim
///    (lid bottom edge exactly touches the body top edge, no gap).
/// 2. The line is NOT the lid, and the lid must not swing. On delete the
///    single lid lifts STRAIGHT UP and holds above the bin mouth,
///    leaving a clear gap — and the letters hop one-by-one DOWNWARD
///    through that gap into the bin from above ("like tossing trash into
///    a bin"), never sliding in from the side. The v27.28 flight travelled
///    sideways into the bin, which Mohamed explicitly rejected.
/// 3. There is exactly ONE lid at every moment — idle and every animation
///    stage. The old detached line element is fully gone, not left under
///    or above the new lid.
///
/// Shared by every confirmed delete action in the app (6 call sites). The
/// sequence, driven by a single 1400 ms controller, is:
/// 1. Lid lifts: the single lid rises straight up (~200 ms) and holds,
///    leaving a 14 px gap above the bin mouth.
/// 2. Letters hop in: each label letter, staggered one after another,
///    first travels horizontally toward the bin while arcing up, then
///    drops STRAIGHT DOWN through the gap into the bin mouth. The final
///    approach of every letter is purely vertical (dx constant, dy
///    increasing) — a from-above entry, not a sideways slide. Each letter
///    shrinks and fades only at the very end of its drop, inside the bin.
/// 3. Lid closes: once every letter is inside, the lid comes straight
///    back down onto the rim.
/// 4. Success check: a circle with a checkmark draws itself
///    stroke-by-stroke (circle arc, then check path), and ONLY then
///    [onConfirmed] fires exactly once.
///
/// Guarantees kept from v27.24: this button only ever appears inside an
/// existing Yes/No confirmation dialog, so the tap here IS the
/// confirmation — nothing is deleted before the animation completes, the
/// button ignores further taps while animating, and under the OS
/// reduce-motion flag the animation is skipped and [onConfirmed] fires
/// directly. Cheap transforms/opacity only: no shader, no blur layers,
/// no per-frame layout (letter distances are measured once per build).
class BinEatingDeleteButton extends StatefulWidget {
  const BinEatingDeleteButton({
    super.key,
    required this.label,
    required this.onConfirmed,
  });

  /// The button's label (e.g. the localized "Delete" or "Yes").
  final String label;

  /// Called exactly once, after the lift → hops → close → check sequence
  /// completes (or immediately under reduce-motion). Callers pop their
  /// confirmation dialog with `true` here and then execute the deletion.
  final VoidCallback onConfirmed;

  @override
  State<BinEatingDeleteButton> createState() => _BinEatingDeleteButtonState();
}

/// Total sequence length: lid 200 ms + hops + lid-close + check draw.
/// Stays inside the 1.2–1.5 s budget even for long labels.
const _totalDuration = Duration(milliseconds: 1400);

/// How far the lid rises straight up, leaving the gap letters drop through.
const _lidLiftDistance = 14.0;

/// How far a letter drops vertically into the bin mouth at the end of its
/// flight (matches the lid gap, so it lands inside the bin).
const _dropDistance = 14.0;

/// How high a letter arcs above its baseline during the horizontal leg.
const _hopHeight = 12.0;

class _BinEatingDeleteButtonState extends State<BinEatingDeleteButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _animating = false;
  bool _showCheck = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _totalDuration)
      ..addListener(_onTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      });
  }

  /// The check appears once the lid is shut again (t >= 0.82).
  void _onTick() {
    if (!_showCheck && _controller.value >= 0.82) {
      _showCheck = true;
      if (mounted) setState(() {});
    }
  }

  void _start() {
    if (_animating || _completed) return; // ignore taps while animating.
    // OS reduce-motion: skip the animation, delete directly.
    if (MediaQuery.disableAnimationsOf(context)) {
      _completed = true;
      widget.onConfirmed();
      return;
    }
    setState(() {
      _animating = true;
    });
    _controller.forward();
  }

  void _finish() {
    if (!mounted || _completed) return;
    _completed = true;
    widget.onConfirmed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  TextStyle _labelStyle(BuildContext context) {
    return Theme.of(context).textTheme.labelLarge ??
        const TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
  }

  double _labelWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: widget.label, style: _labelStyle(context)),
      textDirection: Directionality.of(context),
    )..layout();
    // label + bin icon + gaps + horizontal padding.
    return painter.width + 24 + 16 + 32;
  }

  /// Per-letter widths, used to aim each letter at the bin mouth.
  List<double> _letterWidths(BuildContext context) {
    final style = _labelStyle(context);
    final dir = Directionality.of(context);
    return widget.label.characters.map((c) {
      final painter = TextPainter(
        text: TextSpan(text: c, style: style),
        textDirection: dir,
      )..layout();
      return painter.width;
    }).toList();
  }

  /// Lid lift factor (0 = flush on the rim, 1 = fully raised): rises over
  /// t = 0 → 0.15, holds through the hops, comes back down over
  /// t = 0.70 → 0.82. Straight vertical motion only — no swing, no turn.
  double _lidLift(double t) {
    final up =
        const Interval(0.0, 0.15, curve: Curves.easeOut).transform(t);
    final down =
        const Interval(0.70, 0.82, curve: Curves.easeInOut).transform(t);
    return up * (1.0 - down);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chars = widget.label.characters.toList();
    final widths = _letterWidths(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final sign = rtl ? -1.0 : 1.0;
    // Distance from each letter's centre to the bin centre: the letters
    // after it, plus the 8 px gap, plus half the 24 px bin.
    final distances = List<double>.generate(chars.length, (i) {
      var after = 0.0;
      for (var j = i + 1; j < chars.length; j++) {
        after += widths[j];
      }
      return widths[i] / 2 + after + 8 + 12;
    });
    // Sequential stagger: one letter after another, never stacked
    // end-to-end, so even long labels finish inside the flight window.
    final stagger = chars.isEmpty
        ? 0.0
        : math.min(0.06, 0.40 / chars.length);

    return GestureDetector(
      onTap: _start,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: _showCheck ? 48.0 : _labelWidth(context),
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _showCheck
              ? const Color(0xFF22C55E)
              : scheme.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(_showCheck ? 24 : 12),
        ),
        child: _showCheck
            ? AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final progress =
                      ((_controller.value - 0.82) / 0.18).clamp(0.0, 1.0);
                  return CustomPaint(
                    key: const Key('binSuccessCheck'),
                    size: const Size(28, 28),
                    painter: _CheckPainter(progress),
                  );
                },
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Label letters: each one hops into the bin from above.
                  // Horizontal leg first (arcing up), then a purely
                  // vertical drop through the lid gap into the bin mouth.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < chars.length; i++)
                        AnimatedBuilder(
                          animation: _controller,
                          builder: (context, child) {
                            final start = 0.15 + stagger * i;
                            final end = (start + 0.30).clamp(0.0, 0.70);
                            final p = Interval(start, end,
                                    curve: Curves.linear)
                                .transform(_controller.value);
                            final xProgress =
                                (p / 0.6).clamp(0.0, 1.0);
                            final dx = sign *
                                distances[i] *
                                Curves.easeIn.transform(xProgress);
                            double dy;
                            if (p < 0.6) {
                              // Rising arc during the horizontal leg.
                              dy = -_hopHeight *
                                  math.sin(math.pi * p / 0.6);
                            } else {
                              // Vertical drop through the lid gap.
                              dy = _dropDistance * (p - 0.6) / 0.4;
                            }
                            // Clamped: 0.85/0.15 are not exact binary
                            // fractions, so the raw fade can land a hair
                            // below 0.0 at p == 1 (float -2.2e-16), which
                            // trips Opacity's range assertion.
                            final opacity = (p < 0.85
                                    ? 1.0
                                    : 1.0 - (p - 0.85) / 0.15)
                                .clamp(0.0, 1.0);
                            return Opacity(
                              opacity: opacity,
                              child: Transform.translate(
                                offset: Offset(dx, dy),
                                child: Transform.scale(
                                  scale: 1.0 - 0.85 * p,
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: Text(chars[i],
                              key: Key('binLetter_$i'),
                              style: _labelStyle(context).copyWith(
                                color: scheme.error,
                                fontWeight: FontWeight.w700,
                              )),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  // ONE bin: an open-top body with a single lid sitting
                  // flush on its rim. No detached line, no second lid.
                  // Clip.none so the raised lid is not cut off.
                  SizedBox(
                    key: const Key('binIcon'),
                    width: 24,
                    height: 28,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Bin body: open at the top (the mouth letters
                        // drop through), closed at the bottom.
                        Positioned(
                          left: 3,
                          bottom: 0,
                          width: 18,
                          height: 20,
                          child: Container(
                            key: const Key('binBody'),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                    color: scheme.error, width: 2),
                                right: BorderSide(
                                    color: scheme.error, width: 2),
                                bottom: BorderSide(
                                    color: scheme.error, width: 2),
                              ),
                              borderRadius:
                                  const BorderRadius.vertical(
                                bottom: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        // THE single lid: flush on the rim at rest
                        // (bottom: 20 == body top), rising straight up
                        // and holding during the hops, then back down.
                        Positioned(
                          left: 1,
                          bottom: 20,
                          width: 22,
                          height: 4,
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(
                                    0,
                                    -_lidLift(_controller.value) *
                                        _lidLiftDistance),
                                child: child,
                              );
                            },
                            child: Container(
                              key: const Key('binLid'),
                              decoration: BoxDecoration(
                                color: scheme.error,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Draws a success check stroke-by-stroke: the circle arc sweeps first
/// (progress 0 → 0.55), then the check path draws (0.55 → 1).
class _CheckPainter extends CustomPainter {
  _CheckPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    final circleProgress = (progress / 0.55).clamp(0.0, 1.0);
    if (circleProgress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -0.5 * 3.14159,
        circleProgress * 2 * 3.14159,
        false,
        stroke,
      );
    }
    if (progress > 0.55) {
      final checkProgress = ((progress - 0.55) / 0.45).clamp(0.0, 1.0);
      final path = Path()
        ..moveTo(size.width * 0.28, size.height * 0.54)
        ..lineTo(size.width * 0.46, size.height * 0.72)
        ..lineTo(size.width * 0.74, size.height * 0.32);
      final metrics = path.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final extract =
            metrics.first.extractPath(0, metrics.first.length * checkProgress);
        canvas.drawPath(extract, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}
