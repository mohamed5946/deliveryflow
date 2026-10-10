import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';

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

  @override
  void initState() {
    super.initState();
    _weekAnchor = DateTime.now();
    _load();
  }

  void _load() {
    final db = ref.read(databaseServiceProvider);
    final start = WeekCalendar.weekStart(_weekAnchor);
    final existing = db.scheduleForWeek(_weekAnchor);
    if (existing != null) {
      _days = existing.dailySchedules
          .map((d) => DailySchedule(
                dateKey: d.dateKey,
                isWorkingDay: d.isWorkingDay,
                startMinutes: d.startMinutes,
                endMinutes: d.endMinutes,
                breakDurationMinutes: d.breakDurationMinutes,
                notes: d.notes,
              ))
          .toList();
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

  String _fmtTime(BuildContext context, int minutes) {
    final t = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    return t.format(context);
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
          WeekCalendar.dateKey(start.add(const Duration(days: 6))),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.scheduleSaved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    if (!_loaded) return const Scaffold(body: GlassLoading());
    final start = WeekCalendar.weekStart(_weekAnchor);
    final locale =
        ref.watch(settingsProvider.select((s) => s.languageCode));
    final rangeLabel =
        '${DateFormat.yMMMd(locale == 'ar' ? 'ar' : 'en').format(start)} – ${DateFormat.yMMMd(locale == 'ar' ? 'ar' : 'en').format(start.add(const Duration(days: 6)))}';
    final totalMinutes =
        _days.fold<int>(0, (s, d) => s + d.netPlannedMinutes);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scheduleTitle),
        actions: [
          IconButton(
            tooltip: l10n.previousWeek,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => setState(() {
              _weekAnchor = WeekCalendar.addDays(_weekAnchor, -7);
              _load();
            }),
          ),
          IconButton(
            tooltip: l10n.nextWeek,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => setState(() {
              _weekAnchor = WeekCalendar.addDays(_weekAnchor, 7);
              _load();
            }),
          ),
        ],
      ),
      body: ListView(
        padding: GlassTokens.screenPadding,
        children: [
          GlassCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(rangeLabel,
                    style: text.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                    l10n.totalPlannedHours(
                        WeekCalendar.formatHours(totalMinutes / 60.0)),
                    style: text.bodyMedium),
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
          for (var i = 0; i < 7; i++) _dayCard(context, i, l10n),
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
    final d = _days[i];
    final date = WeekCalendar.parseDateKey(d.dateKey);
    final locale =
        ref.watch(settingsProvider.select((s) => s.languageCode));
    final dayName = DateFormat.EEEE(locale == 'ar' ? 'ar' : 'en').format(date);
    final dayNum = DateFormat.Md(locale == 'ar' ? 'ar' : 'en').format(date);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Column(
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
                      Text(dayNum,
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
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: (d.isWorkingDay
                              ? scheme.primary
                              : scheme.outline)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      d.isWorkingDay ? l10n.workingDay : l10n.dayOff,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: d.isWorkingDay
                            ? scheme.primary
                            : scheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
            if (d.isWorkingDay) ...[
              const SizedBox(height: 10),
              if (_editing)
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
                )
              else
                Text(
                  '${l10n.startTime}: ${_fmtTime(context, d.startMinutes)} • '
                  '${l10n.endTime}: ${_fmtTime(context, d.endMinutes)} • '
                  '${l10n.plannedHours(WeekCalendar.formatHours(d.netPlannedMinutes / 60.0))}'
                  '${d.notes.isNotEmpty ? '\n${d.notes}' : ''}',
                  style: text.bodyMedium,
                ),
            ],
          ],
        ),
      ),
    );
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
