// v27.33 — Manager day editor (manager powers).
//
// A manager opens ANY driver's day from the dashboard detail screen
// and edits ANYTHING the driver himself can edit: add/edit/delete
// the driver's orders, correct km, adjust salary components
// (order price, paid-day fixed pay, distance/manual/flat bonuses).
// Edits write through Firestore into the DRIVER's own docs and sync
// down to the driver's device on next login; the backend stamps
// manager edits with editedByManagerUid + timestamp so the driver
// can see a change came from the manager.
//
// Validation mirrors the driver's own editors: orders are a whole
// number ≥ 0, km and every money component are numbers ≥ 0.
// Passwords are never touched here — they live only in Firebase
// Auth and are never visible or editable by a manager.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/cloud/cloud_providers.dart';
import '../../core/cloud/cloud_types.dart';
import '../../theme/bin_eating_delete_button.dart';
import '../../theme/design_system.dart';

class ManagerEditDayScreen extends ConsumerStatefulWidget {
  const ManagerEditDayScreen({
    super.key,
    required this.uid,
    required this.dateKey,
  });

  final String uid;
  final String dateKey;

  @override
  ConsumerState<ManagerEditDayScreen> createState() =>
      _ManagerEditDayScreenState();
}

class _ManagerEditDayScreenState extends ConsumerState<ManagerEditDayScreen> {
  final _ordersCtrl = TextEditingController();
  final _kmCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _fixedCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  final _manualCtrl = TextEditingController();
  final _flatCtrl = TextEditingController();
  bool _loaded = false;
  String? _error;
  String? _name;

  @override
  void dispose() {
    for (final c in [
      _ordersCtrl,
      _kmCtrl,
      _priceCtrl,
      _fixedCtrl,
      _distanceCtrl,
      _manualCtrl,
      _flatCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (_loaded) return;
    final backend = ref.read(cloudBackendProvider);
    final users = await backend.listUsers();
    for (final u in users) {
      if (u.uid == widget.uid) _name = u.displayName;
    }
    final summary = await backend.fetchDaySummary(widget.uid, widget.dateKey);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _ordersCtrl.text = '${summary?.ordersCount ?? 0}';
      _kmCtrl.text = '${summary?.totalKm ?? 0}';
      _priceCtrl.text = '${summary?.orderPrice ?? 0}';
      _fixedCtrl.text = '${summary?.dailyFixedPay ?? 0}';
      _distanceCtrl.text = '${summary?.distanceBonus ?? 0}';
      _manualCtrl.text = '${summary?.manualBonus ?? 0}';
      _flatCtrl.text = '${summary?.flatBonus ?? 0}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(cloudAccountProvider).account;
    return GlassScaffold(
      appBar: AppBar(title: const Text('Edit driver day')),
      body: SingleChildScrollView(
        padding: GlassTokens.screenPadding,
        child: account == null || !account.isManager
            ? const GlassCard(
                key: ValueKey('managerEditDenied'),
                child: Text(
                  'Access denied: this section is for manager '
                  'accounts only.',
                ),
              )
            : account.mustChangePassword
                ? const GlassCard(
                    key: ValueKey('managerEditDenied'),
                    child: Text(
                      'Password change required before any '
                      'dashboard access. Open Cloud account to '
                      'change your password.',
                    ),
                  )
                : FutureBuilder<void>(
                future: _load(),
                builder: (context, snap) {
                  if (!_loaded) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassCard(
                        child: Text(
                          '${_name ?? widget.uid} — ${widget.dateKey}',
                          style:
                              Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _field('managerEditOrders', 'Orders', _ordersCtrl,
                          TextInputType.number),
                      _field('managerEditKm', 'Km', _kmCtrl,
                          const TextInputType.numberWithOptions(
                            decimal: true,
                          )),
                      _field('managerEditPrice', 'Order price (EGP)',
                          _priceCtrl,
                          const TextInputType.numberWithOptions(
                            decimal: true,
                          )),
                      _field('managerEditFixed', 'Paid-day fixed pay (EGP)',
                          _fixedCtrl,
                          const TextInputType.numberWithOptions(
                            decimal: true,
                          )),
                      _field('managerEditDistance', 'Distance bonus (EGP)',
                          _distanceCtrl,
                          const TextInputType.numberWithOptions(
                            decimal: true,
                          )),
                      _field('managerEditManual', 'Manual bonus (EGP)',
                          _manualCtrl,
                          const TextInputType.numberWithOptions(
                            decimal: true,
                          )),
                      _field('managerEditFlat', 'Flat bonus (EGP)',
                          _flatCtrl,
                          const TextInputType.numberWithOptions(
                            decimal: true,
                          )),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          key: const ValueKey('managerEditError'),
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      GlassButton(
                        key: const ValueKey('managerEditSave'),
                        label: 'Save day',
                        icon: Icons.save_rounded,
                        onPressed: _save,
                      ),
                      const SizedBox(height: 12),
                      GlassButton(
                        key: const ValueKey('managerEditDelete'),
                        label: 'Delete this day',
                        icon: Icons.delete_rounded,
                        primary: false,
                        onPressed: _confirmDelete,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This edits the driver\'s own data and syncs '
                        'to their device. The edit is stamped as a '
                        'manager edit.',
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _field(
    String key,
    String label,
    TextEditingController ctrl,
    TextInputType keyboard,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: ValueKey(key),
        controller: ctrl,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final orders = int.tryParse(_ordersCtrl.text.trim());
    final km = double.tryParse(_kmCtrl.text.trim());
    final price = double.tryParse(_priceCtrl.text.trim());
    final fixed = double.tryParse(_fixedCtrl.text.trim());
    final distance = double.tryParse(_distanceCtrl.text.trim());
    final manual = double.tryParse(_manualCtrl.text.trim());
    final flat = double.tryParse(_flatCtrl.text.trim());
    if (orders == null ||
        km == null ||
        price == null ||
        fixed == null ||
        distance == null ||
        manual == null ||
        flat == null ||
        orders < 0 ||
        km < 0 ||
        price < 0 ||
        fixed < 0 ||
        distance < 0 ||
        manual < 0 ||
        flat < 0) {
      setState(() {
        _error = 'Enter valid numbers: orders as a whole number, '
            'all values 0 or more.';
      });
      return;
    }
    setState(() => _error = null);
    final backend = ref.read(cloudBackendProvider);
    final summary = buildDaySummary(
      uid: widget.uid,
      dateKey: widget.dateKey,
      ordersCount: orders,
      totalKm: km,
      orderPrice: price,
      dailyFixedPay: fixed,
      distanceBonus: distance,
      manualBonus: manual,
      flatBonus: flat,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      await backend.saveDaySummary(summary);
      await backend.saveOrderRecord(widget.uid, widget.dateKey, {
        'dateKey': widget.dateKey,
        'completedOrders': orders,
        'totalKm': km,
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Day saved')),
      );
      context.pop();
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this day?'),
        content: const Text(
          'This removes the driver\'s summary and order record for '
          'this day. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          // Same destructive-confirmation pattern as the rest of the
          // app: the shared bin-eats-label button, not a plain button.
          BinEatingDeleteButton(
            label: 'Delete',
            onConfirmed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(cloudBackendProvider)
        .deleteUserDay(widget.uid, widget.dateKey);
    if (mounted) context.pop();
  }
}
