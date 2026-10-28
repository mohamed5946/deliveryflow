import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';

import '../../core/database/models.dart';
import '../../core/date_time/hour_blocks.dart';
import '../../core/date_time/time_format.dart';
import '../../core/date_time/week_calendar.dart';
import '../../theme/design_system.dart';
import '../../theme/staggered_entrance.dart';
import '../../theme/bin_eating_delete_button.dart';

/// v27.13 Home hour blocks for one selected day, full screen width.
///
/// Rendered below Quick actions on the dashboard. Kept as a public
/// widget (not a dashboard method) so the confirmation-dialog flow is
/// widget-testable without pumping the whole dashboard.
///
/// - Header: the day's start–end times (always visible for a working
///   day) plus a "worked X — remaining Y" summary. Break hours count
///   as neither; the current hour counts as remaining.
/// - One wide rectangle per work hour, end-exclusive, labelled by its
///   start hour. Colours: worked = green, current = blue, upcoming =
///   neutral outline, break = orange.
/// - Day off: Day off only, no blocks. No schedule: neutral empty
///   state, no invented hours.
/// - TAP-VS-SWIPE RESOLUTION (v27.13 decision): a TAP on a block does
///   nothing at all (it never toggles). Every mutation goes through
///   a swipe action, the Assign button, or the schedule edit screen.
///   This removes the v27.12 tap-toggle entirely, so a horizontal
///   drag can never also fire a tap — there is exactly one gesture
///   path per mutation, and no gesture can fire two of them.
///   Exception: tapping a PROTECTED block shows the protection
///   explanation (it changes nothing, it only explains the lock).
/// - SWIPE (v27.13, reveal fixed in v27.14, layering redesigned in
///   v27.15, true Delete in v27.19): each block is horizontally
///   draggable and grows its action panel as it is dragged — swipe
///   LEFT grows a red Delete panel from the right edge, swipe RIGHT
///   grows a Break panel from the left edge (a break block's right
///   action is Restore instead, since it is already a break).
///   v27.19: Delete is a REAL deletion now ([onDelete]), offered on
///   work blocks AND break blocks alike — deleting a break block
///   removes it completely, it does NOT restore it. Break/Restore
///   ([onToggleBreak]) is unchanged: work -> orange break,
///   break -> work. Swiping alone changes NOTHING: only tapping a
///   fully built action opens the Yes/No confirmation dialog, and
///   only Yes invokes the callback. No / dismiss changes nothing.
///   The reveal is a plain drag + snap (no slidable dependency was
///   added; the widget is a small custom horizontal-drag reveal,
///   smooth standard motion, no looping animation). v27.14 fix: at
///   rest NO action widget is rendered at all (v27.13 rendered both
///   actions full-width behind the translucent block, so they peeked
///   through on both sides at once); while dragging, only the
///   dragged side's panel exists, its width is exactly the drag
///   distance, and the panel was opaque and painted OVER the block.
///   v27.15 redesign (user complaint 2026-10-25: the v27.14 panel
///   sat flat ON TOP of the block and the two did not read as one
///   piece): the panel is now UNDER the hour block. The block is
///   the top layer, a raised card with real Material elevation +
///   shadow so it reads 3D, and the panel emerges from underneath
///   its dragged edge. Block and panel share exactly the same
///   height, are vertically aligned, and touch with zero spacing:
///   the outer corners stay rounded, the touching inner edges are
///   square, so the pair joins into one continuous bar with no gap,
///   no seam, and no overlapping text. The block's time/status (and
///   lock/Protected label) stay fully readable at all times — the
///   panel never paints over block content. To achieve that with a
///   fixed full-width bar, the block yields its dragged edge as the
///   panel grows (its leading edge and content never move, so
///   nothing is ever clipped off — a whole-block translation would
///   push the time label off the leading edge); the panel stays
///   attached to that edge, so the pair stays one continuous bar.
///   The panel still builds piece by piece with drag distance, eats
///   piece by piece on drag-back, is exactly zero-width (and
///   unrendered) at rest, and snaps open past half the panel width
///   or closed below it (~200ms easeOut; full width 96px, unchanged
///   from v27.14).
/// - ASSIGN (v27.13, replaces the v27.12 + / − hour buttons, which
///   are deleted): one full-width button below the blocks, same
///   size/shape as a block, labelled Assign / تسجيل. It opens a
///   picker of AVAILABLE hours — wall-clock hours 0–23 minus every
///   existing block hour (work AND break; a break hour is already a
///   block, and restoring it is the swipe-restore path). Picking an
///   hour asks the add confirmation; only Yes adds the block, via
///   [onAssignHour] (the parent saves through the schedule save
///   chokepoint and logs it, as before). The Assign button is also
///   shown for a day off / no schedule, where picking an hour
///   creates a one-hour working shift.
/// - PROTECTION (v27.13): blocks listed in [protectedBlockStarts]
///   contain real orders and cannot be deleted or broken. They show
///   a lock + Protected label, cannot be swiped open at all, and
///   tapping one shows the explanation dialog instead of any
///   confirmation. The widget never reads the database: the parent
///   computes the set from the day's order record (countOnly entries
///   excluded — see [protectedBlockStarts]).
class DayHoursSection extends StatelessWidget {
  /// The selected day's schedule, or null when the week has no
  /// schedule for it (neutral empty state).
  final DailySchedule? day;

  /// Calendar date of [day] (used for worked/upcoming classification).
  final DateTime selectedDay;

  /// "Now" for classification; defaults to [DateTime.now] in the
  /// dashboard, injectable in tests for a fixed clock.
  final DateTime now;

  final TimeFormatMode timeFormat;
  final bool arabic;

  /// Fired (after Yes) when a block is toggled work <-> break.
  final ValueChanged<int> onToggleBreak;

  /// Fired (after Yes) when a block is deleted outright (v27.19).
  /// Unlike [onToggleBreak], this removes the hour from the day
  /// completely — work blocks and break blocks alike.
  final ValueChanged<int> onDelete;

  /// Fired (after Yes) when an hour picked in the Assign picker is
  /// added as a new work block (wall-clock hour 0..23).
  final ValueChanged<int> onAssignHour;

  /// Extended block starts that contain real orders and are
  /// therefore locked against delete/break. Empty by default.
  final Set<int> protectedBlockStarts;

  /// v27.24 liquid trial: home-only opt-in for this section's card.
  /// Defaults to false (exact old glass); the dashboard passes the
  /// setting. This widget is only used on the home tab.
  final bool liquid;

  const DayHoursSection({
    super.key,
    required this.day,
    required this.selectedDay,
    required this.now,
    required this.timeFormat,
    this.liquid = false,
    required this.arabic,
    required this.onToggleBreak,
    required this.onDelete,
    required this.onAssignHour,
    this.protectedBlockStarts = const {},
  });

  String _fmt(BuildContext context, int minutes) =>
      formatMinutesWithContext(context, minutes, timeFormat, arabic: arabic);

  /// Confirmation gate: returns true only on an explicit Yes tap.
  /// No / dismiss / back returns false and changes nothing.
  Future<bool> _confirm(BuildContext context, bool isAdd) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAdd ? l10n.confirmAddBlock : l10n.confirmDeleteBlock),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.no),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.yes),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// v27.24: delete-only confirmation. Same Yes/No gate as [_confirm],
  /// but the Yes button is the bin-eats-label button: its label letters
  /// are eaten by the bin, it shrinks to a circle, and only then does
  /// the dialog pop (true) so the caller deletes. Break keeps the plain
  /// [_confirm] dialog — Break is a different action, never animated here.
  Future<bool> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.confirmDeleteBlock),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.no),
          ),
          BinEatingDeleteButton(
            label: l10n.yes,
            onConfirmed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Protection explanation: shown instead of any confirmation when
  /// a protected block is tapped. Changes nothing.
  Future<void> _explainProtected(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.blockProtectedHasOrders),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  /// Assign picker: available hours for [day], then the add
  /// confirmation; only Yes invokes [onAssignHour].
  Future<void> _pickAssignHour(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final hours = availableHoursForAssign(day);
    if (hours.isEmpty) return;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.assignHourTitle),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: ListView(
            children: [
              for (final h in hours)
                ListTile(
                  key: ValueKey('assign-hour-$h'),
                  title: Text(_fmt(context, h * 60)),
                  onTap: () => Navigator.pop(ctx, h),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    if (await _confirm(context, true)) onAssignHour(picked);
  }

  /// The Assign button: full-width rectangle, same size/shape as an
  /// hour block (same padding, radius and border treatment).
  Widget _assignButton(BuildContext context, AppLocalizations l10n) {
    final color = LiquidPalette.primaryBlue;
    return InkWell(
      key: const ValueKey('day-assign-button'),
      onTap: () => _pickAssignHour(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              l10n.assign,
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: color, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final d = day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.dayHoursSection),
        GlassCard(
          liquid: liquid,
          child: d == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.noScheduleForDay,
                      style: text.bodyMedium?.copyWith(
                          color:
                              text.bodyMedium?.color?.withValues(alpha: 0.65)),
                    ),
                    const SizedBox(height: 10),
                    _assignButton(context, l10n),
                  ],
                )
              : !d.isWorkingDay
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(l10n.dayOff,
                            style: text.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        _assignButton(context, l10n),
                      ],
                    )
                  : _workingBody(context, d, l10n),
        ),
      ],
    );
  }

  Widget _workingBody(
      BuildContext context, DailySchedule d, AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    final starts = hourBlockStarts(d);
    final breaks = breakBlockStarts(d);
    final summary = summarizeBlocks(day: d, dayDate: selectedDay, now: now);
    final dayName = WeekCalendar.dateKey(selectedDay);

    return TabReplayScope(
      tabIndex: 0,
      child: StaggeredScope(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Always-visible header: start–end + worked/remaining summary.
            Text(
              // Generated placeholders are alphabetical: (end, start).
              l10n.dayShiftRange(_fmt(context, effectiveEndMinutes(d)),
                  _fmt(context, d.startMinutes)),
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              // Generated placeholders are alphabetical: (remaining, worked).
              l10n.workedRemaining(summary.remaining, summary.worked),
              style: text.bodyMedium,
            ),
            if (breaks.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(l10n.breakHoursCount(breaks.length),
                  style: text.bodySmall?.copyWith(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w700)),
            ],
            if (d.breakDurationMinutes > 0) ...[
              const SizedBox(height: 2),
              Text(l10n.registeredBreak(d.breakDurationMinutes),
                  style: text.bodySmall?.copyWith(
                      color: text.bodySmall?.color?.withValues(alpha: 0.65))),
            ],
            const SizedBox(height: 10),
            // Legend (small, if space allows — a single wrapping row).
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _legendDot(LiquidPalette.success, l10n.hourWorked),
                _legendDot(LiquidPalette.primaryBlue, l10n.hourCurrent),
                _legendDot(Colors.grey, l10n.hourUpcoming),
                _legendDot(Colors.orange, l10n.hourBreak),
              ],
            ),
            const SizedBox(height: 10),
            // Hour blocks, full width, one per work hour, swipeable.
            for (final start in starts)
              StaggeredItem(
                index: starts.indexOf(start),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _block(context, d, start, breaks.contains(start), l10n,
                      keySuffix: dayName),
                ),
              ),
            const SizedBox(height: 2),
            // Assign: the only way to add a new work hour (v27.13).
            _assignButton(context, l10n),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _block(BuildContext context, DailySchedule d, int start, bool isBreak,
      AppLocalizations l10n,
      {required String keySuffix}) {
    final state = classifyBlock(
      day: selectedDay,
      now: now,
      blockStart: start,
      isBreak: isBreak,
    );
    final Color color;
    final Color bg;
    final String stateLabel;
    switch (state) {
      case HourBlockState.worked:
        color = LiquidPalette.success;
        bg = color.withValues(alpha: 0.14);
        stateLabel = l10n.hourWorked;
      case HourBlockState.current:
        color = LiquidPalette.primaryBlue;
        bg = color.withValues(alpha: 0.20);
        stateLabel = l10n.hourCurrent;
      case HourBlockState.upcoming:
        color = Colors.grey;
        bg = Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.55);
        stateLabel = l10n.hourUpcoming;
      case HourBlockState.onBreak:
        color = Colors.orange;
        bg = color.withValues(alpha: 0.16);
        stateLabel = l10n.hourBreak;
    }
    final isProtected = protectedBlockStarts.contains(start);
    // The card shell (raised Material + border + radius) is rendered
    // by _SwipeableBlock so the inner edge can go square while a
    // panel is attached (v27.15: one continuous bar, no seam). This
    // is only the content: padding + icon + time + lock + status.
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(
            isBreak
                ? Icons.coffee_rounded
                : state == HourBlockState.current
                    ? Icons.play_arrow_rounded
                    : Icons.schedule_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _fmt(context, start),
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: color, fontSize: 16),
            ),
          ),
          if (isProtected) ...[
            Icon(Icons.lock_rounded, color: color, size: 14),
            const SizedBox(width: 4),
            Text(l10n.blockProtected,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(width: 8),
          ],
          Text(stateLabel,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
    // Tap does nothing for ordinary blocks (v27.13 tap-vs-swipe
    // resolution); a protected block's tap only explains the lock.
    final tappable = GestureDetector(
      onTap: isProtected ? () => _explainProtected(context) : () {},
      child: content,
    );
    return _SwipeableBlock(
      key: ValueKey('day-hour-block-$keySuffix-$start'),
      blockStart: start,
      isBreak: isBreak,
      isProtected: isProtected,
      cardColor: color,
      cardBg: bg,
      onDelete: () async {
        if (await _confirmDelete(context)) onDelete(start);
      },
      onBreak: () async {
        if (await _confirm(context, isBreak)) onToggleBreak(start);
      },
      deleteLabel: l10n.delete,
      breakLabel: isBreak ? l10n.blockRestore : l10n.blockBreak,
      child: tappable,
    );
  }
}

/// v27.15 custom horizontal-drag panel (no new dependency:
/// flutter_slidable is not in pubspec.yaml, and a full slidable
/// package would be heavy for one row type).
///
/// LAYERING (supersedes v27.14, where the panel painted OVER the
/// block): the action panel is UNDER the hour block. In the Stack
/// the panel is the first child (paints first) and the block is the
/// top layer: a raised card — Material elevation 6 with a real
/// shadow — so it reads 3D, and the panel emerges from underneath
/// its dragged edge, its shadow falling onto the panel. The block
/// NEVER gets painted over: the panel never overlaps block content.
///
/// CONTIGUOUS, NO GAP, NO SEAM: panel and block share exactly the
/// same height (the panel is stretched top-to-bottom to the Stack
/// height, which the block itself determines) and touch with zero
/// spacing — the panel is anchored at the dragged edge and the
/// block is padded on that side by exactly the panel width, so the
/// panel's inner edge and the block's edge are the same line. The
/// outer corners stay rounded (14px); the touching inner edges are
/// square on BOTH pieces, and the block's border is omitted on the
/// touching side, so the two pieces join into one continuous bar
/// with no gap, no seam line, and no overlapping text.
///
/// WHY THE BLOCK YIELDS ITS EDGE INSTEAD OF TRANSLATING: the bar
/// is fixed full-width, so a whole-block translation by the drag
/// distance would push the time label off the leading edge and
/// break the "fully readable at all times" rule. Instead the
/// block's leading edge and content never move; only its dragged
/// edge retreats as the panel grows, and the panel stays attached
/// to that edge. The pair still reads as one bar, and the block's
/// time, status, and lock/Protected label stay fully visible.
///
/// BUILD PIECE BY PIECE (unchanged from v27.14): at rest
/// (_offset == 0) no panel widget exists at all, so nothing can
/// peek through. While dragging, only the dragged side's panel
/// exists, its width is EXACTLY the drag distance, and its label is
/// centred in the panel and clipped to the panel's CURRENT width
/// (ClipRect), so the label itself builds/eats piece by piece and
/// never overflows into the block. Dragging back EATS the panel
/// piece by piece in reverse, shrinking it smoothly back to zero.
/// Releasing snaps open (past half the panel width) or closed,
/// animated over ~200ms easeOut (never an instant jump). Swiping
/// alone never mutates anything — only tapping a fully built panel
/// runs its handler (which itself asks for confirmation in the
/// parent widget).
///
/// - Work block: drag LEFT builds Delete (red, right edge) only;
///   drag RIGHT builds Break (orange, left edge) only.
/// - Break block (v27.19): drag RIGHT builds Restore; drag LEFT
///   builds Delete too — deleting a break block removes it
///   completely, it does not restore it.
/// - Protected block: no drag at all — it cannot be opened, so no
///   Delete/Break panel can ever be tapped for it.
///
/// Drag handling lives on BOTH the block and the panel (shared
/// handlers): a reverse drag may start on the panel itself, and the
/// panel — sitting beside the block in the row — is what the
/// pointer hits there, so the panel needs its own drag recognizer
/// to shrink.
class _SwipeableBlock extends StatefulWidget {
  final int blockStart;
  final Widget child;
  final bool isBreak;
  final bool isProtected;

  /// Accent/border colour of the hour block (state colour).
  final Color cardColor;

  /// Fill colour of the hour block.
  final Color cardBg;
  final VoidCallback onDelete;
  final VoidCallback onBreak;
  final String deleteLabel;
  final String breakLabel;

  const _SwipeableBlock({
    super.key,
    required this.blockStart,
    required this.child,
    required this.isBreak,
    required this.isProtected,
    required this.cardColor,
    required this.cardBg,
    required this.onDelete,
    required this.onBreak,
    required this.deleteLabel,
    required this.breakLabel,
  });

  @override
  State<_SwipeableBlock> createState() => _SwipeableBlockState();
}

class _SwipeableBlockState extends State<_SwipeableBlock>
    with SingleTickerProviderStateMixin {
  static const double _actionWidth = 96;
  static const Duration _snapDuration = Duration(milliseconds: 200);
  static const double _cardRadius = 14;
  double _offset = 0;

  // Snap animation: from [_snapFrom] to [_snapTo] over [_snapDuration].
  late final AnimationController _snapController;
  double _snapFrom = 0;
  double _snapTo = 0;

  // v27.19: both work and break blocks can be deleted, so the left
  // (Delete) direction is open for every unprotected block.
  double get _minOffset => -_actionWidth;
  double get _maxOffset => _actionWidth;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: _snapDuration,
    )..addListener(() {
        setState(() {
          _offset = _snapFrom +
              (_snapTo - _snapFrom) *
                  Curves.easeOut.transform(_snapController.value);
        });
      });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    if (_offset == target) return;
    _snapFrom = _offset;
    _snapTo = target;
    _snapController.forward(from: 0);
  }

  void _close() => _animateTo(0);

  void _onDragUpdate(DragUpdateDetails details) {
    _snapController.stop();
    setState(() {
      _offset = (_offset + details.delta.dx).clamp(_minOffset, _maxOffset);
    });
  }

  void _onDragEnd(DragEndDetails _) {
    if (_offset.abs() > _actionWidth / 2) {
      _animateTo(_offset < 0 ? _minOffset : _maxOffset);
    } else {
      _animateTo(0);
    }
  }

  /// The block's corner radius: all corners rounded at rest; the
  /// touching inner edge goes square while its panel is attached,
  /// so block + panel join into one continuous bar.
  BorderRadius get _blockRadius {
    if (_offset < 0) {
      // Panel on the right: square right edge.
      return const BorderRadius.only(
        topLeft: Radius.circular(_cardRadius),
        bottomLeft: Radius.circular(_cardRadius),
      );
    }
    if (_offset > 0) {
      // Panel on the left: square left edge.
      return const BorderRadius.only(
        topRight: Radius.circular(_cardRadius),
        bottomRight: Radius.circular(_cardRadius),
      );
    }
    return BorderRadius.circular(_cardRadius);
  }

  /// The raised 3D card: Material elevation + shadow on top of the
  /// panel layer, with the state fill and a border on every side
  /// EXCEPT the touching side (a border there would draw a seam
  /// line down the middle of the bar).
  Widget _raisedBlock() {
    final radius = _blockRadius;
    final side =
        BorderSide(color: widget.cardColor.withValues(alpha: 0.55), width: 1.2);
    final border = _offset < 0
        ? Border(left: side, top: side, bottom: side)
        : _offset > 0
            ? Border(right: side, top: side, bottom: side)
            : Border.all(color: side.color, width: side.width);
    return Material(
      key: ValueKey('block-card-material-${widget.blockStart}'),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: widget.cardBg,
          borderRadius: radius,
          border: border,
        ),
        child: widget.child,
      ),
    );
  }

  /// One action panel, exactly [width] wide, anchored at the dragged
  /// edge and painted UNDER the raised block (it is the Stack's
  /// first child; the block's shadow falls onto it). Its outer
  /// corners are rounded like the block's, its touching inner edge
  /// is square, and its label is centred and clipped to the panel's
  /// current width, so the label builds/eats piece by piece with
  /// the panel and never overflows into the block. The panel carries
  /// its own drag recognizer so a reverse drag starting on the panel
  /// itself still shrinks it.
  Widget _actionPanel({
    required double width,
    required bool leftEdge,
    required Color color,
    required Key key,
    required String label,
    required VoidCallback onTap,
  }) {
    final radius = leftEdge
        ? const BorderRadius.only(
            topLeft: Radius.circular(_cardRadius),
            bottomLeft: Radius.circular(_cardRadius),
          )
        : const BorderRadius.only(
            topRight: Radius.circular(_cardRadius),
            bottomRight: Radius.circular(_cardRadius),
          );
    return Positioned(
      left: leftEdge ? 0 : null,
      right: leftEdge ? null : 0,
      top: 0,
      bottom: 0,
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: widget.isProtected ? null : _onDragUpdate,
        onHorizontalDragEnd: widget.isProtected ? null : _onDragEnd,
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            color: color,
            child: InkWell(
              key: key,
              onTap: () {
                _close();
                onTap();
              },
              child: Center(
                child: ClipRect(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      // Forced LTR: in the Arabic RTL locale, left/right would
      // otherwise mirror, putting Delete on the left and breaking
      // the spec mapping (swipe LEFT builds Delete on the right).
      textDirection: TextDirection.ltr,
      child: Stack(
        // Clip.none: the raised card's shadow must be allowed to
        // spill onto the panel beside it (that spill is what reads
        // as "panel underneath the card"). Nothing else overflows:
        // the panel and the padded block exactly fill the row.
        clipBehavior: Clip.none,
        children: [
          // The panel UNDER the block: first child paints first.
          // At rest there is NO panel widget at all. While
          // dragging, only the dragged side's panel exists, and
          // its width is exactly the drag distance.
          if (_offset > 0)
            _actionPanel(
              width: _offset,
              leftEdge: true,
              color: Colors.orange,
              key: ValueKey('block-action-break-${widget.blockStart}'),
              label: widget.breakLabel,
              onTap: widget.onBreak,
            ),
          if (_offset < 0)
            _actionPanel(
              width: -_offset,
              leftEdge: false,
              color: Colors.red,
              key: ValueKey('block-action-delete-${widget.blockStart}'),
              label: widget.deleteLabel,
              onTap: widget.onDelete,
            ),
          // The block on top: padded on the dragged side by exactly
          // the panel width, so the panel's inner edge and the
          // block's edge are the same line — one continuous bar,
          // same height (the panel stretches to this child's
          // height), zero gap, and the block's content never moves
          // or gets covered.
          Padding(
            padding: EdgeInsets.only(
              left: _offset > 0 ? _offset : 0,
              right: _offset < 0 ? -_offset : 0,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: widget.isProtected ? null : _onDragUpdate,
              onHorizontalDragEnd: widget.isProtected ? null : _onDragEnd,
              // Tapping a panel-open block just closes it; tapping a
              // closed block is handled by the child's own tap
              // (no-op, or the protection explanation).
              onTap: _offset != 0 ? _close : null,
              child: _raisedBlock(),
            ),
          ),
        ],
      ),
    );
  }
}
