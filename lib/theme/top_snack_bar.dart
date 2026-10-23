import 'dart:async';

import 'package:flutter/material.dart';

/// v27.4: top snackbars — the app's single notification-bar style.
///
/// Mohamed asked for every in-app bar to slide DOWN from the top of
/// the screen (inside the app, below the status bar) instead of rising
/// from the bottom, where it covered the bottom navigation bar. All
/// former `ScaffoldMessenger.showSnackBar` call sites route through
/// [showTopSnackBar]; the visual is an overlay card with a slide-down
/// animation, auto-dismiss, swipe-up-to-dismiss and an optional action
/// button. Message texts and durations are unchanged from the old
/// snackbars (default duration stays the snackbar-standard 4s).

OverlayEntry? _activeEntry;
Timer? _activeTimer;
final _bannerKey = GlobalKey<_TopBannerState>();

/// Shows [message] as a top banner in [context]'s overlay, replacing
/// any banner currently on screen.
void showTopSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  _removeActiveEntry();
  final overlay = Overlay.of(context);
  final entry = OverlayEntry(
    builder: (_) => _TopBanner(
      key: _bannerKey,
      message: message,
      actionLabel: actionLabel,
      onAction: () {
        onAction?.call();
        dismissTopSnackBar();
      },
      onDismissed: _removeActiveEntry,
    ),
  );
  _activeEntry = entry;
  overlay.insert(entry);
  _activeTimer = Timer(duration, dismissTopSnackBar);
}

/// Dismisses the visible top banner (animated) if there is one.
void dismissTopSnackBar() {
  _activeTimer?.cancel();
  _activeTimer = null;
  final state = _bannerKey.currentState;
  if (state == null) {
    _removeActiveEntry();
    return;
  }
  state.dismiss();
}

/// Hides the visible top banner immediately (no animation).
void hideTopSnackBar() {
  _activeTimer?.cancel();
  _activeTimer = null;
  _removeActiveEntry();
}

void _removeActiveEntry() {
  _activeTimer?.cancel();
  _activeTimer = null;
  _activeEntry?.remove();
  _activeEntry = null;
}

class _TopBanner extends StatefulWidget {
  const _TopBanner({
    super.key,
    required this.message,
    required this.onDismissed,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismissed;

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1.4),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> dismiss() async {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    await _ctrl.reverse();
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final topInset = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topInset + 12,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -150) dismiss();
          },
          child: Material(
            color: scheme.inverseSurface,
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.actionLabel != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: widget.onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.inversePrimary,
                      ),
                      child: Text(widget.actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
