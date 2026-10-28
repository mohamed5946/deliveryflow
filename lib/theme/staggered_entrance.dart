import 'dart:async';

import 'package:flutter/material.dart';

/// v27.30: staggered list entrance, modelled on the flutter_animate
/// staggered-lists technique from the reference video Mohamed sent:
/// items appear ONE BY ONE with fadeIn + slideY on screen entry.
///
/// Rules (all from the brief + the video's scrolling lesson):
/// * Each item fades in and slides up from ~20% of its own height
///   ([_slideFraction]), with a stagger of [_stagger] per item.
/// * CAP: the delay is min(index, [_capIndex]) * [_stagger], so items
///   beyond the first screen never wait seconds — a long list stays
///   fast and scrolling never leaves items invisible.
/// * Entry-only: an item animates on its first mount inside a
///   [StaggeredScope] and is then marked seen, so data refreshes,
///   stream updates and scrolling back never re-trigger or flicker.
///   A fresh scope (screen re-entry) replays the stagger.
/// * Reduce-motion: items appear immediately, no stagger.
/// * Cheap only: opacity + transform, no shader, no blur, 120fps-safe.
/// * No data/order/value/behaviour change — entrance animation only.
///
/// Hand-rolled (no flutter_animate dependency): the same interval
/// math the video shows, without adding a package to the build.
class StaggeredScope extends StatefulWidget {
  const StaggeredScope({super.key, required this.child});

  final Widget child;

  static StaggeredScopeState? maybeOf(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<_StaggeredInherited>();
    return inherited?.state;
  }

  @override
  State<StaggeredScope> createState() => StaggeredScopeState();
}

class StaggeredScopeState extends State<StaggeredScope> {
  final Set<int> _seen = {};

  bool isSeen(int index) => _seen.contains(index);

  void markSeen(int index) => _seen.add(index);

  @override
  Widget build(BuildContext context) {
    return _StaggeredInherited(state: this, child: widget.child);
  }
}

class _StaggeredInherited extends InheritedWidget {
  const _StaggeredInherited({required this.state, required super.child});

  final StaggeredScopeState state;

  @override
  bool updateShouldNotify(_StaggeredInherited old) => false;
}

/// v27.31: tab-visibility replay.
///
/// The 5 main tabs live in a go_router IndexedStack, so their widgets
/// stay mounted when the user switches tabs — the v27.30 scopes therefore
/// animated only on first entry after launch. Mohamed explicitly demanded
/// replay on EVERY entry, including tab switches (even 100 times a
/// minute). The shell publishes the selected tab index here (see
/// router.dart, which syncs it post-frame and on destination taps);
/// [TabReplayScope] turns each re-activation of its tab into a new
/// generation, and [StaggeredItem] replays when its generation changes.
/// Data refreshes do NOT change the generation, so they still never
/// re-trigger or flicker. Scroll position is preserved: nothing
/// remounts — items restart their animation in place.
final ValueNotifier<int> currentTabIndexNotifier = ValueNotifier<int>(0);

/// Generation counter published by [TabReplayScope]. Items read it via
/// dependOnInheritedWidget, so a generation bump re-runs their
/// didChangeDependencies and replays the entrance.
class _StaggeredGeneration extends InheritedWidget {
  const _StaggeredGeneration({required this.generation, required super.child});

  final int generation;

  static int maybeOf(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<_StaggeredGeneration>();
    return inherited?.generation ?? 0;
  }

  @override
  bool updateShouldNotify(_StaggeredGeneration old) =>
      old.generation != generation;
}

/// Wraps a tab screen's list content: every time [tabIndex] becomes
/// the selected tab again (after having been inactive), the generation
/// bumps and every [StaggeredItem] below replays its entrance.
/// Pushed routes do not need this — remount replays for them already.
class TabReplayScope extends StatefulWidget {
  const TabReplayScope(
      {super.key, required this.tabIndex, required this.child});

  final int tabIndex;
  final Widget child;

  @override
  State<TabReplayScope> createState() => _TabReplayScopeState();
}

class _TabReplayScopeState extends State<TabReplayScope> {
  int _generation = 0;
  late bool _wasActive;

  void _onTabChanged() {
    final active = currentTabIndexNotifier.value == widget.tabIndex;
    if (active && !_wasActive) {
      _wasActive = true;
      setState(() => _generation++);
    } else if (!active) {
      _wasActive = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _wasActive = currentTabIndexNotifier.value == widget.tabIndex;
    currentTabIndexNotifier.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    currentTabIndexNotifier.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StaggeredGeneration(generation: _generation, child: widget.child);
  }
}

/// on entry: same parameters, but every item is wrapped in a
/// [StaggeredItem] inside one [StaggeredScope]. Use it for the app's
/// item lists (history, day orders, notifications, diagnostics log,
/// search results) so they all share the same entrance behaviour.
class StaggeredList extends StatelessWidget {
  const StaggeredList({
    super.key,
    this.padding,
    required this.itemCount,
    required this.itemBuilder,
  });

  final EdgeInsetsGeometry? padding;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return StaggeredScope(
      child: ListView.builder(
        padding: padding,
        itemCount: itemCount,
        itemBuilder: (ctx, i) => StaggeredItem(
          index: i,
          child: itemBuilder(ctx, i) ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class StaggeredItem extends StatefulWidget {
  const StaggeredItem({super.key, required this.index, required this.child});

  /// Stagger per item, matching the video's 80ms interval.
  static const stagger = Duration(milliseconds: 80);

  /// Items at or beyond this index share the capped delay.
  static const capIndex = 7;

  /// Single-item animation length.
  static const itemDuration = Duration(milliseconds: 300);

  /// Slide distance as a fraction of the item's own height
  /// (the video's slideY begin ~0.2).
  static const slideFraction = 0.2;

  /// Capped delay for [index] — the video's scrolling lesson.
  static Duration delayFor(int index) =>
      stagger * (index < capIndex ? index : capIndex);

  final int index;
  final Widget child;

  @override
  State<StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  Timer? _timer;
  bool _immediate = false;
  bool _initialized = false;
  int? _playedGeneration;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: StaggeredItem.itemDuration,
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  void _play() {
    _immediate = false;
    _controller.reset();
    _timer?.cancel();
    _timer = Timer(StaggeredItem.delayFor(widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inherited lookups (MediaQuery, scope, generation) are not allowed
    // in initState; this runs before the first build, and again whenever
    // an inherited dependency changes — including a TabReplayScope
    // generation bump, which is exactly the replay signal.
    final generation = _StaggeredGeneration.maybeOf(context);
    if (_initialized && generation == _playedGeneration) return;
    _initialized = true;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scope = StaggeredScope.maybeOf(context);
    if (reduceMotion) {
      // Reduce-motion: appear immediately, never animate. (Do not
      // record the generation: if reduce-motion is later turned off,
      // the item must still play its entrance.)
      _timer?.cancel();
      _immediate = true;
      return;
    }
    // Same generation already played (refresh / scroll-back): appear
    // immediately, never re-animate. A NEW generation (tab re-entry)
    // or a fresh scope (route remount) replays the entrance.
    if (scope != null &&
        scope.isSeen(widget.index) &&
        generation == _playedGeneration) {
      _immediate = true;
      return;
    }
    scope?.markSeen(widget.index);
    _playedGeneration = generation;
    _play();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_immediate) return widget.child;
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) {
        final t = _progress.value;
        return Opacity(
          opacity: t,
          child: FractionalTranslation(
            translation: Offset(0, StaggeredItem.slideFraction * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
