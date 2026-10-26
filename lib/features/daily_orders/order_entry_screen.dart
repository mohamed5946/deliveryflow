import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/models.dart';
import '../../core/date_time/day_rollover.dart';
import '../../core/money_format.dart';
import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../core/tracking/delivery_tracking_service.dart';
import '../../theme/design_system.dart';
import '../../theme/top_snack_bar.dart';
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
  late final DayRolloverWatcher _rollover;

  @override
  void initState() {
    super.initState();
    _dateKey = widget.dateKey ?? WeekCalendar.dateKey(DateTime.now());
    _rollover = DayRolloverWatcher(onDayChanged: _handleDayChanged);
    _rollover.start();
    _notesFocus.addListener(() {
      if (!_notesFocus.hasFocus && _notesDirty) _saveNotes();
    });
    _load();
  }

  /// v26 midnight rollover: only follow into the new day when this screen
  /// defaulted to "today" and is still untouched — never retarget a day
  /// the user is actively working on.
  void _handleDayChanged(DateTime previous, DateTime current) {
    if (!mounted) return;
    if (widget.dateKey != null) return;
    if (_notesDirty || _entries.isNotEmpty || _count > 0) return;
    _dateKey = WeekCalendar.dateKey(current);
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
    _rollover.dispose();
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

  /// v27: the «أضف أوردر» button first asks HOW to log — the
  /// standalone bulk-count button was too easy to miss. «أوردر
  /// بتفاصيل» runs the existing detailed add flow; «تسجيل العدد فقط»
  /// opens the existing bulk-count dialog.
  Future<void> _showAddOrderChoice() async {
    final l10n = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: GlassCard(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.addOrder,
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _addChoiceRow(
                  sheetContext,
                  icon: Icons.receipt_long_rounded,
                  title: l10n.addOrderDetailed,
                  subtitle: l10n.addOrderDetailedDesc,
                  onTap: () => Navigator.of(sheetContext).pop('detailed'),
                ),
                const Divider(height: 8),
                _addChoiceRow(
                  sheetContext,
                  icon: Icons.numbers_rounded,
                  title: l10n.logCountOnly,
                  subtitle: l10n.bulkCountHint,
                  onTap: () => Navigator.of(sheetContext).pop('count'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'detailed') {
      await _addEntry();
    } else if (choice == 'count') {
      await _logBulkCount();
    }
  }

  Widget _addChoiceRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassTokens.radiusS),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              scheme.onSurface.withValues(alpha: 0.65))),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20,
                color: scheme.onSurface.withValues(alpha: 0.35)),
          ],
        ),
      ),
    );
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

  /// Bulk entry: set the day's TOTAL order count with no per-order
  /// details. v27.1: the total is backed by real count-only entries
  /// (born completed) instead of a bare number, so every bulk order
  /// shows in the day's list and can be deleted individually; raising
  /// the total adds entries, lowering it removes count-only entries
  /// first (a small legacy bare remainder, if any, is adjusted last).
  Future<void> _logBulkCount() async {
    final l10n = AppLocalizations.of(context);
    final ctrl =
        TextEditingController(text: _count > 0 ? '$_count' : '');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bulkCountTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.bulkCountHint,
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration:
                  InputDecoration(hintText: l10n.ordersLabel),
            ),
            if (_entries.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l10n.bulkCountIncludesDetails(_countedEntries),
                  style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    // The total can never drop below the entries already counted
    // (delivery started, v27) — a bulk log never erases tracked work.
    final total = value.clamp(_countedEntries, 9999);
    final db = ref.read(databaseServiceProvider);
    final delta = total - _count;
    if (delta > 0) {
      // More orders: materialize them as count-only entries (each is
      // born counted, so the stored total lands exactly on target).
      await db.addCountOnlyEntries(
        dateKey: _dateKey,
        count: delta,
        timestampMillis: DateTime.now().millisecondsSinceEpoch,
      );
      // Keep the day's notes in sync, exactly like the old upsert did.
      await db.upsertOrderRecord(
        dateKey: _dateKey,
        completedOrders: total,
        notes: _notes.text.trim(),
      );
    } else if (delta < 0) {
      // Fewer orders: remove count-only entries first, newest first,
      // so a mistaken bulk log is undone entry by entry.
      var remaining = -delta;
      final removable = _entries.where((e) => e.countOnly).toList()
        ..sort((a, b) => b.timestampMillis.compareTo(a.timestampMillis));
      for (final e in removable) {
        if (remaining <= 0) break;
        await db.deleteOrderEntry(dateKey: _dateKey, entryId: e.id);
        remaining--;
      }
      if (remaining > 0) {
        // Only a legacy bare-number remainder can still be too high.
        await db.upsertOrderRecord(
          dateKey: _dateKey,
          completedOrders: total,
          notes: _notes.text.trim(),
        );
      }
    } else {
      await db.upsertOrderRecord(
        dateKey: _dateKey,
        completedOrders: total,
        notes: _notes.text.trim(),
      );
    }
    _notesDirty = false;
    if (!mounted) return;
    bumpDataVersion(ref);
    await ref.read(settingsProvider.notifier).refreshReminders();
    _load();
    if (!mounted) return;
    showTopSnackBar(context, l10n.recordSaved);
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
    showTopSnackBar(context, l10n.orderDeleted);
  }

  /// How many of this day's entries are already counted toward the
  /// day total — only entries whose delivery started count (v27).
  int get _countedEntries => _entries.where((e) => e.status >= 1).length;

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

    final undetailed = _count - _countedEntries;

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
              onPressed: _showAddOrderChoice,
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
            ..._entries.map((e) => e.countOnly
                ? _countOnlyCard(context, e)
                : _entryCard(context, e)),
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

  /// v27.1: a bulk-logged order (count-only) renders as a simple row —
  /// label + time + delete. It is a finished order with no delivery to
  /// track, so the row deliberately does NOT navigate to the order
  /// detail / بدأ التوصيل lifecycle; deletion is its only action.
  Widget _countOnlyCard(BuildContext context, OrderEntry entry) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(settingsProvider.select((s) => s.languageCode));
    final time = DateFormat.Hm(locale == 'ar' ? 'ar' : 'en')
        .format(entry.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
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
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(l10n.statusCompleted,
                  style: text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.green)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.numbers_rounded,
                      size: 18,
                      color:
                          scheme.onSurface.withValues(alpha: 0.55)),
                  const SizedBox(width: 6),
                  Text(l10n.countOnlyOrder,
                      style: text.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
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
      ),
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
        // v27.20 Hero source: this card flies to the detail trip
        // card. Tag is unique per order id (see orderDetailHeroTag).
        child: Hero(
          tag: orderDetailHeroTag(entry.id),
          child: Material(
            type: MaterialType.transparency,
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
                // v27.5: subtle manual-bonus indicator on the row.
                if (entry.manualBonusEgp > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                        '+${formatMoney(entry.manualBonusEgp)} ${l10n.egpUnit}',
                        style: text.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.green)),
                  ),
                ],
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
