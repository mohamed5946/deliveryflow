import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';
import '../../core/money_format.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';
import '../../theme/top_snack_bar.dart';
import '../../theme/page_transitions.dart';
import '../../theme/pressable.dart';
import '../daily_orders/order_detail_screen.dart';

/// Drill-down: all orders of a single day from the history week view.
///
/// Tapping a row opens the full [OrderDetailScreen] (map, times,
/// distances) — the detail UI is reused, not duplicated.
class DayOrdersScreen extends ConsumerWidget {
  final String dateKey;

  const DayOrdersScreen({super.key, required this.dateKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale =
        ref.watch(settingsProvider.select((s) => s.languageCode));
    final loc = locale == 'ar' ? 'ar' : 'en';

    final db = ref.watch(databaseServiceProvider);
    ref.watch(dataVersionProvider);
    final day = WeekCalendar.parseDateKey(dateKey);
    final record = db.orderRecord(dateKey);
    final entries =
        List<OrderEntry>.from(record?.entries ?? [])
          ..sort((a, b) =>
              a.timestampMillis.compareTo(b.timestampMillis));
    // v26: a day can hold a bulk count with no detailed entries.
    final bulkCount = record?.completedOrders ?? 0;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(
          '${DateFormat.EEEE(loc).format(day)} • ${DateFormat.yMMMd(loc).format(day)}',
        ),
      ),
      body: entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: bulkCount > 0
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$bulkCount',
                              style: text.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary)),
                          const SizedBox(height: 4),
                          Text(l10n.ordersLabel, style: text.bodyMedium),
                          const SizedBox(height: 8),
                          Text(
                            l10n.ordersWithoutDetails(bulkCount),
                            textAlign: TextAlign.center,
                            style: text.bodySmall?.copyWith(
                                color: scheme.onSurface
                                    .withValues(alpha: 0.6)),
                          ),
                        ],
                      )
                    : Text(
                        l10n.noOrdersThisDay,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
              ),
            )
          : ListView.builder(
              padding: GlassTokens.screenPadding,
              itemCount: entries.length,
              itemBuilder: (ctx, i) {
                final entry = entries[i];
                final time = DateFormat.Hm(loc).format(
                  DateTime.fromMillisecondsSinceEpoch(
                      entry.timestampMillis),
                );
                final (statusLabel, statusColor) =
                    switch (entry.status) {
                  1 => (l10n.statusToCustomer, Colors.orange),
                  2 => (l10n.statusToMart, Colors.blue),
                  3 => (l10n.statusCompleted, Colors.green),
                  _ => (
                      l10n.statusPending,
                      scheme.onSurface.withValues(alpha: 0.55)
                    ),
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Pressable(
                    // v27.1: count-only rows have no delivery detail to
                    // open — they stay non-navigating (delete only).
                    onTap: entry.countOnly
                        ? null
                        : () => Navigator.of(context).push(
                              SmoothPageRoute(
                                builder: (_) => OrderDetailScreen(
                                  dateKey: dateKey,
                                  entryId: entry.id,
                                ),
                              ),
                            ),
                    // v27.20 Hero source: this order card flies to
                    // the detail trip card (tag unique per order).
                    child: Hero(
                      tag: orderDetailHeroTag(entry.id),
                      child: Material(
                        type: MaterialType.transparency,
                        child: GlassCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: scheme.primary
                                  .withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(10),
                            ),
                            child: Text(
                              time,
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      entry.countOnly
                                          ? l10n.countOnlyOrder
                                          : '${entry.effectiveKmTotal.toStringAsFixed(2)} ${l10n.kmUnit}',
                                      style: text.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (entry.hasManualKm) ...[
                                      const SizedBox(width: 6),
                                      const ManualBadge(),
                                    ],
                                    // v27.5: manual-bonus indicator.
                                    if (entry.manualBonusEgp > 0) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '+${formatMoney(entry.manualBonusEgp)} ${l10n.egpUnit}',
                                        style: text.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (entry.notes.isNotEmpty)
                                  Text(
                                    entry.notes,
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor
                                  .withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                            child: Text(
                              statusLabel,
                              style: text.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          if (!entry.countOnly) ...[
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: scheme.onSurface
                                  .withValues(alpha: 0.4),
                            ),
                            const SizedBox(width: 2),
                          ],
                          Pressable(
                            onTap: () =>
                                _deleteEntry(context, ref, entry),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: scheme.error
                                    .withValues(alpha: 0.10),
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: scheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  /// Deletes one order from any day (including past days) with
  /// confirmation. All aggregates (daily km/hours/count, weekly totals,
  /// charts, heatmap, salary) are derived from the remaining records,
  /// so they recompute automatically via [bumpDataVersion].
  Future<void> _deleteEntry(
      BuildContext context, WidgetRef ref, OrderEntry entry) async {
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
                style: TextStyle(
                    color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(databaseServiceProvider);
    await db.deleteOrderEntry(
        dateKey: dateKey, entryId: entry.id);
    bumpDataVersion(ref);
    if (context.mounted) {
      showTopSnackBar(context, l10n.orderDeleted);
    }
  }
}
