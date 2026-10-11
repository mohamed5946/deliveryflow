import 'package:flutter/material.dart';

/// Buttery in-app page transition: subtle slide + fade.
///
/// GPU-cheap (transform + opacity only), ~300ms, easeOutCubic.
/// Used for all in-app navigation pushes instead of [MaterialPageRoute].
class SmoothPageRoute<T> extends PageRouteBuilder<T> {
  SmoothPageRoute({
    required Widget Function(BuildContext context) builder,
    super.settings,
  }) : super(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration:
              const Duration(milliseconds: 250),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeOutCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(
                opacity: curved,
                child: child,
              ),
            );
          },
        );
}
