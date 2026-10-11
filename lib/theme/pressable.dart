import 'package:flutter/material.dart';

/// Tactile press wrapper: gives any child a physical "pressed" feel.
///
/// On press down the child scales to 0.96 over ~120ms (easeOut) and
/// springs back on release/cancel. The animation plays even when
/// [onTap] is null, so disabled buttons still feel tactile.
///
/// GPU-cheap: transform only, no layout work, no continuous animation.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final BorderRadius? borderRadius;

  /// When true, only the press-scale animation plays and [onTap] is never
  /// invoked — use when nested inside another tap handler (e.g. InkWell)
  /// so the tap doesn't fire twice.
  final bool scaleOnly;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) {
        _setPressed(false);
        if (!widget.scaleOnly) widget.onTap?.call();
      },
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
