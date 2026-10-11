import 'dart:async';

import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/models.dart';
import '../../core/providers.dart';
import '../../core/tracking/delivery_tracking_service.dart';
import '../../theme/design_system.dart';
import 'live_trip_map_card.dart';
import 'route_map_card.dart';

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
  final _noteController = TextEditingController();
  Timer? _noteSaveTimer;
  bool _noteDirty = false;

  @override
  void initState() {
    super.initState();
    _load();
    _recoverTracking();
  }

  @override
  void dispose() {
    _noteSaveTimer?.cancel();
    // Flush any unsaved note text silently (no provider notifications
    // during teardown).
    if (_noteDirty) {
      _noteDirty = false;
      ref.read(databaseServiceProvider).updateOrderEntry(
            dateKey: widget.dateKey,
            entryId: widget.entryId,
            notes: _noteController.text.trim(),
          );
    }
    _noteController.dispose();
    super.dispose();
  }

  void _load() {
    final db = ref.read(databaseServiceProvider);
    final rec = db.orderRecord(widget.dateKey);
    final entries = rec?.entries ?? const <OrderEntry>[];
    final idx = entries.indexWhere((e) => e.id == widget.entryId);
    final entry = idx >= 0 ? entries[idx] : null;
    // Sync the field from the DB, but never clobber text the user is
    // currently typing.
    if (entry != null &&
        !_noteDirty &&
        _noteController.text != entry.notes) {
      _noteController.text = entry.notes;
    }
    setState(() {
      _entry = entry;
    });
  }

  /// If the app was killed/reopened mid-trip, re-attach the main isolate
  /// to the still-running background tracking session. If tracking
  /// should be running but isn't (system killed the service) and there's
  /// evidence it ran before (a progress file), offer a loud resume or
  /// manual entry — never silently record 0 km.
  Future<void> _recoverTracking() async {
    final svc = ref.read(deliveryTrackingServiceProvider);
    final recovered = await svc.recoverTracking(widget.entryId);
    if (!mounted || recovered) return;
    final entry = _entry;
    if (entry == null || !entry.isTracking) return;
    final progress = await svc.readLiveProgress(widget.entryId);
    if (!mounted || progress == null) return;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final choice = await showDialog<_TrackingFailureChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: scheme.error, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(l10n.trackingStoppedTitle)),
          ],
        ),
        content: Text(l10n.trackingStoppedBody),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_TrackingFailureChoice.manual),
            child: Text(l10n.enterManualKm),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_TrackingFailureChoice.retry),
            child: Text(l10n.startTracking),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == _TrackingFailureChoice.retry) {
      setState(() => _busy = true);
      try {
        await svc.resumeTracking(
          entryId: widget.entryId,
          segment: entry.isToCustomer
              ? TrackingSegment.outgoing
              : TrackingSegment.returning,
        );
        bumpDataVersion(ref);
        _load();
      } catch (e) {
        if (!mounted) return;
        await _showBlockingError(
          l10n.trackingFailedTitle,
          _errorText(e),
        );
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else if (choice == _TrackingFailureChoice.manual) {
      await _showManualKmDialog(
        outgoing: entry.isToCustomer,
        onSave: (km) =>
            _saveManualKm(outgoing: entry.isToCustomer, km: km),
      );
    }
  }

  void _onNoteChanged(String value) {
    _noteDirty = true;
    _noteSaveTimer?.cancel();
    _noteSaveTimer = Timer(
      const Duration(milliseconds: 800),
      () {
        if (mounted) _persistNote();
      },
    );
  }

  void _persistNote() {
    _noteSaveTimer?.cancel();
    if (!_noteDirty) return;
    _noteDirty = false;
    ref.read(databaseServiceProvider).updateOrderEntry(
          dateKey: widget.dateKey,
          entryId: widget.entryId,
          notes: _noteController.text.trim(),
        );
    bumpDataVersion(ref);
  }

  Future<void> _startDelivery() async {
    if (_busy) return;
    _persistNote();
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
      // Never get stuck: reset busy (the retry path re-enters this
      // method) and offer retry or manual km entry.
      setState(() => _busy = false);
      await _showTrackingFailedActions(
        error: e,
        onRetry: _startDelivery,
        manualLegOutgoing: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tracking failed to start: blocking dialog with two ways forward —
  /// retry, or enter the kilometers manually. The order is never stuck.
  Future<void> _showTrackingFailedActions({
    required Object error,
    required Future<void> Function() onRetry,
    required bool manualLegOutgoing,
  }) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final msg = error.toString();
    final message = msg.contains('Location permission')
        ? l10n.locationPermissionRequired
        : _errorText(error);
    final choice = await showDialog<_TrackingFailureChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: scheme.error, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(l10n.trackingStartFailed)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_TrackingFailureChoice.manual),
            child: Text(l10n.enterManualKm),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_TrackingFailureChoice.retry),
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == _TrackingFailureChoice.retry) {
      await onRetry();
    } else if (choice == _TrackingFailureChoice.manual) {
      await _showManualKmDialog(
        outgoing: manualLegOutgoing,
        onSave: (km) =>
            _saveManualKm(outgoing: manualLegOutgoing, km: km),
      );
    }
  }

  double _currentManualKm(bool outgoing) {
    final e = _entry;
    if (e == null) return 0;
    return outgoing ? e.kmOut : e.kmBack;
  }

  /// Numeric km entry dialog for the current leg. GPS values take
  /// precedence when present; the manual value is fallback-only.
  Future<void> _showManualKmDialog({
    required bool outgoing,
    required Future<void> Function(double km) onSave,
  }) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final current = _currentManualKm(outgoing);
    final controller = TextEditingController(
      text: current > 0 ? current.toString() : '',
    );
    final km = await showDialog<double>(
      context: context,
      builder: (ctx) {
        var error = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void trySubmit() {
              final raw =
                  controller.text.trim().replaceAll(',', '.');
              final value = double.tryParse(raw);
              if (value == null || value <= 0) {
                setDialogState(() => error = l10n.invalidKm);
                return;
              }
              Navigator.of(ctx).pop(value);
            }

            return AlertDialog(
              title: Text(l10n.enterManualKm),
              content: TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(
                        decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.manualKmLabel,
                  hintText: l10n.manualKmHint,
                  errorText: error.isEmpty ? null : error,
                ),
                onSubmitted: (_) => trySubmit(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: trySubmit,
                  child: Text(l10n.save),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (km != null && mounted) {
      await onSave(km);
    }
  }

  /// Persists a manually entered km for the current leg. When the order
  /// is still pending and the outgoing leg never started, this puts the
  /// order into manual travel mode (no background tracking).
  Future<void> _saveManualKm({
    required bool outgoing,
    required double km,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (outgoing && (_entry?.isPending ?? false)) {
        await ref
            .read(deliveryTrackingServiceProvider)
            .startManualOutgoing(
              dateKey: widget.dateKey,
              entryId: widget.entryId,
              kmOut: km,
            );
      } else {
        await ref.read(databaseServiceProvider).updateOrderEntry(
              dateKey: widget.dateKey,
              entryId: widget.entryId,
              kmOut: outgoing ? km : null,
              kmBack: outgoing ? null : km,
            );
      }
      bumpDataVersion(ref);
      _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markDelivered() async {
    if (_busy) return;
    _persistNote();
    setState(() => _busy = true);
    try {
      final svc = ref.read(deliveryTrackingServiceProvider);
      await svc.markDelivered(
        dateKey: widget.dateKey,
        entryId: widget.entryId,
      );
      bumpDataVersion(ref);
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _load();
      // If the outgoing leg was saved (status == toMart) but the return
      // leg failed to start, offer retry or manual entry — don't
      // silently lose the return trip.
      final entry = _entry;
      if (entry != null && entry.isToMart) {
        await _showReturnTrackingRetry();
      } else {
        final l10n = AppLocalizations.of(context);
        await _showBlockingError(
          l10n.trackingFailedTitle,
          _errorText(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryReturnLeg() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(deliveryTrackingServiceProvider)
          .startReturnLeg(entryId: widget.entryId);
      bumpDataVersion(ref);
      _load();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      await _showBlockingError(
        l10n.trackingFailedTitle,
        _errorText(e),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorText(Object e) =>
      e is StateError ? e.message : e.toString();

  /// Blocking error dialog the user can't miss — used for tracking
  /// failures that must never pass silently.
  Future<void> _showBlockingError(String title, String message) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: scheme.error, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  /// The outgoing leg was saved but return tracking failed to start.
  /// Loud dialog: retry, or enter the return km manually.
  Future<void> _showReturnTrackingRetry() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final choice = await showDialog<_TrackingFailureChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: scheme.error, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(l10n.trackingFailedTitle)),
          ],
        ),
        content: Text(l10n.returnTrackingFailed),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_TrackingFailureChoice.manual),
            child: Text(l10n.enterManualKm),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_TrackingFailureChoice.retry),
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == _TrackingFailureChoice.retry) {
      await _retryReturnLeg();
    } else if (choice == _TrackingFailureChoice.manual) {
      await _showManualKmDialog(
        outgoing: false,
        onSave: (km) => _saveManualKm(outgoing: false, km: km),
      );
    }
  }

  Future<void> _markArrivedAtMart() async {
    if (_busy) return;
    _persistNote();
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
            LiveTripMapCard(
              entryId: entry.id,
              isOutgoing: entry.isToCustomer,
            ),
            const SizedBox(height: 12),
          ],
          if (entry.isCompleted) ...[
            _breakdownCard(context, entry),
            const SizedBox(height: 12),
            RouteMapCard(entry: entry),
            const SizedBox(height: 12),
          ],
          _noteCard(context, entry),
          const SizedBox(height: 12),
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

    // When no live snapshot is flowing (service dead, or manual mode),
    // fall back to the manually entered km so the courier always sees
    // a number — never a stuck 0.
    final manualKm = entry.isToCustomer ? entry.kmOut : entry.kmBack;
    final km = isMine ? snapshot.kmSoFar : manualKm;
    final showingManual = !isMine && manualKm > 0;
    final elapsed = isMine
        ? snapshot.elapsed
        : (entry.pickupTimeMillis == null
            ? Duration.zero
            : DateTime.now().difference(
                DateTime.fromMillisecondsSinceEpoch(
                    entry.pickupTimeMillis!)));
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
                  manual: showingManual,
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
          // Manual fallback affordance: if GPS drops mid-trip the
          // courier can always enter the distance by hand.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _showManualKmDialog(
                outgoing: entry.isToCustomer,
                onSave: (km) => _saveManualKm(
                    outgoing: entry.isToCustomer, km: km),
              ),
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: Text(l10n.editManualDistance),
            ),
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
              Colors.orange,
              manual: entry.isManualOut),
          _row(context, l10n.deliveryTime,
              fmtTime(entry.deliveredTimeMillis), Icons.person_pin_rounded,
              scheme.secondary),
          _row(
              context,
              l10n.returnLeg,
              '${_fmtKm(entry.effectiveKmBack)} ${l10n.kmUnit} • ${_fmtDuration(Duration(seconds: entry.returnDurationSec))}',
              Icons.keyboard_return_rounded,
              Colors.blue,
              manual: entry.isManualBack),
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
      {bool bold = false, bool manual = false}) {
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
          if (manual) ...[
            const ManualBadge(),
            const SizedBox(width: 6),
          ],
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
      String label, Color color,
      {bool manual = false}) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Text('$value${unit.isNotEmpty ? ' $unit' : ''}',
            style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: text.bodySmall),
        if (manual) ...[
          const SizedBox(height: 4),
          const ManualBadge(),
        ],
      ],
    );
  }

  /// Trip note (address etc.): editable while the order is active,
  /// read-only after completion when non-empty, hidden when empty.
  /// Max 500 characters, saved debounced to the DB.
  Widget _noteCard(BuildContext context, OrderEntry entry) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (entry.isCompleted) {
      if (entry.notes.isEmpty) return const SizedBox.shrink();
      return GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sticky_note_2_outlined,
                    size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(l10n.tripNote,
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            Text(entry.notes, style: text.bodyMedium),
          ],
        ),
      );
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sticky_note_2_outlined,
                  size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(l10n.tripNote,
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            maxLength: 500,
            maxLines: 4,
            minLines: 2,
            textInputAction: TextInputAction.done,
            onChanged: _onNoteChanged,
            decoration: InputDecoration(
              hintText: l10n.tripNoteHint,
              counterStyle: text.bodySmall?.copyWith(
                  color:
                      scheme.onSurface.withValues(alpha: 0.45)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pulsingDot(Color color) {
    return _PulsingDot(color: color);
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

/// Choice from a tracking-failure dialog: retry the start, or fall back
/// to manual km entry.
enum _TrackingFailureChoice { retry, manual }

/// Small dot that actually pulses (repeating fade in/out).
/// The old one-shot TweenAnimationBuilder never repeated.
class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.35,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
        ),
      ),
    );
  }
}
