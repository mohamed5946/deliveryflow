import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';

import '../../core/database/models.dart';
import '../../core/date_time/hour_blocks.dart';
import '../../core/date_time/time_format.dart';
import '../../core/date_time/week_calendar.dart';
import '../../theme/design_system.dart';

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
/// - SWIPE (v27.13): each block is horizontally draggable and snaps
///   open to reveal its actions — swipe LEFT reveals a red Delete
///   action, swipe RIGHT reveals a Break action (a break block's
///   right action is Restore instead, since it is already a break;
///   a break block has no Delete action — there is no work left in
///   it to delete). Swiping alone changes NOTHING: only tapping a
///   revealed action opens the Yes/No confirmation dialog, and only
///   Yes invokes the callback. No / dismiss changes nothing. The
///   reveal is a plain drag + snap (no slidable dependency was
///   added; the widget is a small custom horizontal-drag reveal,
///   smooth standard motion, no looping animation).
///   In the start/end + break model, "deleting" a work hour and
///   "breaking" it are the same stored change (the hour becomes a
///   break block, so the header range stays coherent); both swipe
///   actions are offered per spec and both are confirmation-gated.
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

  /// Fired (after Yes) when an hour picked in the Assign picker is
  /// added as a new work block (wall-clock hour 0..23).
  final ValueChanged<int> onAssignHour;

  /// Extended block starts that contain real orders and are
  /// therefore locked against delete/break. Empty by default.
  final Set<int> protectedBlockStarts;

  const DayHoursSection({
    super.key,
    required this.day,
    required this.selectedDay,
    required this.now,
    required this.timeFormat,
    required this.arabic,
    required this.onToggleBreak,
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

    return Column(
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
                  color: Colors.orange.shade700, fontWeight: FontWeight.w700)),
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
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _block(context, d, start, breaks.contains(start), l10n,
                keySuffix: dayName),
          ),
        const SizedBox(height: 2),
        // Assign: the only way to add a new work hour (v27.13).
        _assignButton(context, l10n),
      ],
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
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
      ),
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
      onDelete: () async {
        if (await _confirm(context, false)) onToggleBreak(start);
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

/// v27.13 custom horizontal-drag reveal (no new dependency:
/// flutter_slidable is not in pubspec.yaml, and a full slidable
/// package would be heavy for one row type).
///
/// The block sits over its actions in a [Stack]; dragging it
/// sideways translates it and exposes the action underneath, and
/// releasing snaps it fully open (past half the action width) or
/// closed. Swiping alone never mutates anything — only tapping a
/// revealed action runs its handler (which itself asks for
/// confirmation in the parent widget).
///
/// - Work block: left reveal = Delete (red), right reveal = Break.
/// - Break block: right reveal = Restore; no left action (there is
///   no work left in it to delete), so left drags are ignored.
/// - Protected block: no drag at all — it cannot be opened, so no
///   Delete/Break action can ever be tapped for it.
class _SwipeableBlock extends StatefulWidget {
  final int blockStart;
  final Widget child;
  final bool isBreak;
  final bool isProtected;
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
    required this.onDelete,
    required this.onBreak,
    required this.deleteLabel,
    required this.breakLabel,
  });

  @override
  State<_SwipeableBlock> createState() => _SwipeableBlockState();
}

class _SwipeableBlockState extends State<_SwipeableBlock> {
  static const double _actionWidth = 96;
  double _offset = 0;

  double get _minOffset => widget.isBreak ? 0 : -_actionWidth;
  double get _maxOffset => _actionWidth;

  void _close() => setState(() => _offset = 0);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          // Actions underneath (only the sides this block allows).
          // Forced LTR: in the Arabic RTL locale a plain Row would
          // mirror, putting Delete on the left and breaking the
          // spec mapping (swipe LEFT reveals Delete on the right).
          Positioned.fill(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  // Right swipe reveals this (left side).
                  SizedBox(
                    width: _actionWidth,
                    child: Material(
                      color: Colors.orange,
                      child: InkWell(
                        key:
                            ValueKey('block-action-break-${widget.blockStart}'),
                        onTap: () {
                          _close();
                          widget.onBreak();
                        },
                        child: Center(
                          child: Text(widget.breakLabel,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Left swipe reveals this (right side), work only.
                  if (!widget.isBreak)
                    SizedBox(
                      width: _actionWidth,
                      child: Material(
                        color: Colors.red,
                        child: InkWell(
                          key: ValueKey(
                              'block-action-delete-${widget.blockStart}'),
                          onTap: () {
                            _close();
                            widget.onDelete();
                          },
                          child: Center(
                            child: Text(widget.deleteLabel,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // The block itself, translated by the drag. The Transform
          // MUST wrap the GestureDetector (not the other way round):
          // a detector outside the transform keeps its full-width
          // hit area over the revealed actions, so they could never
          // be tapped. With the transform outside, the hit area moves
          // with the block and the exposed action receives the tap.
          Transform.translate(
            offset: Offset(_offset, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: widget.isProtected
                  ? null
                  : (details) {
                      setState(() {
                        _offset = (_offset + details.delta.dx)
                            .clamp(_minOffset, _maxOffset);
                      });
                    },
              onHorizontalDragEnd: widget.isProtected
                  ? null
                  : (_) {
                      setState(() {
                        if (_offset.abs() > _actionWidth / 2) {
                          _offset = _offset < 0 ? _minOffset : _maxOffset;
                        } else {
                          _offset = 0;
                        }
                      });
                    },
              // Tapping an open block just closes it; tapping a closed
              // block is handled by the child's own tap (no-op, or the
              // protection explanation).
              onTap: _offset != 0 ? _close : null,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}
