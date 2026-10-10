import 'dart:async';

import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';

/// Working-hours tracker:
/// - Method A: manual entry (start/end/break, overnight-safe).
/// - Method B: live session timer with break/resume, persisted by timestamps
///   so it survives app restarts; restored on reopen.
class SessionScreen extends ConsumerStatefulWidget {
  final String? dateKey;
  const SessionScreen({super.key, this.dateKey});

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  late String _dateKey;
  Timer? _ticker;
  bool _restoredNoticeShown = false;

  // Manual entry state
  TimeOfDay _mStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _mEnd = const TimeOfDay(hour: 17, minute: 0);
  final _mBreak = TextEditingController();
  final _mNotes = TextEditingController();
  String? _mError;

  @override
  void initState() {
    super.initState();
    _dateKey = widget.dateKey ?? WeekCalendar.dateKey(DateTime.now());
    final db = ref.read(databaseServiceProvider);
    _mBreak.text = db.settings.defaultBreakDurationMinutes.toString();
    _ticker = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _mBreak.dispose();
    _mNotes.dispose();
    super.dispose();
  }

  Future<void> _pick(TimeOfDay current, ValueChanged<TimeOfDay> onPick) async {
    final t = await showTimePicker(context: context, initialTime: current);
    if (t != null) onPick(t);
  }

  Future<void> _saveManual() async {
    final l10n = AppLocalizations.of(context);
    final brk = int.tryParse(_mBreak.text.trim()) ?? -1;
    final sMin = _mStart.hour * 60 + _mStart.minute;
    var eMin = _mEnd.hour * 60 + _mEnd.minute;
    if (eMin <= sMin) eMin += 24 * 60;
    final gross = eMin - sMin;
    if (gross <= 0) {
      setState(() => _mError = l10n.invalidTimeRange);
      return;
    }
    if (brk < 0 || brk > gross) {
      setState(() => _mError = l10n.invalidBreak);
      return;
    }
    final db = ref.read(databaseServiceProvider);
    await db.saveManualSession(
      dateKey: _dateKey,
      startMinutes: sMin,
      endMinutes: _mEnd.hour * 60 + _mEnd.minute,
      breakMinutes: brk,
      notes: _mNotes.text.trim(),
    );
    bumpDataVersion(ref);
    if (mounted) {
      setState(() => _mError = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.recordSaved)));
      // Return to the previous screen after saving.
      context.pop();
    }
  }

  Future<void> _startSession() async {
    final l10n = AppLocalizations.of(context);
    final db = ref.read(databaseServiceProvider);
    try {
      await db.startSession(_dateKey);
      bumpDataVersion(ref);
    } on StateError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.overlapWarning)));
      }
    }
    setState(() {});
  }

  Future<void> _toggleBreak(WorkSession s) async {
    final db = ref.read(databaseServiceProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (s.status == 0) {
      s.breaks.add(BreakInterval(startMillis: now));
      s.status = 1;
    } else if (s.status == 1) {
      final last = s.breaks.last;
      last.endMillis = now;
      await last.save();
      s.status = 0;
    }
    await db.saveSession(s);
    bumpDataVersion(ref);
    setState(() {});
  }

  Future<void> _finish(WorkSession s) async {
    final db = ref.read(databaseServiceProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (s.status == 1 && s.breaks.isNotEmpty) {
      s.breaks.last.endMillis = now;
      await s.breaks.last.save();
    }
    s.endMillis = now;
    s.status = 2;
    await db.saveSession(s);
    bumpDataVersion(ref);
    setState(() {});
  }

  String _fmtDur(int millis) {
    final s = (millis / 1000).round();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale =
        ref.watch(settingsProvider.select((s) => s.languageCode));
    final date = WeekCalendar.parseDateKey(_dateKey);
    final dateLabel =
        DateFormat.yMMMMEEEEd(locale == 'ar' ? 'ar' : 'en').format(date);

    final db = ref.watch(databaseServiceProvider);
    final active = db.activeSession();
    final sessions = db.sessionsForDate(_dateKey);
    final order = db.orderRecord(_dateKey);
    final netMinutes = db.recordedMinutesForDate(_dateKey);

    if (active != null && active.isActive && !_restoredNoticeShown) {
      _restoredNoticeShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.sessionRestored)));
        }
      });
    }

    final ordersPerHour = netMinutes > 0 && order != null
        ? order.completedOrders / (netMinutes / 60.0)
        : null;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.hoursTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: GlassTokens.screenPadding,
        children: [
          Text(dateLabel,
              style:
                  text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          // Daily summary
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.dailySummary,
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _row(l10n.netHours,
                    WeekCalendar.formatHours(netMinutes / 60.0), text),
                _row(l10n.todayOrders,
                    order == null
                        ? l10n.unrecorded
                        : '${order.completedOrders}',
                    text),
                if (ordersPerHour != null)
                  _row(l10n.ordersPerHour,
                      ordersPerHour.toStringAsFixed(1), text),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Timer
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.sessionTimer,
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                if (active == null) ...[
                  Center(
                    child: GlassButton(
                      label: l10n.startWork,
                      icon: Icons.play_arrow_rounded,
                      onPressed: _startSession,
                    ),
                  ),
                ] else ...[
                  Center(
                    child: Text(
                      _fmtDur(DateTime.now().millisecondsSinceEpoch -
                          active.startMillis -
                          active.breakMillis),
                      style: text.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.primary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      active.isOnBreak
                          ? l10n.onBreak
                          : l10n.activeSession,
                      style: text.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      '${l10n.breakTime}: ${WeekCalendar.formatMinutes((active.breakMillis / 60000).round())}',
                      style: text.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GlassButton(
                        label: active.isOnBreak
                            ? l10n.resumeWork
                            : l10n.takeBreak,
                        primary: false,
                        icon: active.isOnBreak
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        onPressed: () => _toggleBreak(active),
                      ),
                      const SizedBox(width: 10),
                      GlassButton(
                        label: l10n.finishWork,
                        icon: Icons.stop_rounded,
                        onPressed: () => _finish(active),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Manual entry
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.manualEntry,
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _timeField(context, l10n.startTime,
                          _mStart, (t) => setState(() => _mStart = t)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _timeField(context, l10n.endTime, _mEnd,
                          (t) => setState(() => _mEnd = t)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _mBreak,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: l10n.breakMinutes),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _mNotes,
                  maxLines: 2,
                  decoration: InputDecoration(
                      labelText: l10n.notesOptional),
                ),
                if (_mError != null) ...[
                  const SizedBox(height: 8),
                  Text(_mError!,
                      style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 12),
                Center(
                  child: GlassButton(
                    label: l10n.saveRecord,
                    icon: Icons.check_rounded,
                    onPressed: _saveManual,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Finished sessions list
          if (sessions.where((s) => s.status == 2).isNotEmpty) ...[
            Text(l10n.dailySummary,
                style:
                    text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final s in sessions.where((s) => s.status == 2))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        s.isManual
                            ? l10n.manualEntry
                            : l10n.sessionTimer,
                        style: text.bodyMedium,
                      ),
                      Text(
                        WeekCalendar.formatHours(
                            s.netMinutes / 60.0),
                        style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _row(String label, String value, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: text.bodyMedium),
          Text(value,
              style: text.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _timeField(BuildContext context, String label, TimeOfDay value,
      ValueChanged<TimeOfDay> onPick) {
    return InkWell(
      onTap: () => _pick(value, onPick),
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value.format(context),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
