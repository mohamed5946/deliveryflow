import 'package:flutter/material.dart';

/// v27.24: "bin eats the label" delete button. Reworked in v27.28 after a
/// field report: the old version only faded letters in place, so on a
/// real phone the flight was invisible ("letters just disappear").
///
/// Shared by every confirmed delete action in the app (6 call sites). The
/// sequence, driven by a single 1400 ms controller, is:
/// 1. Lid opens: the bin lid visibly swings up (~200 ms).
/// 2. Letters fly: each label letter travels on a real trajectory toward
///    the bin mouth — translating the full distance to the bin while
///    shrinking — and only fades once it is almost inside the bin.
///    Letters are staggered so the flight reads as a stream, not a blink.
/// 3. Lid closes: once every letter is inside, the lid swings shut.
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

  /// Called exactly once, after the lid → flight → lid → check sequence
  /// completes (or immediately under reduce-motion). Callers pop their
  /// confirmation dialog with `true` here and then execute the deletion.
  final VoidCallback onConfirmed;

  @override
  State<BinEatingDeleteButton> createState() => _BinEatingDeleteButtonState();
}

/// Total sequence length: lid 200 ms + flight + lid-close + check draw.
/// Stays inside the 1.2–1.5 s budget even for long labels.
const _totalDuration = Duration(milliseconds: 1400);

class _BinEatingDeleteButtonState extends State<BinEatingDeleteButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _animating = false;
  bool _lidOpen = false;
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

  /// Lid closes once every letter has landed (t >= 0.70); the check
  /// appears once the lid is shut (t >= 0.82).
  void _onTick() {
    final t = _controller.value;
    var changed = false;
    if (_lidOpen && t >= 0.70) {
      _lidOpen = false;
      changed = true;
    }
    if (!_showCheck && t >= 0.82) {
      _showCheck = true;
      changed = true;
    }
    if (changed && mounted) setState(() {});
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
      _lidOpen = true;
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chars = widget.label.characters.toList();
    final widths = _letterWidths(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final sign = rtl ? -1.0 : 1.0;
    // Distance from each letter's centre to the bin centre: the letters
    // after it, plus the 8 px gap, plus half the 22 px bin.
    final distances = List<double>.generate(chars.length, (i) {
      var after = 0.0;
      for (var j = i + 1; j < chars.length; j++) {
        after += widths[j];
      }
      return widths[i] / 2 + after + 8 + 11;
    });

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
                  // Label letters: each one flies the full distance into
                  // the bin mouth, shrinking as it goes, fading only at
                  // the very end of its flight.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < chars.length; i++)
                        AnimatedBuilder(
                          animation: _controller,
                          builder: (context, child) {
                            final n = chars.length;
                            final start = 0.15 + 0.25 * i / n;
                            final end = (start + 0.30).clamp(0.0, 0.70);
                            final p = Interval(start, end,
                                    curve: Curves.easeIn)
                                .transform(_controller.value);
                            final opacity =
                                p < 0.75 ? 1.0 : 1.0 - (p - 0.75) / 0.25;
                            return Opacity(
                              opacity: opacity,
                              child: Transform.translate(
                                offset: Offset(sign * distances[i] * p, 0),
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
                  // Bin: lid swings visibly open, then shut after the
                  // letters are inside.
                  Column(
                    key: const Key('binIcon'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedRotation(
                        key: const Key('binLid'),
                        turns: _lidOpen ? -0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 22,
                          height: 4,
                          decoration: BoxDecoration(
                            color: scheme.error,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Icon(Icons.delete_outline_rounded,
                          size: 22, color: scheme.error),
                    ],
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
