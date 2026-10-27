import 'dart:async';

import 'package:flutter/material.dart';

/// v27.24: "bin eats the label" delete button.
///
/// Shared by every confirmed delete action in the app. The sequence is:
/// 1. Idle: `[label] [bin]` — a normal destructive button.
/// 2. Tap (this tap IS the confirmation — the button only ever appears
///    inside an existing Yes/No confirmation dialog, never standalone):
///    the bin lid swings open and the label's letters fly one by one
///    toward the bin, shrinking and fading as they are "eaten".
/// 3. Done: the button shrinks to a circle holding just the bin icon.
/// 4. Only then [onConfirmed] fires, and the caller executes the actual
///    deletion. Nothing is deleted before the animation completes, and
///    the button ignores further taps while animating.
///
/// There is no reduce-motion setting in DeliveryFlow (checked v27.24), so
/// the animation always plays — but it is capped at ~1s total and runs
/// only on explicit delete taps, never on its own.
///
/// No blur is used here, so no RepaintBoundary is required.
class BinEatingDeleteButton extends StatefulWidget {
  const BinEatingDeleteButton({
    super.key,
    required this.label,
    required this.onConfirmed,
  });

  /// The button's label (e.g. the localized "Delete" or "Yes").
  final String label;

  /// Called exactly once, after the eat + shrink animation completes.
  /// Callers pop their confirmation dialog with `true` here and then
  /// execute the deletion.
  final VoidCallback onConfirmed;

  @override
  State<BinEatingDeleteButton> createState() => _BinEatingDeleteButtonState();
}

enum _Phase { idle, eating, done }

class _BinEatingDeleteButtonState extends State<BinEatingDeleteButton> {
  _Phase _phase = _Phase.idle;
  int _eaten = 0;
  Timer? _timer;

  /// Letters are eaten at most this fast in total, so long labels do not
  /// stretch the animation past ~1s.
  Duration get _letterGap {
    final len = widget.label.characters.length;
    if (len == 0) return Duration.zero;
    final ms = 700 ~/ len;
    return Duration(milliseconds: ms.clamp(40, 90));
  }

  double _labelWidth(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge ??
        const TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
    final painter = TextPainter(
      text: TextSpan(text: widget.label, style: style),
      textDirection: Directionality.of(context),
    )..layout();
    // label + bin icon + gaps + horizontal padding.
    return painter.width + 24 + 16 + 32;
  }

  void _start() {
    if (_phase != _Phase.idle) return; // ignore taps while animating.
    final len = widget.label.characters.length;
    if (len == 0) {
      setState(() => _phase = _Phase.done);
      Future.delayed(const Duration(milliseconds: 300), _finish);
      return;
    }
    setState(() => _phase = _Phase.eating);
    _timer = Timer.periodic(_letterGap, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _eaten++);
      if (_eaten >= len) {
        timer.cancel();
        setState(() => _phase = _Phase.done);
        Future.delayed(const Duration(milliseconds: 300), _finish);
      }
    });
  }

  void _finish() {
    if (!mounted) return;
    if (_phase == _Phase.done) widget.onConfirmed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDone = _phase == _Phase.done;
    final isEating = _phase == _Phase.eating;
    final chars = widget.label.characters.toList();
    // Letters slide toward the bin, which sits at the trailing end.
    final slide = Directionality.of(context) == TextDirection.rtl ? -14.0 : 14.0;
    final width = isDone ? 48.0 : _labelWidth(context);

    return GestureDetector(
      onTap: _start,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: width,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDone
              ? scheme.error
              : scheme.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(isDone ? 24 : 12),
        ),
        child: isDone
            ? Icon(Icons.delete_outline_rounded,
                size: 22, color: scheme.onError)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Label letters: eaten ones vanish toward the bin.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < chars.length; i++)
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: i < _eaten ? 0 : 1,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            transform: Matrix4.translationValues(
                                i < _eaten ? slide : 0, 0, 0),
                            child: Text(chars[i],
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: scheme.error,
                                      fontWeight: FontWeight.w700,
                                    )),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  // Bin: lid swings open while eating.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedRotation(
                        turns: isEating ? -0.18 : 0,
                        duration: const Duration(milliseconds: 250),
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
