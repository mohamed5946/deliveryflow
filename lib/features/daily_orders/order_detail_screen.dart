import 'dart:async';

import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:latlong2/latlong.dart';

import '../../core/database/models.dart';
import '../../core/logging/app_log_service.dart';
import '../../core/money_format.dart';
import '../../core/providers.dart';
import '../../core/tracking/delivery_tracking_service.dart';
import '../../theme/design_system.dart';
import '../../theme/top_snack_bar.dart';
import '../../theme/page_transitions.dart';
import '../../theme/pressable.dart';
import '../navigation/navigation_screen.dart';
import 'phone_sheet.dart';

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

/// v27.9: the `updateOrderEntry` km arguments for ONE leg after an
/// edit-sheet save, resolved from the field's raw text against the
/// leg's EFFECTIVE (currently displayed) distance.
///
/// The sheet's km semantics: an untouched field — left exactly as
/// prefilled, or emptied — keeps the app's calculated distance
/// ([km] and [gpsKm] both null → `updateOrderEntry` skips the leg
/// entirely, GPS value and all). A deliberately changed value makes
/// THAT leg manual only ([km] = new value, [gpsKm] = 0). A non-empty
/// unparseable or negative value is [invalid] and blocks the save
/// with the sheet's `invalidKm` error.
typedef LegKmEdit = ({bool invalid, double? km, double? gpsKm});

LegKmEdit resolveLegKmEdit(String raw, double effectiveKm) {
  final t = raw.trim().replaceAll(',', '.');
  if (t.isEmpty) return (invalid: false, km: null, gpsKm: null);
  final v = double.tryParse(t);
  if (v == null || v < 0) return (invalid: true, km: null, gpsKm: null);
  if (v == effectiveKm) return (invalid: false, km: null, gpsKm: null);
  return (invalid: false, km: v, gpsKm: 0.0);
}

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
    // v27.8: apply any legs the background isolate auto-confirmed
    // while the app was away (frozen in the progress file).
    final applied = await svc.processAutoArrivals(
      dateKey: widget.dateKey,
      entryId: widget.entryId,
    );
    if (!mounted) return;
    if (applied) {
      bumpDataVersion(ref);
      _load();
      return;
    }
    if (recovered) return;
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

  /// Edit a COMPLETED order's notes, phone and km. Edited km is stored
  /// as manual: gpsKmOut/gpsKmBack are zeroed so the "يدوي" badge shows
  /// (isManualOut = gpsKmOut == 0 && kmOut > 0) and the edited numbers
  /// actually take effect (effectiveKm prefers GPS when present).
  /// Confirm dialog before saving; all aggregates recompute from the
  /// remaining records via bumpDataVersion.
  Future<void> _showEditOrderSheet(
      BuildContext context, OrderEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final notesCtrl = TextEditingController(text: entry.notes);
    final phoneCtrl = TextEditingController(text: entry.phone);
    // v27.9: prefill with the EFFECTIVE distances (the ones the user
    // sees on this screen) — NOT the manual km fields, which stay 0
    // whenever the app measured the trip itself. The old prefill made
    // the sheet show 0.0 for GPS-measured legs and forced retyping
    // numbers the app already knew (see resolveLegKmEdit).
    final kmOutCtrl =
        TextEditingController(text: entry.effectiveKmOut.toString());
    final kmBackCtrl =
        TextEditingController(text: entry.effectiveKmBack.toString());
    // v27.6: the manual bonus is editable here too — the same field
    // the breakdown-card row edits, so all order edits live in one
    // sheet. Prefilled like that editor (whole amounts without the
    // trailing .0); empty means no bonus.
    final bonusCtrl = TextEditingController(
      text: entry.manualBonusEgp > 0
          ? (entry.manualBonusEgp.truncateToDouble() == entry.manualBonusEgp
              ? entry.manualBonusEgp.toInt().toString()
              : entry.manualBonusEgp.toString())
          : '',
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var error = '';
        var bonusError = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // Empty clears the bonus; unparseable or negative is
            // rejected with the sheet's error pattern.
            double? parseBonus(String raw) {
              final t = raw.trim().replaceAll(',', '.');
              if (t.isEmpty) return 0;
              final v = double.tryParse(t);
              return (v == null || v < 0) ? null : v;
            }

            Future<void> trySave() async {
              // v27.9: per-leg resolution — an emptied or unchanged
              // km field is VALID and means "keep the calculated
              // distance"; only a non-empty garbage/negative value
              // errors.
              final outEdit =
                  resolveLegKmEdit(kmOutCtrl.text, entry.effectiveKmOut);
              final backEdit =
                  resolveLegKmEdit(kmBackCtrl.text, entry.effectiveKmBack);
              if (outEdit.invalid || backEdit.invalid) {
                setSheetState(() => error = l10n.invalidKm);
                return;
              }
              if (parseBonus(bonusCtrl.text) == null) {
                setSheetState(() => bonusError = l10n.invalidAmount);
                return;
              }
              final confirmed = await showDialog<bool>(
                context: ctx,
                builder: (dctx) => AlertDialog(
                  title: Text(l10n.editOrder),
                  content: Text(l10n.confirm),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.of(dctx).pop(false),
                      child: Text(l10n.cancel),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(dctx).pop(true),
                      child: Text(l10n.save),
                    ),
                  ],
                ),
              );
              if (confirmed == true && ctx.mounted) {
                Navigator.of(ctx).pop(true);
              }
            }

            return Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom:
                    MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.onSurface
                              .withValues(alpha: 0.2),
                          borderRadius:
                              BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.editOrder,
                      style: Theme.of(ctx)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: kmOutCtrl,
                            keyboardType: const TextInputType
                                .numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText:
                                  '${l10n.kmOutLabel} (${l10n.kmUnit})',
                              errorText:
                                  error.isEmpty ? null : error,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: kmBackCtrl,
                            keyboardType: const TextInputType
                                .numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText:
                                  '${l10n.kmBackLabel} (${l10n.kmUnit})',
                              errorText:
                                  error.isEmpty ? null : error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bonusCtrl,
                      keyboardType: const TextInputType
                          .numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: l10n.extraBonusLabel,
                        prefixIcon:
                            const Icon(Icons.card_giftcard_rounded),
                        suffixText: l10n.egpUnit,
                        errorText:
                            bonusError.isEmpty ? null : bonusError,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: l10n.phoneNumber,
                        prefixIcon:
                            const Icon(Icons.call_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: InputDecoration(
                        labelText: l10n.notesOptional,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(ctx).pop(false),
                            child: Text(l10n.cancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: trySave,
                            child: Text(l10n.save),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // v27.9: resolve each leg independently against its effective
    // distance (the sheet already validated these exact texts in
    // trySave; resolving again here keeps one source of truth).
    final outEdit = resolveLegKmEdit(kmOutCtrl.text, entry.effectiveKmOut);
    final backEdit = resolveLegKmEdit(kmBackCtrl.text, entry.effectiveKmBack);
    final newBonusText = bonusCtrl.text.trim().replaceAll(',', '.');
    final newBonus =
        newBonusText.isEmpty ? 0.0 : double.tryParse(newBonusText);
    final newNotes = notesCtrl.text.trim();
    final newPhone = phoneCtrl.text.trim();
    notesCtrl.dispose();
    phoneCtrl.dispose();
    kmOutCtrl.dispose();
    kmBackCtrl.dispose();
    bonusCtrl.dispose();
    if (saved != true ||
        outEdit.invalid ||
        backEdit.invalid ||
        newBonus == null ||
        newBonus < 0 ||
        !mounted) {
      return;
    }
    final db = ref.read(databaseServiceProvider);
    // Per leg: unchanged/emptied passes null for both km and gpsKm, so
    // the stored value (GPS included) is preserved byte-for-byte; a
    // changed leg passes its new km with gpsKm zeroed — that leg alone
    // becomes manual (يدوي badge) and takes effect.
    await db.updateOrderEntry(
      dateKey: widget.dateKey,
      entryId: widget.entryId,
      kmOut: outEdit.km,
      kmBack: backEdit.km,
      gpsKmOut: outEdit.gpsKm,
      gpsKmBack: backEdit.gpsKm,
      notes: newNotes,
      phone: newPhone,
      manualBonusEgp: newBonus,
    );
    if (newBonus != entry.manualBonusEgp) {
      ref.read(appLogServiceProvider).info(
            AppLogCategory.orders,
            'Manual bonus for order ${entry.id} (${widget.dateKey}) set to '
            '$newBonus EGP',
          );
    }
    bumpDataVersion(ref);
    _load();
    if (context.mounted) {
      showTopSnackBar(
          context, AppLocalizations.of(context).orderUpdated);
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
      // v27.8: a manual arrival supersedes any pending auto-confirm
      // prompt for this order.
      await ref.read(notificationServiceProvider).cancelArrivalPrompts();
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
      await ref.read(notificationServiceProvider).cancelArrivalPrompts();
      bumpDataVersion(ref);
      _load();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showTopSnackBar(context, l10n.orderCompleted);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Customer location for the "توجيه" (Navigate) button: last point of
  /// the recorded OUTGOING trail, falling back to the snapped road
  /// geometry end. Null when no trail was recorded (e.g. orders from
  /// before tracking) — the button is hidden then.
  LatLng? _customerLocation(OrderEntry entry) {
    if (entry.routeOutLat.isNotEmpty && entry.routeOutLng.isNotEmpty) {
      return LatLng(entry.routeOutLat.last, entry.routeOutLng.last);
    }
    if (entry.roadOutLat.isNotEmpty && entry.roadOutLng.isNotEmpty) {
      return LatLng(entry.roadOutLat.last, entry.roadOutLng.last);
    }
    return null;
  }

  /// Opens the in-app navigation screen ("التوصيل الآن") with live
  /// position, camera follow, and the OSRM driving route to [loc].
  /// Mohamed explicitly wants navigation INSIDE the app, not Google Maps.
  void _openNavigation(BuildContext context, LatLng loc, OrderEntry entry) {
    final l10n = AppLocalizations.of(context);
    final db = ref.read(databaseServiceProvider);
    final shortId = entry.id.length > 6
        ? entry.id.substring(entry.id.length - 6)
        : entry.id;
    final String statusLine;
    if (entry.isToCustomer) {
      statusLine = l10n.onWayToCustomer;
    } else if (entry.isToMart) {
      statusLine = l10n.onWayToMart;
    } else if (entry.isCompleted) {
      statusLine = l10n.statusCompleted;
    } else {
      statusLine = l10n.statusPending;
    }
    Navigator.of(context).push(
      SmoothPageRoute(
        builder: (_) => NavigationScreen(
          dateKey: widget.dateKey,
          entryId: entry.id,
          shortOrderId: shortId,
          destination: loc,
          statusLine: statusLine,
          address: entry.notes,
          phone: entry.phone,
          // v21: blended ETA — 50% his own measured riding speed.
          personalSpeedKmh: db.personalAvgSpeedKmh(),
        ),
      ),
    );
  }

  Widget _navigateButton(
      BuildContext context, LatLng loc, OrderEntry entry) {
    return Pressable(
      onTap: () => _openNavigation(context, loc, entry),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: LiquidPalette.primaryBlue.withValues(alpha: 0.12),
          border: Border.all(
            color: LiquidPalette.primaryBlue.withValues(alpha: 0.35),
          ),
        ),
        child: const Icon(Icons.navigation_rounded,
            color: LiquidPalette.primaryBlue, size: 20),
      ),
    );
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
      appBar: AppBar(
        title: Text(l10n.orderDetails),
        actions: [
          // Edit a completed order's notes / phone / km. Edited km is
          // saved as manual (يدوي badge) since it's no longer pure GPS.
          // v27.6 BUG FIX: this Pressable must NOT be scaleOnly — with
          // scaleOnly:true the onTap is never invoked (animation-only
          // mode meant for nesting inside another handler), which left
          // this button visibly pressable but dead. There is no outer
          // handler here; Pressable owns the tap.
          if (entry.isCompleted)
            Pressable(
              onTap: () => _showEditOrderSheet(context, entry),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.edit_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
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

    // Customer location for the "توجيه" button (null = hide it).
    final customerLoc = _customerLocation(entry);

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
                  child: Pressable(
                    onTap: () =>
                        showCustomerPhoneSheet(context, entry.phone),
                    child: Text(entry.phone,
                        textDirection: TextDirection.ltr,
                        style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Pressable(
                  onTap: () =>
                      showCustomerPhoneSheet(context, entry.phone),
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
                if (customerLoc != null) ...[
                  const SizedBox(width: 8),
                  _navigateButton(context, customerLoc, entry),
                ],
              ],
            ),
          ],
          // Navigate button on its own row when there's no phone
          // number but a recorded customer location exists.
          if (entry.phone.isEmpty && customerLoc != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.navigation_outlined,
                    size: 17, color: LiquidPalette.primaryBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(l10n.navigate,
                      style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: LiquidPalette.primaryBlue)),
                ),
                const SizedBox(width: 8),
                _navigateButton(context, customerLoc, entry),
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
    final settings = ref.watch(settingsProvider);
    final locale = settings.languageCode;
    final timeFmt =
        DateFormat.Hm(locale == 'ar' ? 'ar' : 'en');

    String fmtTime(int? millis) => millis == null
        ? '—'
        : timeFmt.format(
            DateTime.fromMillisecondsSinceEpoch(millis));

    final totalSec =
        entry.outgoingDurationSec + entry.returnDurationSec;
    final totalKm = entry.effectiveKmTotal;
    // v27.16 distance bonus for this order: resolved against the
    // tiers active on the ORDER'S OWN date and the effective flag
    // for that date (period coverage AND the week's override) —
    // derived, exactly as the weekly report computes it, so the
    // detail view can never disagree with the salary totals.
    final distancePeriod = settings.distancePeriodForDate(entry.dateKey);
    final distanceBonus = distanceBonusFor(
      totalKm,
      distancePeriod?.tiers ?? const [],
      enabled: settings.distanceBonusEnabledForDate(entry.dateKey),
    );

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
          // v27.5: the order's distance bonus, when it earns one.
          if (entry.isCompleted && distanceBonus > 0)
            _row(
                context,
                l10n.distanceBonusLabel,
                '+${formatMoney(distanceBonus)} ${l10n.egpUnit}',
                Icons.toll_rounded,
                Colors.teal,
                bold: true),
          // v27.5: manual per-order bonus — always shown so it can be
          // added to any order; tap to set or clear (0 clears).
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _editManualBonus(entry),
            child: _row(
                context,
                l10n.extraBonusLabel,
                entry.manualBonusEgp > 0
                    ? '+${formatMoney(entry.manualBonusEgp)} ${l10n.egpUnit}'
                    : l10n.extraBonusNone,
                Icons.card_giftcard_rounded,
                Colors.green,
                bold: entry.manualBonusEgp > 0),
          ),
        ],
      ),
    );
  }

  /// v27.5: sets/clears the manual bonus on this order. An empty
  /// field or 0 clears it. The change is logged (orders category) and
  /// every earnings surface re-derives from the entry, so the day,
  /// week and PDF totals follow immediately.
  Future<void> _editManualBonus(OrderEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: entry.manualBonusEgp > 0
          ? (entry.manualBonusEgp.truncateToDouble() == entry.manualBonusEgp
              ? entry.manualBonusEgp.toInt().toString()
              : entry.manualBonusEgp.toString())
          : '',
    );
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) {
        var error = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void trySubmit() {
              final raw =
                  controller.text.trim().replaceAll(',', '.');
              if (raw.isEmpty) {
                Navigator.of(ctx).pop(0.0);
                return;
              }
              final value = double.tryParse(raw);
              if (value == null || value < 0) {
                setDialogState(() => error = l10n.invalidAmount);
                return;
              }
              Navigator.of(ctx).pop(value);
            }

            return AlertDialog(
              title: Text(l10n.extraBonusLabel),
              content: TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.egpUnit,
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
    if (amount == null || !mounted) return;
    await ref.read(databaseServiceProvider).updateOrderEntry(
          dateKey: widget.dateKey,
          entryId: entry.id,
          manualBonusEgp: amount,
        );
    ref.read(appLogServiceProvider).info(
          AppLogCategory.orders,
          'Manual bonus for order ${entry.id} (${widget.dateKey}) set to '
          '$amount EGP',
        );
    bumpDataVersion(ref);
    if (mounted) _load();
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
      // v21: waiting for the first GPS breadcrumb is a pure event
      // wait — there are no stages to measure, so we show an honest
      // status indicator instead of a fake progress bar.
      return Container(
        color: LiquidPalette.cardTint(isDark),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.satellite_alt_rounded,
                size: 34,
                color: LiquidPalette.primaryBlue,
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
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
