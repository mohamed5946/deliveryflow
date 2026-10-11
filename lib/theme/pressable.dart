import 'package:flutter/material.dart';

/// Tactile press wrapper: gives any child a physical "pressed" feel,
/// like pushing a real button down.
///
/// On press down the child dips ~4px downward with a very slight scale
/// (120ms, easeOut) and springs back up on release/cancel. The animation
/// plays even when [onTap] is null, so disabled buttons still feel tactile.
///
/// GPU-cheap: composited transforms only, no layout work, no continuous
/// animation.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  /// How far (in logical pixels) the child dips down while pressed.
  final double pressedDip;

  final BorderRadius? borderRadius;

  /// When true, only the press animation plays and [onTap] is never
  /// invoked — use when nested inside another tap handler (e.g. InkWell)
  /// so the tap doesn't fire twice.
  final bool scaleOnly;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.pressedDip = 4.0,
    this.borderRadius,
    this.scaleOnly = false,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 120);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) {
        _setPressed(false);
        if (!widget.scaleOnly) widget.onTap?.call();
      },
      onTapCancel: () => _setPressed(false),
      // Outer: the physical dip down. Inner: subtle scale about the
      // center. Both are composited transforms — cheap on the GPU.
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          0,
          _pressed ? widget.pressedDip : 0.0,
          0,
        ),
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1.0,
          duration: duration,
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
