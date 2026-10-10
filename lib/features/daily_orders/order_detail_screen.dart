import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/models.dart';
import '../../core/providers.dart';
import '../../core/tracking/delivery_tracking_service.dart';
import '../../theme/design_system.dart';

/// Order detail + GPS-tracked delivery lifecycle.
///
/// Shows the full breakdown the user asked for:
/// - pickup time, outgoing duration & distance (mart → customer)
/// - delivery time, return duration & distance (customer → mart)
/// - total time and total distance
///
/// Lifecycle buttons:
/// - pending → "بدأ التوصيل" (starts GPS tracking)
/// - toCustomer → "وصلت للعميل" (stops outgoing, starts return)
/// - toMart → "وصلت للمارت" (stops return, completes order)
class OrderDetailScreen extends ConsumerStatefulWidget {
  final String dateKey;
  final String entryId;

  const OrderDetailScreen({
    super.key,
    required this.dateKey,
    required this.entryId,
  });

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  OrderEntry? _entry;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final db = ref.read(databaseServiceProvider);
    final rec = db.orderRecord(widget.dateKey);
    final entries = rec?.entries ?? const <OrderEntry>[];
    final idx = entries.indexWhere((e) => e.id == widget.entryId);
    setState(() {
      _entry = idx >= 0 ? entries[idx] : null;
    });
  }

  Future<void> _startDelivery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final svc = ref.read(deliveryTrackingServiceProvider);
      await svc.startOutgoing(
        dateKey: widget.dateKey,
        entryId: widget.entryId,
      );
      bumpDataVersion(ref);
      _load();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.locationPermissionRequired)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markDelivered() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final svc = ref.read(deliveryTrackingServiceProvider);
      await svc.markDelivered(
        dateKey: widget.dateKey,
        entryId: widget.entryId,
      );
      bumpDataVersion(ref);
      _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markArrivedAtMart() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final svc = ref.read(deliveryTrackingServiceProvider);
      await svc.markArrivedAtMart(
        dateKey: widget.dateKey,
        entryId: widget.entryId,
      );
      bumpDataVersion(ref);
      _load();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.orderCompleted)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entry = _entry;
    if (entry == null) {
      return const GlassScaffold(body: GlassLoading());
    }

    return GlassScaffold(
      appBar: AppBar(title: Text(l10n.orderDetails)),
      body: ListView(
        padding: GlassTokens.screenPadding,
        children: [
          _statusCard(context, entry),
          const SizedBox(height: 12),
          if (entry.isTracking) ...[
            _liveTrackingCard(context, entry),
            const SizedBox(height: 12),
          ],
          if (entry.isCompleted) ...[
            _breakdownCard(context, entry),
            const SizedBox(height: 12),
          ],
          _actionButton(context, entry),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context, OrderEntry entry) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final (label, color, icon) = switch (entry.status) {
      1 => (l10n.statusToCustomer, Colors.orange, Icons.delivery_dining_rounded),
      2 => (l10n.statusToMart, Colors.blue, Icons.keyboard_return_rounded),
      3 => (l10n.statusCompleted, Colors.green, Icons.check_circle_rounded),
      _ => (l10n.statusPending, scheme.onSurface.withValues(alpha: 0.6),
          Icons.pending_outlined),
    };

    return GlassCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800, color: color)),
                if (entry.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(entry.notes,
                      style: text.bodySmall?.copyWith(
                          color:
                              scheme.onSurface.withValues(alpha: 0.6))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveTrackingCard(BuildContext context, OrderEntry entry) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final snapshot = ref.watch(trackingSnapshotProvider).valueOrNull;
    final isMine =
        snapshot != null && snapshot.orderId == entry.id;

    final km = isMine ? snapshot.kmSoFar : 0.0;
    final elapsed = isMine ? snapshot.elapsed : Duration.zero;
    final legLabel = entry.isToCustomer
        ? l10n.trackingToCustomer
        : l10n.trackingToMart;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _pulsingDot(scheme.primary),
              const SizedBox(width: 8),
              Text(legLabel,
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _statColumn(
                  context,
                  _fmtKm(km),
                  l10n.kmUnit,
                  l10n.distanceSoFar,
                  scheme.primary,
                ),
              ),
              Container(
                  width: 1,
                  height: 56,
                  color: Colors.white.withValues(alpha: 0.15)),
              Expanded(
                child: _statColumn(
                  context,
                  _fmtDuration(elapsed),
                  '',
                  l10n.timeElapsed,
                  scheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.gpsAccuracyNote,
            style: text.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _breakdownCard(BuildContext context, OrderEntry entry) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale =
        ref.watch(settingsProvider.select((s) => s.languageCode));
    final timeFmt =
        DateFormat.Hm(locale == 'ar' ? 'ar' : 'en');

    String fmtTime(int? millis) => millis == null
        ? '—'
        : timeFmt.format(
            DateTime.fromMillisecondsSinceEpoch(millis));

    final totalSec =
        entry.outgoingDurationSec + entry.returnDurationSec;
    final totalKm = entry.effectiveKmTotal;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.tripBreakdown,
              style:
                  text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _row(context, l10n.pickupTime, fmtTime(entry.pickupTimeMillis),
              Icons.store_rounded, scheme.primary),
          _row(
              context,
              l10n.outgoingLeg,
              '${_fmtKm(entry.effectiveKmOut)} ${l10n.kmUnit} • ${_fmtDuration(Duration(seconds: entry.outgoingDurationSec))}',
              Icons.delivery_dining_rounded,
              Colors.orange),
          _row(context, l10n.deliveryTime,
              fmtTime(entry.deliveredTimeMillis), Icons.person_pin_rounded,
              scheme.secondary),
          _row(
              context,
              l10n.returnLeg,
              '${_fmtKm(entry.effectiveKmBack)} ${l10n.kmUnit} • ${_fmtDuration(Duration(seconds: entry.returnDurationSec))}',
              Icons.keyboard_return_rounded,
              Colors.blue),
          _row(context, l10n.martArrivalTime,
              fmtTime(entry.martArrivedTimeMillis),
              Icons.check_circle_rounded, Colors.green),
          const Divider(height: 24),
          _row(
              context,
              l10n.totalTripTime,
              _fmtDuration(Duration(seconds: totalSec)),
              Icons.timer_rounded,
              scheme.primary,
              bold: true),
          _row(context, l10n.totalTripDistance,
              '${_fmtKm(totalKm)} ${l10n.kmUnit}', Icons.route_rounded,
              scheme.secondary,
              bold: true),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      IconData icon, Color color,
      {bool bold = false}) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: text.bodyMedium),
          ),
          Text(
            value,
            style: text.bodyMedium?.copyWith(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: bold ? color : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statColumn(BuildContext context, String value, String unit,
      String label, Color color) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Text('$value${unit.isNotEmpty ? ' $unit' : ''}',
            style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: text.bodySmall),
      ],
    );
  }

  Widget _pulsingDot(Color color) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1.0),
      duration: const Duration(milliseconds: 800),
      builder: (context, v, _) => Opacity(
        opacity: v,
        child: Container(
          width: 12,
          height: 12,
          decoration:
              BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
      onEnd: () {},
    );
  }

  Widget _actionButton(BuildContext context, OrderEntry entry) {
    final l10n = AppLocalizations.of(context);
    if (entry.isPending) {
      return SizedBox(
        width: double.infinity,
        child: GlassButton(
          label: _busy ? l10n.pleaseWait : l10n.startDelivery,
          icon: Icons.play_arrow_rounded,
          onPressed: _busy ? null : _startDelivery,
        ),
      );
    }
    if (entry.isToCustomer) {
      return SizedBox(
        width: double.infinity,
        child: GlassButton(
          label: _busy ? l10n.pleaseWait : l10n.arrivedAtCustomer,
          icon: Icons.check_rounded,
          onPressed: _busy ? null : _markDelivered,
        ),
      );
    }
    if (entry.isToMart) {
      return SizedBox(
        width: double.infinity,
        child: GlassButton(
          label: _busy ? l10n.pleaseWait : l10n.arrivedAtMart,
          icon: Icons.check_rounded,
          onPressed: _busy ? null : _markArrivedAtMart,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

String _fmtKm(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

String _fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
