import 'dart:async';

import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/database/models.dart';
import '../../core/providers.dart';
import '../../core/tracking/delivery_tracking_service.dart';
import '../../theme/design_system.dart';
import '../../theme/pressable.dart';

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
  final _phoneController = TextEditingController();
  Timer? _phoneSaveTimer;
  bool _phoneDirty = false;
  final _scrollController = ScrollController();
  final _detailsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
    _recoverTracking();
  }

  @override
  void dispose() {
    _noteSaveTimer?.cancel();
    _phoneSaveTimer?.cancel();
    // Flush any unsaved note/phone text silently (no provider notifications
    // during teardown).
    if (_noteDirty) {
      _noteDirty = false;
      ref.read(databaseServiceProvider).updateOrderEntry(
            dateKey: widget.dateKey,
            entryId: widget.entryId,
            notes: _noteController.text.trim(),
          );
    }
    if (_phoneDirty) {
      _phoneDirty = false;
      ref.read(databaseServiceProvider).updateOrderEntry(
            dateKey: widget.dateKey,
            entryId: widget.entryId,
            phone: _phoneController.text.trim(),
          );
    }
    _noteController.dispose();
    _phoneController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _load() {
    final db = ref.read(databaseServiceProvider);
    final rec = db.orderRecord(widget.dateKey);
    final entries = rec?.entries ?? const <OrderEntry>[];
    final idx = entries.indexWhere((e) => e.id == widget.entryId);
    final entry = idx >= 0 ? entries[idx] : null;
    // Sync the fields from the DB, but never clobber text the user is
    // currently typing.
    if (entry != null &&
        !_noteDirty &&
        _noteController.text != entry.notes) {
      _noteController.text = entry.notes;
    }
    if (entry != null &&
        !_phoneDirty &&
        _phoneController.text != entry.phone) {
      _phoneController.text = entry.phone;
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

  void _onPhoneChanged(String value) {
    _phoneDirty = true;
    _phoneSaveTimer?.cancel();
    _phoneSaveTimer = Timer(
      const Duration(milliseconds: 800),
      () {
        if (mounted) _persistPhone();
      },
    );
  }

  void _persistPhone() {
    _phoneSaveTimer?.cancel();
    if (!_phoneDirty) return;
    _phoneDirty = false;
    ref.read(databaseServiceProvider).updateOrderEntry(
          dateKey: widget.dateKey,
          entryId: widget.entryId,
          phone: _phoneController.text.trim(),
        );
    bumpDataVersion(ref);
  }

  Future<void> _startDelivery() async {
    if (_busy) return;
    _persistNote();
    _persistPhone();
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

    // Map-first hero (mockup's "التوصيل الآن"): live map while the trip
    // is being tracked, recorded route once completed. Pending orders and
    // completed orders without route points get no hero.
    final hasHero = entry.isTracking || entry.hasRoute;
    // The info card is pulled up over the map's lower edge like the
    // mockup; everything below it is pulled up by the same overlap
    // minus the visual gap, so the layout stays seamless.
    const overlap = 40.0;
    const gap = 12.0;

    return GlassScaffold(
      appBar: AppBar(title: Text(l10n.orderDetails)),
      body: ListView(
        controller: _scrollController,
        padding: EdgeInsets.zero,
        children: [
          if (hasHero)
            _DeliveryHeroMap(
              entry: entry,
              height: MediaQuery.of(context).size.height * 0.48,
            ),
          Transform.translate(
            offset: Offset(0, hasHero ? -overlap : 0),
            child: Padding(
              padding:
                  EdgeInsets.fromLTRB(16, hasHero ? 0 : 16, 16, 0),
              child: _tripInfoCard(context, entry),
            ),
          ),
          Transform.translate(
            offset: Offset(0, hasHero ? -(overlap - gap) : 0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, gap, 16, 0),
              child: Column(
                key: _detailsKey,
                children: [
                  if (entry.isCompleted) ...[
                    _breakdownCard(context, entry),
                    const SizedBox(height: 12),
                  ],
                  _noteCard(context, entry),
                  const SizedBox(height: 12),
                  _actionButton(context, entry),
                  SizedBox(
                      height: 24 + (hasHero ? (overlap - gap) : 0)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Smooth-scrolls the details section below the info card into view
  /// (the mockup's "عرض التفاصيل" button).
  void _scrollToDetails() {
    final ctx = _detailsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      alignment: 0.02,
    );
  }

  /// Mockup's "التوصيل الآن" card, shown for every status: order number,
  /// status line, address row (notes), phone row with tap-to-call, km +
  /// time chips with the manual "يدوي" badges + edit affordance, and the
  /// gradient "عرض التفاصيل" button.
  Widget _tripInfoCard(BuildContext context, OrderEntry entry) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final snapshot = ref.watch(trackingSnapshotProvider).valueOrNull;
    final isMine =
        snapshot != null && snapshot.orderId == entry.id;

    final String heading;
    final Color headingColor;
    if (entry.isToCustomer) {
      heading = l10n.onWayToCustomer;
      headingColor = Colors.orange;
    } else if (entry.isToMart) {
      heading = l10n.onWayToMart;
      headingColor = LiquidPalette.primaryBlue;
    } else if (entry.isCompleted) {
      heading = l10n.statusCompleted;
      headingColor = Colors.green;
    } else {
      heading = l10n.statusPending;
      headingColor = scheme.onSurface.withValues(alpha: 0.6);
    }

    final shortId = entry.id.length > 6
        ? entry.id.substring(entry.id.length - 6)
        : entry.id;

    // Km + elapsed for the chips. Pending orders have no trip yet, so
    // the chips row is hidden for them.
    final showChips = !entry.isPending;
    double km = 0;
    Duration elapsed = Duration.zero;
    bool showManualBadge = false;
    if (entry.isTracking) {
      final manualKm = entry.isToCustomer ? entry.kmOut : entry.kmBack;
      km = isMine ? snapshot.kmSoFar : manualKm;
      showManualBadge = !isMine && manualKm > 0;
      elapsed = isMine
          ? snapshot.elapsed
          : (entry.pickupTimeMillis == null
              ? Duration.zero
              : DateTime.now().difference(
                  DateTime.fromMillisecondsSinceEpoch(
                      entry.pickupTimeMillis!)));
    } else if (entry.isCompleted) {
      km = entry.effectiveKmTotal;
      showManualBadge = entry.hasManualKm;
      elapsed = Duration(
          seconds:
              entry.outgoingDurationSec + entry.returnDurationSec);
    }

    Widget chip(IconData icon, String value, {bool manual = false}) {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: LiquidPalette.primaryBlue.withValues(alpha: 0.10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: LiquidPalette.primaryBlue),
            const SizedBox(width: 5),
            Text(value,
                style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: LiquidPalette.primaryBlue)),
            if (manual) ...[
              const SizedBox(width: 4),
              const ManualBadge(),
            ],
          ],
        ),
      );
    }

    return GlassCard(
      borderRadius: GlassTokens.radiusL,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (entry.isTracking)
                _pulsingDot(LiquidPalette.primaryBlue)
              else
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: headingColor,
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LiquidPalette.brandGradientLg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('#$shortId',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(heading,
                    style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: headingColor)),
              ),
            ],
          ),
          if (entry.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.location_on_rounded,
                    size: 17, color: LiquidPalette.primaryBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(entry.notes,
                      style: text.bodySmall?.copyWith(
                          color: scheme.onSurface
                              .withValues(alpha: 0.75)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
          if (entry.phone.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.phone_outlined,
                    size: 17,
                    color:
                        scheme.onSurface.withValues(alpha: 0.55)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(entry.phone,
                      textDirection: TextDirection.ltr,
                      style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Pressable(
                  onTap: () {
                    launchUrl(
                        Uri(scheme: 'tel', path: entry.phone));
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LiquidPalette.brandGradientLg,
                      boxShadow: [
                        BoxShadow(
                          color: LiquidPalette.primaryBlue
                              .withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.call_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ],
          if (showChips) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                chip(Icons.route_rounded,
                    '${_fmtKm(km)} ${l10n.kmUnit}',
                    manual: showManualBadge),
                const SizedBox(width: 8),
                chip(Icons.schedule_rounded, _fmtDuration(elapsed)),
              ],
            ),
            // Manual fallback affordance, exactly as before.
            if (entry.isTracking)
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: GlassButton(
              label: l10n.viewDetails,
              icon: Icons.keyboard_arrow_down_rounded,
              onPressed: _scrollToDetails,
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

  /// Trip note (address etc.) + optional phone number: editable while the
  /// order is active, read-only after completion when non-empty, hidden
  /// when empty. Note max 500 characters, both saved debounced to the DB.
  Widget _noteCard(BuildContext context, OrderEntry entry) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (entry.isCompleted) {
      if (entry.notes.isEmpty && entry.phone.isEmpty) {
        return const SizedBox.shrink();
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
            if (entry.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(entry.notes, style: text.bodyMedium),
            ],
            if (entry.phone.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.phone_outlined,
                      size: 18,
                      color: scheme.onSurface
                          .withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Text(entry.phone,
                      style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
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
          const SizedBox(height: 4),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onChanged: _onPhoneChanged,
            decoration: InputDecoration(
              hintText: l10n.phoneNumberHint,
              labelText: l10n.phoneNumber,
              prefixIcon: const Icon(Icons.phone_outlined),
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

/// Map-first hero for the order detail screen (mockup's "التوصيل الآن").
///
/// - While tracking: live map fed by the background isolate's progress
///   file, polled every 5s and rebuilt only when km/point count actually
///   change (same update mechanism as the old LiveTripMapCard).
/// - When completed: the recorded outgoing/return route with mart +
///   customer pins (same data as the old RouteMapCard).
///
/// Mockup styling: rounded ~24 corners, subtle brand-blue border, route
/// polyline in brand blue #0A84FF (5-6px), courier marker + destination
/// pins in brand colors. No continuous animations.
class _DeliveryHeroMap extends ConsumerStatefulWidget {
  final OrderEntry entry;
  final double height;

  const _DeliveryHeroMap({
    required this.entry,
    required this.height,
  });

  @override
  ConsumerState<_DeliveryHeroMap> createState() =>
      _DeliveryHeroMapState();
}

class _DeliveryHeroMapState extends ConsumerState<_DeliveryHeroMap> {
  Timer? _timer;
  LiveTripProgress? _progress;
  double _lastKm = -1;
  int _lastPoints = -1;

  @override
  void initState() {
    super.initState();
    if (widget.entry.isTracking) _startPolling();
  }

  @override
  void didUpdateWidget(covariant _DeliveryHeroMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entry.id != oldWidget.entry.id ||
        widget.entry.isTracking != oldWidget.entry.isTracking) {
      _timer?.cancel();
      _timer = null;
      _progress = null;
      _lastKm = -1;
      _lastPoints = -1;
      if (widget.entry.isTracking) _startPolling();
    }
  }

  void _startPolling() {
    _tick();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _tick(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    final svc = ref.read(deliveryTrackingServiceProvider);
    final p = await svc.readLiveProgress(widget.entry.id);
    if (!mounted) return;
    final km = p?.km ?? -1;
    final points = p?.pointCount ?? -1;
    // Only rebuild when something actually changed.
    if (km != _lastKm || points != _lastPoints) {
      setState(() {
        _progress = p;
        _lastKm = km;
        _lastPoints = points;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: LiquidPalette.primaryBlue.withValues(alpha: 0.18),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: widget.entry.isTracking ? _liveMap() : _routeMap(),
      ),
    );
  }

  /// Live trip: traveled route in brand blue + courier position marker.
  Widget _liveMap() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = _progress;
    final n = progress?.pointCount ?? 0;
    if (progress == null || n == 0) {
      return Container(
        color: LiquidPalette.cardTint(isDark),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.waitingForGps,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      );
    }

    final points = List<LatLng>.generate(
      n,
      (i) => LatLng(progress.lat[i], progress.lng[i]),
    );
    final current = points.last;

    return FlutterMap(
      options: MapOptions(
        initialCenter: current,
        initialZoom: 15,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.valor.deliveryflow',
        ),
        PolylineLayer(
          polylines: [
            if (points.length > 1)
              Polyline(
                points: points,
                strokeWidth: 5.5,
                color: LiquidPalette.primaryBlue,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: current,
              width: 46,
              height: 46,
              child: Container(
                decoration: BoxDecoration(
                  color: LiquidPalette.primaryBlue,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.delivery_dining_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<LatLng> _pts(List<double> lat, List<double> lng) {
    final n = lat.length < lng.length ? lat.length : lng.length;
    return List.generate(n, (i) => LatLng(lat[i], lng[i]));
  }

  /// Completed trip: outgoing leg in brand blue, return leg in sky
  /// blue, mart + customer pins in brand colors.
  Widget _routeMap() {
    final entry = widget.entry;
    final out = _pts(entry.displayOutLat, entry.displayOutLng);
    final back = _pts(entry.displayBackLat, entry.displayBackLng);
    final bounds = LatLngBounds.fromPoints([...out, ...back]);

    return FlutterMap(
      options: MapOptions(
        initialCenter: bounds.center,
        initialZoom: 14,
        initialCameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(48),
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.valor.deliveryflow',
        ),
        PolylineLayer(
          polylines: [
            if (out.length > 1)
              Polyline(
                points: out,
                strokeWidth: 5,
                color: LiquidPalette.primaryBlue,
              ),
            if (back.length > 1)
              Polyline(
                points: back,
                strokeWidth: 5,
                color: LiquidPalette.skyBlue,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            if (out.isNotEmpty)
              _pin(out.first, Icons.store_rounded,
                  LiquidPalette.skyBlue),
            if (out.isNotEmpty)
              _pin(out.last, Icons.person_pin_rounded,
                  LiquidPalette.primaryBlue),
            if (back.isNotEmpty)
              _pin(back.last, Icons.store_rounded,
                  LiquidPalette.skyBlue),
          ],
        ),
      ],
    );
  }

  Marker _pin(LatLng point, IconData icon, Color color) {
    return Marker(
      point: point,
      width: 40,
      height: 40,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 6,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
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
