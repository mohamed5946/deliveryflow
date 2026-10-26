import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/database_service.dart';
import '../../core/database/models.dart';
import '../../core/date_time/day_rollover.dart';
import '../../core/date_time/time_format.dart';
import '../../core/date_time/schedule_normalizer.dart';
import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';
import '../../theme/top_snack_bar.dart';
import '../../theme/pressable.dart';

/// Weekly schedule editor (Sunday–Saturday).
///
/// Each day: working/off, start/end, break, notes. Supports copy-day,
/// mark-multiple-off, overnight shifts. One schedule per week (upsert).
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late DateTime _weekAnchor; // any day in the displayed week
  late List<DailySchedule> _days;
  bool _loaded = false;
  bool _editing = false;
  String? _error;
  late final DayRolloverWatcher _rollover;

  @override
  void initState() {
    super.initState();
    _weekAnchor = DateTime.now();
    _rollover = DayRolloverWatcher(onDayChanged: _handleDayChanged);
    _rollover.start();
    _load();
  }

  @override
  void dispose() {
    _rollover.dispose();
    super.dispose();
  }

  /// v26 midnight rollover: when the displayed week was the current one,
  /// follow into the new week; otherwise just refresh the today markers.
  /// Never yank the view while he is editing.
  void _handleDayChanged(DateTime previous, DateTime current) {
    if (!mounted) return;
    setState(() {
      if (!_editing && WeekCalendar.isSameWeek(_weekAnchor, previous)) {
        _weekAnchor = current;
        _load();
      }
    });
  }

  void _load() {
    final db = ref.read(databaseServiceProvider);
    final start = WeekCalendar.weekStart(_weekAnchor);
    final existing = db.scheduleForWeek(_weekAnchor);
    if (existing != null) {
      // v27.10: work on the canonical week, never the raw stored list.
      // scheduleForWeek already normalizes (and logs) on read; running
      // the normalizer here too keeps the editor safe even if a future
      // caller hands it an unvalidated list. Its output days are fresh
      // copies, safe to edit in place.
      _days = ScheduleNormalizer.normalizeWeek(
        weekStartKey: existing.weekStartKey,
        stored: existing.dailySchedules,
        defaultBreakMinutes: db.settings.defaultBreakDurationMinutes,
      ).days;
      _editing = false;
    } else {
      final settings = db.settings;
      _days = WeekCalendar.weekDays(start)
          .map((d) => DailySchedule(
                dateKey: WeekCalendar.dateKey(d),
                breakDurationMinutes: settings.defaultBreakDurationMinutes,
              ))
          .toList();
      _editing = true;
    }
    _loaded = true;
    _error = null;
  }

  /// v27.12: honours the Profile time-format setting. Mode "system"
  /// (the default) keeps the exact pre-v27.12 behaviour —
  /// `TimeOfDay.format` — so existing users see no change until they
  /// pick 12h or 24h; explicit modes use the shared pure formatter.
  String _fmtTime(BuildContext context, int minutes) {
    final settings = ref.read(settingsProvider);
    return formatMinutesWithContext(
      context,
      minutes,
      timeFormatModeFromStored(settings.timeFormat),
      arabic: settings.languageCode == 'ar',
    );
  }

  Future<void> _pickTime(int index, bool isStart) async {
    final cur = isStart ? _days[index].startMinutes : _days[index].endMinutes;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (t != null) {
      setState(() {
        if (isStart) {
          _days[index].startMinutes = t.hour * 60 + t.minute;
        } else {
          _days[index].endMinutes = t.hour * 60 + t.minute;
        }
      });
    }
  }

  Future<void> _editBreak(int index) async {
    final ctrl = TextEditingController(
        text: _days[index].breakDurationMinutes.toString());
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).breakMinutes),
        content: TextField(
            controller: ctrl, keyboardType: TextInputType.number),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx).cancel)),
          TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
              child: Text(AppLocalizations.of(ctx).ok)),
        ],
      ),
    );
    if (v != null && v >= 0) {
      setState(() => _days[index].breakDurationMinutes = v);
    }
  }

  Future<void> _editNotes(int index) async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: _days[index].notes);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.notesOptional),
        content: TextField(controller: ctrl, maxLines: 3),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(l10n.ok)),
        ],
      ),
    );
    if (v != null) setState(() => _days[index].notes = v);
  }

  /// Copy day [from] shift to selected days.
  Future<void> _copyDay(int from) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => _DayPickerDialog(
        title: l10n.copyToDays,
        exclude: from,
      ),
    );
    if (selected == null) return;
    final src = _days[from];
    setState(() {
      for (final i in selected) {
        _days[i].isWorkingDay = src.isWorkingDay;
        _days[i].startMinutes = src.startMinutes;
        _days[i].endMinutes = src.endMinutes;
        _days[i].breakDurationMinutes = src.breakDurationMinutes;
        // v27.12: copy-day must carry the break blocks too, or the
        // copied day silently loses its break marks.
        // v27.19: same for deleted hours.
        _days[i].breakHourStarts = List.of(src.breakHourStarts);
        _days[i].deletedHourStarts = List.of(src.deletedHourStarts);
      }
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    // Validate.
    for (final d in _days) {
      if (!d.isWorkingDay) continue;
      var end = d.endMinutes;
      if (end <= d.startMinutes) end += 24 * 60; // overnight ok
      final gross = end - d.startMinutes;
      if (gross <= 0) {
        setState(() => _error = l10n.invalidTimeRange);
        return;
      }
      if (d.breakDurationMinutes < 0 ||
          d.breakDurationMinutes > gross) {
        setState(() => _error = l10n.invalidBreak);
        return;
      }
    }
    final db = ref.read(databaseServiceProvider);
    final start = WeekCalendar.weekStart(_weekAnchor);
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = db.scheduleForWeek(_weekAnchor);
    final sched = WorkSchedule(
      id: existing?.id ?? 'sch_${WeekCalendar.dateKey(start)}',
      weekStartKey: WeekCalendar.dateKey(start),
      weekEndKey:
          WeekCalendar.dateKey(WeekCalendar.addDays(start, 6)),
      dailySchedules: _days,
      createdAtMillis: existing?.createdAtMillis ?? now,
      updatedAtMillis: now,
    );
    await db.saveSchedule(sched);
    bumpDataVersion(ref);
    await ref.read(settingsProvider.notifier).refreshReminders();
    if (mounted) {
      setState(() {
        _editing = false;
        _error = null;
      });
      showTopSnackBar(context, l10n.scheduleSaved);
    }
  }

  void _prevWeek() => setState(() {
        _weekAnchor = WeekCalendar.addDays(_weekAnchor, -7);
        _load();
      });

  void _nextWeek() => setState(() {
        _weekAnchor = WeekCalendar.addDays(_weekAnchor, 7);
        _load();
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    if (!_loaded) return const Scaffold(body: GlassLoading());
    final start = WeekCalendar.weekStart(_weekAnchor);
    final locale =
        ref.watch(settingsProvider.select((s) => s.languageCode));
    // Rebuild badges when order records / sessions change.
    ref.watch(dataVersionProvider);
    final loc = locale == 'ar' ? 'ar' : 'en';
    final rangeLabel =
        '${DateFormat.d(loc).format(start)} - ${DateFormat.yMMMd(loc).format(WeekCalendar.addDays(start, 6))}';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.scheduleTitle)),
      body: ListView(
        padding: GlassTokens.screenPadding,
        children: [
          // Week navigator (mockup): [›] [range] [‹] in RTL.
          GlassCard(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.previousWeek,
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: _prevWeek,
                ),
                Expanded(
                  child: Text(
                    rangeLabel,
                    textAlign: TextAlign.center,
                    style: text.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: l10n.nextWeek,
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: _nextWeek,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ),
          for (var i = 0; i < _days.length; i++) _dayCard(context, i, l10n),
          const SizedBox(height: 16),
          if (_editing)
            SizedBox(
              width: double.infinity,
              child: GlassButton(
                label: l10n.saveSchedule,
                icon: Icons.check_rounded,
                onPressed: _save,
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: GlassButton(
                label: l10n.editSchedule,
                icon: Icons.edit_rounded,
                primary: false,
                onPressed: () => setState(() => _editing = true),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _dayCard(BuildContext context, int i, AppLocalizations l10n) {
    // In view mode the card shows a chevron, so it must be tappable —
    // v27.3: tapping opens that day's ORDERS (Mohamed's request), not
    // the editor. Schedule editing stays behind the "تعديل الجدول"
    // button below, which switches the whole week into edit mode.
    final card = GlassCard(
      child: _dayCardBody(context, i, l10n),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _editing
          ? card
          : Pressable(
              onTap: () =>
                  context.push('/orders?date=${_days[i].dateKey}'),
              child: card,
            ),
    );
  }

  Widget _dayCardBody(BuildContext context, int i, AppLocalizations l10n) {
    final d = _days[i];
    final date = WeekCalendar.parseDateKey(d.dateKey);
    final locale =
        ref.watch(settingsProvider.select((s) => s.languageCode));
    // v27.12: rebuild rows when the time-format setting changes.
    ref.watch(settingsProvider.select((s) => s.timeFormat));
    final loc = locale == 'ar' ? 'ar' : 'en';
    final dayName = DateFormat.EEEE(loc).format(date);
    final dayDate = DateFormat.Md(loc).format(date);
    final text = Theme.of(context).textTheme;

    return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dayName,
                          style: text.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(dayDate,
                          style: text.bodySmall?.copyWith(
                              color: text.bodySmall?.color
                                  ?.withValues(alpha: 0.65))),
                    ],
                  ),
                ),
                if (_editing)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l10n.copyDay,
                        icon: const Icon(Icons.content_copy_rounded,
                            size: 20),
                        onPressed: () => _copyDay(i),
                      ),
                      Switch(
                        value: d.isWorkingDay,
                        onChanged: (v) =>
                            setState(() => d.isWorkingDay = v),
                      ),
                    ],
                  )
                else ...[
                  // v27.12 view mode: working days always show their
                  // start–end times opposite the day name (previously
                  // times appeared only in edit mode). Day-off rows
                  // show Day off here only when the status chip does
                  // not already say so (a scheduled day off that got
                  // worked shows the completed chip instead) — the
                  // chip itself is untouched.
                  if (d.isWorkingDay) ...[
                    Text(
                      '${_fmtTime(context, d.startMinutes)} - '
                      '${_fmtTime(context, d.endMinutes)}',
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 10),
                  ] else if (_chipFor(i) != ScheduleDayChip.dayOff) ...[
                    Text(
                      l10n.dayOff,
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 10),
                  ],
                  _dayStatus(context, i, l10n),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.35),
                  ),
                ],
              ],
            ),
            if (_editing && d.isWorkingDay) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _timeChip(context, l10n.startTime,
                      _fmtTime(context, d.startMinutes),
                      () => _pickTime(i, true)),
                  _timeChip(context, l10n.endTime,
                      _fmtTime(context, d.endMinutes),
                      () => _pickTime(i, false)),
                  _timeChip(
                      context,
                      l10n.breakMinutes,
                      '${d.breakDurationMinutes}',
                      () => _editBreak(i)),
                  _timeChip(context, l10n.notesOptional,
                      d.notes.isEmpty ? '–' : d.notes,
                      () => _editNotes(i)),
                ],
              ),
            ],
          ],
        );
  }

  /// Status badge + completed-orders count for a day (view mode).
  ///
  /// Green "مكتمل" when the day has counted orders, blue in-progress
  /// when it is today and work has started, a day-off chip (v27.3,
  /// derived by [scheduleDayChipFor]) for past no-order days and
  /// plan-marked off days, gray "لم يبدأ" otherwise.
  /// Shared chip computation for [_dayStatus] and the v27.12 view-mode
  /// Day off label (extracted so both agree on the same chip).
  ScheduleDayChip _chipFor(int i) {
    final db = ref.read(databaseServiceProvider);
    final d = _days[i];
    final record = db.orderRecord(d.dateKey);
    final count = record?.completedOrders ?? 0;
    final todayKey = WeekCalendar.dateKey(DateTime.now());
    return scheduleDayChipFor(
      countedOrders: count,
      isWorkingDay: d.isWorkingDay,
      workStartedToday: d.dateKey == todayKey &&
          _workStartedToday(db, d.dateKey, record),
      date: WeekCalendar.parseDateKey(d.dateKey),
      today: DateTime.now(),
    );
  }

  Widget _dayStatus(
      BuildContext context, int i, AppLocalizations l10n) {
    final db = ref.read(databaseServiceProvider);
    final d = _days[i];
    final record = db.orderRecord(d.dateKey);
    final count = record?.completedOrders ?? 0;
    final chip = _chipFor(i);

    final String label;
    final Color color;
    switch (chip) {
      case ScheduleDayChip.completed:
        label = l10n.statusCompleted;
        color = LiquidPalette.success;
      case ScheduleDayChip.inProgress:
        label = l10n.statusInProgress;
        color = LiquidPalette.primaryBlue;
      case ScheduleDayChip.dayOff:
        label = l10n.dayOff;
        color = Theme.of(context).colorScheme.tertiary;
      case ScheduleDayChip.notStarted:
        label = l10n.statusNotStarted;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        color = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    }

    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        if (count > 0) ...[
          const SizedBox(height: 4),
          Text(
            l10n.completedOrdersChip(count),
            style: text.bodySmall?.copyWith(
                color:
                    text.bodySmall?.color?.withValues(alpha: 0.65)),
          ),
        ],
      ],
    );
  }

  /// True when any work happened today: a work session exists, or an
  /// order entry moved past "pending".
  bool _workStartedToday(
      DatabaseService db, String todayKey, DailyOrderRecord? record) {
    if (db.sessionsForDate(todayKey).isNotEmpty) return true;
    final entries = record?.entries ?? const <OrderEntry>[];
    return entries.any((e) => e.status >= 1 && e.status <= 3);
  }

  Widget _timeChip(BuildContext context, String label, String value,
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outline
                  .withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text(label,
                style: Theme.of(context).textTheme.labelSmall),
            Text(value,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Dialog to pick target days for copy/mark-off.
class _DayPickerDialog extends StatefulWidget {
  final String title;
  final int exclude; // -1 = none
  const _DayPickerDialog({required this.title, this.exclude = -1});

  @override
  State<_DayPickerDialog> createState() => _DayPickerDialogState();
}

class _DayPickerDialogState extends State<_DayPickerDialog> {
  final _sel = <int>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final names = [
      l10n.sunday,
      l10n.monday,
      l10n.tuesday,
      l10n.wednesday,
      l10n.thursday,
      l10n.friday,
      l10n.saturday,
    ];
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: 7,
          itemBuilder: (ctx, i) {
            if (i == widget.exclude) return const SizedBox.shrink();
            return CheckboxListTile(
              title: Text(names[i]),
              value: _sel.contains(i),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _sel.add(i);
                } else {
                  _sel.remove(i);
                }
              }),
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel)),
        TextButton(
            onPressed: () => Navigator.pop(context, _sel.toList()),
            child: Text(l10n.ok)),
      ],
    );
  }
}
