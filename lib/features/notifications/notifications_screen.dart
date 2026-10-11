import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';
import '../../theme/page_transitions.dart';
import '../../theme/pressable.dart';
import '../daily_orders/order_detail_screen.dart';

/// Feed of recent app events built from existing data.
///
/// Each row represents one completed order (newest first) and opens that
/// order's detail screen. The list is built once when the screen opens —
/// no polling, no streams.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<_NotificationItem>? _items;

  @override
  void initState() {
    super.initState();
    // Build once: no polling, no listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _items = _collectCompletedOrders());
    });
  }

  /// Walks back over the most recent days, collects completed orders
  /// (status == 3), newest first, capped at 30.
  List<_NotificationItem> _collectCompletedOrders() {
    final db = ref.read(databaseServiceProvider);
    final today = WeekCalendar.dateOnly(DateTime.now());
    final items = <_NotificationItem>[];
    // 60-day lookback is more than enough for a 30-item feed.
    for (var i = 0; i < 60 && items.length < 30; i++) {
      final day = today.subtract(Duration(days: i));
      final key = WeekCalendar.dateKey(day);
      final record = db.orderRecord(key);
      if (record == null) continue;
      for (final entry in record.entries) {
        if (entry.status == 3) {
          items.add(_NotificationItem(dateKey: key, entry: entry));
        }
      }
    }
    items.sort((a, b) =>
        b.entry.timestampMillis.compareTo(a.entry.timestampMillis));
    return items.take(30).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale =
        ref.watch(settingsProvider.select((s) => s.languageCode));
    final loc = locale == 'ar' ? 'ar' : 'en';

    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsTitle)),
      body: items == null
          ? const GlassLoading()
          : items.isEmpty
              ? _EmptyNotifications(l10n: l10n, text: text)
              : ListView.builder(
                  padding: GlassTokens.screenPadding,
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _NotificationRow(
                        item: item,
                        l10n: l10n,
                        text: text,
                        loc: loc,
                      ),
                    );
                  },
                ),
    );
  }
}

class _NotificationItem {
  final String dateKey;
  final OrderEntry entry;

  _NotificationItem({required this.dateKey, required this.entry});
}

class _NotificationRow extends StatelessWidget {
  final _NotificationItem item;
  final AppLocalizations l10n;
  final TextTheme text;
  final String loc;

  const _NotificationRow({
    required this.item,
    required this.l10n,
    required this.text,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    final shortId = entry.id.length > 8
        ? entry.id.substring(entry.id.length - 8)
        : entry.id;
    final when = DateFormat.yMd(loc).add_Hm().format(
          DateTime.fromMillisecondsSinceEpoch(entry.timestampMillis),
        );
    return Pressable(
      onTap: () => Navigator.of(context).push(
        SmoothPageRoute(
          builder: (_) => OrderDetailScreen(
            dateKey: item.dateKey,
            entryId: entry.id,
          ),
        ),
      ),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LiquidPalette.brandGradientLg,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color:
                        LiquidPalette.primaryBlue.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.notifOrderCompleted,
                          style: text.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (entry.hasManualKm) const ManualBadge(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '#$shortId • '
                    '${WeekCalendar.formatKm(entry.effectiveKmTotal)} ${l10n.kmUnit}',
                    style: text.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                    ),
                  ),
                  if (entry.hasManualKm)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        l10n.notifManualKm,
                        style: text.labelSmall?.copyWith(
                          color: Colors.amber.shade800,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    when,
                    style: text.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded,
                size: 18, color: LiquidPalette.primaryBlue),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  final AppLocalizations l10n;
  final TextTheme text;

  const _EmptyNotifications({required this.l10n, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    scheme.primary.withValues(alpha: 0.25),
                    scheme.secondary.withValues(alpha: 0.12),
                  ],
                ),
              ),
              child: Icon(Icons.notifications_outlined,
                  size: 44, color: scheme.primary),
            ),
            const SizedBox(height: 18),
            Text(l10n.noNotifications,
                style:
                    text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
