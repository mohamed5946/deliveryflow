import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../core/tracking/delivery_tracking_service.dart';
import '../../theme/design_system.dart';
import '../../theme/page_transitions.dart';
import '../../theme/pressable.dart';
import 'order_detail_screen.dart';

/// Per-order tracking: each order gets its own entry with the driven
/// distance going (out) and returning (back). The day's order count is
/// derived from the record; entries are optional details.
class OrderEntryScreen extends ConsumerStatefulWidget {
  final String? dateKey;
  const OrderEntryScreen({super.key, this.dateKey});

  @override
  ConsumerState<OrderEntryScreen> createState() => _OrderEntryScreenState();
}

class _OrderEntryScreenState extends ConsumerState<OrderEntryScreen> {
  late String _dateKey;
  List<OrderEntry> _entries = [];
  int _count = 0;
  final _notes = TextEditingController();
  final _notesFocus = FocusNode();
  bool _loaded = false;
  bool _notesDirty = false;

  @override
  void initState() {
    super.initState();
    _dateKey = widget.dateKey ?? WeekCalendar.dateKey(DateTime.now());
    _notesFocus.addListener(() {
      if (!_notesFocus.hasFocus && _notesDirty) _saveNotes();
    });
    _load();
  }

  void _load() {
    final db = ref.read(databaseServiceProvider);
    final rec = db.orderRecord(_dateKey);
    final entries = List<OrderEntry>.from(rec?.entries ?? const <OrderEntry>[])
      ..sort((a, b) => a.timestampMillis.compareTo(b.timestampMillis));
    setState(() {
      _entries = entries;
      _count = rec?.completedOrders ?? 0;
      if (!_notesDirty) _notes.text = rec?.notes ?? '';
      _loaded = true;
    });
  }

  @override
  void dispose() {
    if (_notesDirty) _saveNotesSync();
    _notes.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  Future<void> _saveNotes() async {
    _notesDirty = false;
    final db = ref.read(databaseServiceProvider);
    await db.upsertOrderRecord(
      dateKey: _dateKey,
      completedOrders: _count,
      notes: _notes.text.trim(),
    );
    bumpDataVersion(ref);
  }

  void _saveNotesSync() {
    // Best effort on dispose; the async save usually wins via focus loss.
    _notesDirty = false;
  }

  Future<void> _addEntry() async {
    // New flow: create a pending order instantly — no km questions.
    // Distances are filled automatically by GPS tracking from the
    // order detail screen ("بدأ التوصيل").
    final db = ref.read(databaseServiceProvider);
    final entry = await db.addOrderEntry(
      dateKey: _dateKey,
      timestampMillis: DateTime.now().millisecondsSinceEpoch,
    );
    if (!mounted) return;
    bumpDataVersion(ref);
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.refreshReminders();
    _load();
    if (!mounted) return;
    // Open the detail screen so the courier can start GPS tracking.
    await Navigator.of(context).push(
      SmoothPageRoute(
        builder: (_) => OrderDetailScreen(
          dateKey: _dateKey,
          entryId: entry.id,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _editEntry(OrderEntry entry) async {
    final result = await showModalBottomSheet<_EntryFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EntryFormSheet(dateKey: _dateKey, entry: entry),
    );
    if (result == null || !mounted) return;
    final db = ref.read(databaseServiceProvider);
    await db.updateOrderEntry(
      dateKey: _dateKey,
      entryId: entry.id,
      timestampMillis: result.timestampMillis,
      kmOut: result.kmOut,
      kmBack: result.kmBack,
      notes: result.notes,
    );
    if (!mounted) return;
    bumpDataVersion(ref);
    _load();
  }

  Future<void> _deleteEntry(OrderEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteOrderTitle),
        content: Text(l10n.deleteOrderConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final db = ref.read(databaseServiceProvider);
    // If the deleted order was being tracked, stop the background
    // service too — otherwise it keeps recording + notifying for a
    // deleted order (orphaned tracking).
    final svc = ref.read(deliveryTrackingServiceProvider);
    if (svc.isTracking && svc.trackingOrderId == entry.id) {
      await svc.cancelTracking();
    }
    await db.deleteOrderEntry(dateKey: _dateKey, entryId: entry.id);
    if (!mounted) return;
    bumpDataVersion(ref);
    _load();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.orderDeleted)));
  }

  double get _kmOut =>
      _entries.fold<double>(0, (s, e) => s + e.effectiveKmOut);
  double get _kmBack =>
      _entries.fold<double>(0, (s, e) => s + e.effectiveKmBack);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(settingsProvider.select((s) => s.languageCode));
    final date = WeekCalendar.parseDateKey(_dateKey);
    final dateLabel =
        DateFormat.yMMMMEEEEd(locale == 'ar' ? 'ar' : 'en').format(date);
    if (!_loaded) {
      return const GlassScaffold(body: GlassLoading());
    }

    final undetailed = _count - _entries.length;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.ordersForDate(dateLabel)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: GlassTokens.screenPadding,
        children: [
          // Summary: count + distance.
          GlassCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text('$_count',
                          style: text.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.primary)),
                      const SizedBox(height: 2),
                      Text(l10n.ordersLabel, style: text.bodySmall),
                    ],
                  ),
                ),
                Container(
                    width: 1,
                    height: 56,
                    color: Colors.white.withValues(alpha: 0.15)),
                Expanded(
                  child: Column(
                    children: [
                      Text(_fmtKm(_kmOut + _kmBack),
                          style: text.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(l10n.totalKmLabel, style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _kmChip(context, l10n.kmOutLabel, _kmOut, scheme.primary),
                _kmChip(context, l10n.kmBackLabel, _kmBack, scheme.secondary),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: GlassButton(
              label: l10n.addOrder,
              icon: Icons.add_rounded,
              onPressed: _addEntry,
            ),
          ),
          const SizedBox(height: 12),
          if (_entries.isEmpty)
            GlassCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Icon(Icons.local_shipping_outlined,
                        size: 40,
                        color: scheme.onSurface.withValues(alpha: 0.35)),
                    const SizedBox(height: 8),
                    Text(l10n.noOrdersYet,
                        style: text.bodyMedium?.copyWith(
                            color: scheme.onSurface
                                .withValues(alpha: 0.6))),
                  ],
                ),
              ),
            )
          else
            ..._entries.map((e) => _entryCard(context, e)),
          if (undetailed > 0) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                l10n.ordersWithoutDetails(undetailed),
                style: text.bodySmall?.copyWith(
                    color:
                        scheme.onSurface.withValues(alpha: 0.55)),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.orderNotesHint, style: text.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _notes,
                  focusNode: _notesFocus,
                  maxLines: 3,
                  decoration:
                      InputDecoration(hintText: l10n.notesOptional),
                  onChanged: (_) => _notesDirty = true,
                  onSubmitted: (_) => _saveNotes(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _kmChip(
      BuildContext context, String label, double value, Color color) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.route_rounded, size: 18, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_fmtKm(value)} ${AppLocalizations.of(context).kmUnit}',
                style: text.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text(label,
                style: text.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6))),
          ],
        ),
      ],
    );
  }

  Widget _entryCard(BuildContext context, OrderEntry entry) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(settingsProvider.select((s) => s.languageCode));
    final time = DateFormat.Hm(locale == 'ar' ? 'ar' : 'en')
        .format(entry.timestamp);

    // Status badge: makes the tracking state visible at a glance.
    final (statusLabel, statusColor) = switch (entry.status) {
      1 => (l10n.statusToCustomer, Colors.orange),
      2 => (l10n.statusToMart, Colors.blue),
      3 => (l10n.statusCompleted, Colors.green),
      _ => (l10n.statusPending, scheme.onSurface.withValues(alpha: 0.55)),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        scaleOnly: true,
        child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.of(context).push(
            SmoothPageRoute(
              builder: (_) => OrderDetailScreen(
                dateKey: _dateKey,
                entryId: entry.id,
              ),
            ),
          );
          if (mounted) _load();
        },
        child: GlassCard(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(time,
                      style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.primary)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(statusLabel,
                      style: text.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.isPending
                        ? l10n.tapToStartTracking
                        : '${l10n.kmOutLabel}: ${_fmtKm(entry.effectiveKmOut)} • ${l10n.kmBackLabel}: ${_fmtKm(entry.effectiveKmBack)} ${l10n.kmUnit}',
                    style: text.bodyMedium?.copyWith(
                      color: entry.isPending
                          ? scheme.primary
                          : null,
                      fontWeight: entry.isPending
                          ? FontWeight.w700
                          : null,
                    ),
                  ),
                  if (entry.notes.isNotEmpty)
                    Text(entry.notes,
                        style: text.bodySmall?.copyWith(
                            color: scheme.onSurface
                                .withValues(alpha: 0.6)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Text(_fmtKm(entry.effectiveKmTotal),
                style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.secondary)),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _editEntry(entry),
              tooltip: l10n.edit,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  size: 20, color: scheme.error),
              onPressed: () => _deleteEntry(entry),
              tooltip: l10n.delete,
              visualDensity: VisualDensity.compact,
            ),
          ],
            ),
          ],
        ),
        ),
      ),
      ),
    );
  }
}

/// Formats km compactly: 12.5 / 12 (no trailing .0).
String _fmtKm(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Converts Arabic-Indic digits to Latin before parsing.
double? _parseKm(String raw) {
  var s = raw.trim();
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < arabic.length; i++) {
    s = s.replaceAll(arabic[i], '$i');
  }
  s = s.replaceAll(',', '.');
  return double.tryParse(s);
}

class _EntryFormResult {
  final int timestampMillis;
  final double kmOut;
  final double kmBack;
  final String notes;
  _EntryFormResult({
    required this.timestampMillis,
    required this.kmOut,
    required this.kmBack,
    required this.notes,
  });
}

/// Bottom sheet to add or edit a single order entry.
class _EntryFormSheet extends ConsumerStatefulWidget {
  final String dateKey;
  final OrderEntry? entry;
  const _EntryFormSheet({required this.dateKey, this.entry});

  @override
  ConsumerState<_EntryFormSheet> createState() => _EntryFormSheetState();
}

class _EntryFormSheetState extends ConsumerState<_EntryFormSheet> {
  final _kmOut = TextEditingController();
  final _kmBack = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _time;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    if (e != null) {
      _time = e.timestamp;
      _kmOut.text = _fmtKm(e.kmOut);
      _kmBack.text = _fmtKm(e.kmBack);
      _notes.text = e.notes;
    } else {
      _time = DateTime.now();
    }
  }

  @override
  void dispose() {
    _kmOut.dispose();
    _kmBack.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (picked == null) return;
    final day = WeekCalendar.parseDateKey(widget.dateKey);
    setState(() {
      _time = DateTime(
          day.year, day.month, day.day, picked.hour, picked.minute);
    });
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final kmOut = _parseKm(_kmOut.text) ?? -1;
    final kmBack = _parseKm(_kmBack.text) ?? -1;
    if (kmOut < 0 || kmBack < 0) {
      setState(() => _error = l10n.invalidKm);
      return;
    }
    Navigator.of(context).pop(_EntryFormResult(
      timestampMillis: _time.millisecondsSinceEpoch,
      kmOut: kmOut,
      kmBack: kmBack,
      notes: _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale =
        ref.watch(settingsProvider.select((s) => s.languageCode));
    final timeLabel = DateFormat.Hm(locale == 'ar' ? 'ar' : 'en')
        .format(_time);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.entry == null ? l10n.addOrder : l10n.editOrder,
              style:
                  text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(l10n.orderTime, style: text.titleSmall),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time_rounded, size: 18),
                  label: Text(timeLabel),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _kmOut,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    decoration: InputDecoration(
                      labelText: '${l10n.kmOutLabel} (${l10n.kmUnit})',
                      hintText: '0',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _kmBack,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    decoration: InputDecoration(
                      labelText: '${l10n.kmBackLabel} (${l10n.kmUnit})',
                      hintText: '0',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration:
                  InputDecoration(hintText: l10n.notesOptional),
              maxLines: 1,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: GlassButton(
                label: l10n.save,
                icon: Icons.check_rounded,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
