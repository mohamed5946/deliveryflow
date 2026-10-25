import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';

import '../../core/database/models.dart';
import '../../core/date_time/hour_blocks.dart';
import '../../core/date_time/time_format.dart';
import '../../core/date_time/week_calendar.dart';
import '../../theme/design_system.dart';

/// v27.12 Home hour blocks for one selected day, full screen width.
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
/// - Every mutation is gated by a confirmation dialog (Mohamed's
///   v27.12 addition): tapping a work block asks "delete the block"
///   (it becomes a break); tapping a break block asks "add the block"
///   (it becomes work again); + / − hour ask add / delete. Only an
///   explicit Yes invokes the callback; No or dismiss changes nothing.
///   Callbacks only fire after Yes, so the parent can save + log
///   unconditionally inside them.
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

  /// Fired (after Yes) when an hour is appended at the end.
  final VoidCallback onAddHour;

  /// Fired (after Yes) when the last hour is removed.
  final VoidCallback onRemoveHour;

  const DayHoursSection({
    super.key,
    required this.day,
    required this.selectedDay,
    required this.now,
    required this.timeFormat,
    required this.arabic,
    required this.onToggleBreak,
    required this.onAddHour,
    required this.onRemoveHour,
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
              ? Text(
                  l10n.noScheduleForDay,
                  style: text.bodyMedium?.copyWith(
                      color: text.bodyMedium?.color
                          ?.withValues(alpha: 0.65)),
                )
              : !d.isWorkingDay
                  ? Text(l10n.dayOff,
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700))
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
    final canRemove = starts.length > 1;
    final dayName = WeekCalendar.dateKey(selectedDay);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Always-visible header: start–end + worked/remaining summary.
        Text(
          // Generated placeholders are alphabetical: (end, start).
          l10n.dayShiftRange(
              _fmt(context, effectiveEndMinutes(d)), _fmt(context, d.startMinutes)),
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
        // Hour blocks, full width, one per work hour.
        for (final start in starts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _block(context, d, start, breaks.contains(start), l10n,
                keySuffix: dayName),
          ),
        const SizedBox(height: 2),
        // Add / remove hour controls (both confirmation-gated).
        Row(
          children: [
            Expanded(
              child: GlassButton(
                label: l10n.addHour,
                icon: Icons.add_rounded,
                onPressed: () async {
                  if (await _confirm(context, true)) onAddHour();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlassButton(
                label: l10n.removeHour,
                icon: Icons.remove_rounded,
                primary: false,
                onPressed: canRemove
                    ? () async {
                        if (await _confirm(context, false)) onRemoveHour();
                      }
                    : null,
              ),
            ),
          ],
        ),
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

  Widget _block(BuildContext context, DailySchedule d, int start,
      bool isBreak, AppLocalizations l10n,
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
    // A plain InkWell owns the tap (never Pressable scaleOnly + onTap,
    // which swallows taps). The toggle itself is confirmation-gated:
    // work -> break asks "delete", break -> work asks "add".
    return InkWell(
      key: ValueKey('day-hour-block-$keySuffix-$start'),
      onTap: () async {
        if (await _confirm(context, isBreak)) onToggleBreak(start);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
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
            Text(stateLabel,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
