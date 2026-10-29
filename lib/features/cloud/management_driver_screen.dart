// v27.33 — Management driver detail (drill-down from the dashboard).
//
// Manager-only: a driver opening this route directly gets the denied
// state, never the driver's data. Shows the driver's orders for the
// day, the week summary, and the salary breakdown — the breakdown
// components come from the summary doc itself, so the detail can
// never disagree with the dashboard total: orders × price + paid-day
// fixed pay + distance + manual + flat bonuses (the app's formula).
// Older summary docs without breakdown fields show the total only,
// with an explicit note — never invented components.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/cloud/adjustment_logic.dart';
import '../../core/cloud/cloud_backend.dart';
import '../../core/cloud/cloud_providers.dart';
import '../../core/cloud/cloud_types.dart';
import '../../core/date_time/week_calendar.dart';
import '../../theme/bin_eating_delete_button.dart';
import '../../theme/design_system.dart';
import 'block_user_flow.dart';
import 'management_dashboard_logic.dart';

class ManagementDriverScreen extends ConsumerWidget {
  const ManagementDriverScreen({
    super.key,
    required this.uid,
    required this.dateKey,
  });

  final String uid;
  final String dateKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(cloudAccountProvider).account;
    final backend = ref.watch(cloudBackendProvider);
    return GlassScaffold(
      appBar: AppBar(title: const Text('Driver detail')),
      body: SingleChildScrollView(
        padding: GlassTokens.screenPadding,
        child: account == null || !account.isManager
            ? const GlassCard(
                key: ValueKey('managementDriverDenied'),
                child: Text(
                  'Access denied: this section is for manager '
                  'accounts only.',
                ),
              )
            : account.mustChangePassword
                ? const GlassCard(
                    key: ValueKey('managementDriverDenied'),
                    child: Text(
                      'Password change required before any '
                      'dashboard access. Open Cloud account to '
                      'change your password.',
                    ),
                  )
                : FutureBuilder<_DriverDetail>(
                future: _load(backend),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                  if (snap.hasError) {
                    return GlassCard(
                      child: Text('Could not load driver: ${snap.error}'),
                    );
                  }
                  final data = snap.data!;
                  // v27.35 blacklist: a blocked driver shows only the
                  // blocked state (plus Unblock) — no day data, no
                  // edit, no role toggle, no block button. The
                  // Blacklist section is the primary place for
                  // blocked drivers; this covers a direct link here.
                  if (data.targetBlocked) {
                    final target = CloudAccount(
                      uid: data.targetUid,
                      email: data.targetEmail,
                      username: data.name,
                      role: data.targetRole,
                      phone: data.targetPhone,
                      blocked: true,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const GlassCard(
                          key: ValueKey('managementDriverBlocked'),
                          child: Text(
                            'This account is blocked. The driver '
                            'cannot sign in and is hidden from the '
                            'team. His data is kept — unblocking '
                            'restores him fully.',
                          ),
                        ),
                        const SizedBox(height: 12),
                        GlassButton(
                          key: const ValueKey('managementDriverUnblock'),
                          label: 'Unblock driver',
                          icon: Icons.lock_open_rounded,
                          primary: false,
                          onPressed: () async {
                            final ok = await confirmAndUnblockUser(
                              context: context,
                              ref: ref,
                              target: target,
                            );
                            if (ok && context.mounted) {
                              bumpManagementRefresh(ref);
                              context.pop();
                            }
                          },
                        ),
                      ],
                    );
                  }
                  final summary = data.summary;
                  final weekTotals =
                      driverWeekTotals(data.weekSummaries)[uid];
                  final weekOrders = weekOrdersPerDay(
                    data.weekSummaries,
                    data.weekKeys,
                  );
                  final weekOrderTotal =
                      weekOrders.fold<int>(0, (a, b) => a + b);
                  // Week total incl. this week's manager adjustments
                  // (same rule as the dashboard + driver weekly view).
                  final weekKey = managementDateKey(
                    WeekCalendar.weekStart(
                      WeekCalendar.parseDateKey(dateKey),
                    ),
                  );
                  final weekAdjustments =
                      adjustmentsForWeek(data.adjustments, weekKey);
                  final weekAdjustedSalary = weekTotals == null
                      ? null
                      : weeklyTotalWithAdjustments(
                          weekTotals.salary,
                          weekAdjustments,
                        );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassCard(
                        key: const ValueKey('managementDriverName'),
                        child: Row(
                          children: [
                            // Same 40px theme-tinted circle pattern.
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                data.name.isEmpty
                                    ? '?'
                                    : data.name[0].toUpperCase(),
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  // v27.35: phone + email from the
                                  // cloud profile. A missing field
                                  // renders nothing — never "null"
                                  // text (the console-created admin
                                  // has no phone).
                                  if (data.targetPhone.isNotEmpty)
                                    Text(
                                      data.targetPhone,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  if (data.targetEmail.isNotEmpty)
                                    Text(
                                      data.targetEmail,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  Text(
                                    dateKey,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (summary == null)
                              const Text('Not synced')
                            else
                              Icon(Icons.check_circle_rounded,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  size: 18),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassCard(
                        key: const ValueKey('managementDriverDay'),
                        child: summary == null
                            ? const Text(
                                'No summary for this day — this driver '
                                'has not synced yet.',
                              )
                            : Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${summary.ordersCount} orders · '
                                    '${summary.totalKm.toStringAsFixed(1)} km',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  if (data.orderRecord != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Raw order record: '
                                      '${data.orderRecord!['completedOrders'] ?? '—'} completed',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                      ),
                      const SizedBox(height: 12),
                      GlassCard(
                        key: const ValueKey('managementDriverBreakdown'),
                        child: summary == null
                            ? const Text('No salary breakdown yet.')
                            : summary.hasBreakdown
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Salary breakdown',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      _row(
                                        context,
                                        'Orders',
                                        '${summary.ordersCount} × '
                                        '${summary.orderPrice.toStringAsFixed(0)} EGP',
                                        summary.ordersCount *
                                            summary.orderPrice,
                                      ),
                                      _row(
                                        context,
                                        'Paid-day fixed pay',
                                        summary.ordersCount >= 1
                                            ? 'Paid day'
                                            : 'No orders — no fixed pay',
                                        summary.ordersCount >= 1
                                            ? summary.dailyFixedPay
                                            : 0,
                                      ),
                                      _row(
                                        context,
                                        'Distance bonus',
                                        '',
                                        summary.distanceBonus,
                                      ),
                                      _row(
                                        context,
                                        'Manual bonus',
                                        '',
                                        summary.manualBonus,
                                      ),
                                      _row(
                                        context,
                                        'Flat bonus',
                                        '',
                                        summary.flatBonus,
                                      ),
                                      const Divider(),
                                      _row(
                                        context,
                                        'Total',
                                        '',
                                        summary.salaryTotal,
                                        bold: true,
                                      ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Total: ${summary.salaryTotal.toStringAsFixed(0)} EGP',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Breakdown unavailable for this '
                                        'older summary.',
                                      ),
                                    ],
                                  ),
                      ),
                      const SizedBox(height: 12),
                      GlassCard(
                        key: const ValueKey('managementDriverWeek'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Week summary',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Team this week: $weekOrderTotal orders',
                              style:
                                  Theme.of(context).textTheme.bodySmall,
                            ),
                            if (weekTotals != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'This driver: ${weekTotals.orders} orders · '
                                '${weekTotals.km.toStringAsFixed(1)} km · '
                                '${weekTotals.salary.toStringAsFixed(0)} EGP',
                              ),
                              if (weekAdjustments.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'After manager adjustments: '
                                  '${weekAdjustedSalary!.toStringAsFixed(0)} EGP',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassButton(
                        key: const ValueKey('managementDriverEditDay'),
                        label: 'Edit this day',
                        icon: Icons.edit_rounded,
                        onPressed: () => context.push(
                          '/management/driver/edit?uid=$uid&date=$dateKey',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (data.targetUid == account.uid)
                        const GlassCard(
                          child: Text(
                            'This is your own account — you cannot '
                            'change your own role (prevents lockout).',
                          ),
                        )
                      else
                        GlassButton(
                          key: const ValueKey('managementDriverRole'),
                          label: data.targetRole == CloudRole.manager
                              ? 'Demote to driver'
                              : 'Make manager',
                          icon: Icons.supervisor_account_rounded,
                          primary: false,
                          onPressed: () async {
                            final next =
                                data.targetRole == CloudRole.manager
                                    ? CloudRole.driver
                                    : CloudRole.manager;
                            final ok = await ref
                                .read(cloudAccountProvider.notifier)
                                .changeRole(uid, next);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'Role updated'
                                        : 'Could not change role',
                                  ),
                                ),
                              );
                              if (ok) {
                                context.pushReplacement(
                                  '/management/driver?uid=$uid&date=$dateKey',
                                );
                              }
                            }
                          },
                        ),
                      const SizedBox(height: 8),
                      if (summary != null && summary.editedByManager)
                        Text(
                          'Last edited by a manager — the driver sees '
                          'this stamp on their synced data.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 12),
                      _AdjustmentsSection(uid: uid, dateKey: dateKey),
                      // v27.35 blacklist: second entry point for
                      // Block (the swipe action on the driver list
                      // is the primary one). Driver accounts only,
                      // never self, never another manager — demote
                      // first. Blocking deletes nothing.
                      if (data.targetUid != account.uid &&
                          data.targetRole == CloudRole.driver) ...[
                        const SizedBox(height: 12),
                        GlassButton(
                          key: const ValueKey('managementDriverBlock'),
                          label: 'Block driver',
                          icon: Icons.block_rounded,
                          primary: false,
                          onPressed: () async {
                            final target = CloudAccount(
                              uid: data.targetUid,
                              email: data.targetEmail,
                              username: data.name,
                              role: data.targetRole,
                              phone: data.targetPhone,
                            );
                            final ok = await confirmAndBlockUser(
                              context: context,
                              ref: ref,
                              target: target,
                            );
                            if (ok && context.mounted) {
                              bumpManagementRefresh(ref);
                              context.pop();
                            }
                          },
                        ),
                      ] else if (data.targetUid != account.uid &&
                          data.targetRole == CloudRole.manager) ...[
                        const SizedBox(height: 12),
                        const GlassCard(
                          child: Text(
                            'Demote to driver first to block this '
                            'account.',
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String note,
    double value, {
    bool bold = false,
  }) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: bold ? FontWeight.w800 : null,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          if (note.isNotEmpty) ...[
            Text(note, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 8),
          ],
          Text('${value.toStringAsFixed(0)} EGP', style: style),
        ],
      ),
    );
  }

  Future<_DriverDetail> _load(CloudBackend backend) async {
    final users = await backend.listUsers();
    String name = '';
    var targetRole = CloudRole.driver;
    var targetPhone = '';
    var targetEmail = '';
    var targetBlocked = false;
    for (final u in users) {
      if (u.uid == uid) {
        name = u.displayName;
        targetRole = u.role;
        targetPhone = u.phone;
        targetEmail = u.email;
        targetBlocked = u.blocked;
      }
    }
    final summary = await backend.fetchDaySummary(uid, dateKey);
    final parsed = WeekCalendar.parseDateKey(dateKey);
    final weekDays = WeekCalendar.weekDays(parsed);
    final weekKeys = [for (final d in weekDays) managementDateKey(d)];
    final week = await backend.listSummariesForDays(weekKeys);
    final orderRecord = await backend.fetchOrderRecord(uid, dateKey);
    final adjustments = await backend.listAdjustments(uid);
    return _DriverDetail(
      name: name,
      targetUid: uid,
      targetRole: targetRole,
      targetPhone: targetPhone,
      targetEmail: targetEmail,
      targetBlocked: targetBlocked,
      summary: summary,
      weekSummaries: week,
      weekKeys: weekKeys,
      orderRecord: orderRecord,
      adjustments: adjustments,
    );
  }
}

/// Manager-only adjustments section on the driver detail screen:
/// add bonus / add deduction (amount + MANDATORY reason) for the
/// week containing the detail's day, list the driver's past
/// adjustments, edit or delete them. Drivers never see this section
/// (the whole detail screen is manager-only); drivers see their own
/// adjustments in their weekly salary view instead.
class _AdjustmentsSection extends ConsumerStatefulWidget {
  const _AdjustmentsSection({required this.uid, required this.dateKey});

  final String uid;
  final String dateKey;

  @override
  ConsumerState<_AdjustmentsSection> createState() =>
      _AdjustmentsSectionState();
}

class _AdjustmentsSectionState extends ConsumerState<_AdjustmentsSection> {
  int _refresh = 0;

  String get _weekKey {
    final day = WeekCalendar.parseDateKey(widget.dateKey);
    return managementDateKey(WeekCalendar.weekStart(day));
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(cloudBackendProvider);
    return GlassCard(
      key: const ValueKey('managementAdjustments'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Manager adjustments',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              TextButton(
                key: const ValueKey('managementAdjustmentAdd'),
                onPressed: () => _editAdjustment(context, null),
                child: const Text('Add bonus / deduction'),
              ),
            ],
          ),
          Text(
            'Week starting $_weekKey',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<CloudAdjustment>>(
            key: ValueKey('managementAdjustmentsList-$_refresh'),
            future: backend.listAdjustments(widget.uid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Text('Could not load adjustments: ${snap.error}');
              }
              final all = snap.data ?? const <CloudAdjustment>[];
              final week = adjustmentsForWeek(all, _weekKey);
              if (week.isEmpty) {
                return const Text('No adjustments for this week.');
              }
              return Column(
                children: [
                  for (final a in week) ...[
                    Row(
                      children: [
                        Icon(
                          a.isBonus
                              ? Icons.add_circle_rounded
                              : Icons.remove_circle_rounded,
                          size: 18,
                          color: a.isBonus
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${a.isBonus ? '+' : '−'}${a.amount.toStringAsFixed(0)} EGP — '
                                '${a.isBonus ? 'Bonus' : 'Deduction'}: ${a.reason}',
                              ),
                              Text(
                                'By manager ${a.createdBy}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: ValueKey('managementAdjustmentEdit-${a.id}'),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          onPressed: () => _editAdjustment(context, a),
                        ),
                        IconButton(
                          key:
                              ValueKey('managementAdjustmentDelete-${a.id}'),
                          icon: const Icon(Icons.delete_rounded, size: 18),
                          onPressed: () => _deleteAdjustment(context, a),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editAdjustment(
    BuildContext context,
    CloudAdjustment? existing,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AdjustmentDialog(
        existing: existing,
        uid: widget.uid,
        weekKey: _weekKey,
      ),
    );
    if (saved == true && mounted) setState(() => _refresh++);
  }

  Future<void> _deleteAdjustment(
    BuildContext context,
    CloudAdjustment a,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete adjustment?'),
        content: Text(
          '${a.isBonus ? 'Bonus' : 'Deduction'} of '
          '${a.amount.toStringAsFixed(0)} EGP — ${a.reason}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          // Same destructive-confirmation pattern as the rest of the
          // app: the shared bin-eats-label button, not a plain button.
          BinEatingDeleteButton(
            key: const ValueKey('managementAdjustmentDeleteConfirm'),
            label: 'Delete',
            onConfirmed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(cloudBackendProvider)
        .deleteAdjustment(widget.uid, a.id);
    if (mounted) setState(() => _refresh++);
  }
}

class _AdjustmentDialog extends StatefulWidget {
  const _AdjustmentDialog({
    required this.existing,
    required this.uid,
    required this.weekKey,
  });

  final CloudAdjustment? existing;
  final String uid;
  final String weekKey;

  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  late CloudAdjustmentType _type;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _reasonCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _type = widget.existing?.type ?? CloudAdjustmentType.bonus;
    _amountCtrl = TextEditingController(
      text: widget.existing == null
          ? ''
          : widget.existing!.amount.toStringAsFixed(0),
    );
    _reasonCtrl = TextEditingController(
      text: widget.existing?.reason ?? '',
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Add adjustment'
          : 'Edit adjustment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Bonus'),
                  selected: _type == CloudAdjustmentType.bonus,
                  onSelected: (_) => setState(
                    () => _type = CloudAdjustmentType.bonus,
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Deduction'),
                  selected: _type == CloudAdjustmentType.deduction,
                  onSelected: (_) => setState(
                    () => _type = CloudAdjustmentType.deduction,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('managementAdjustmentAmount'),
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount (EGP)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('managementAdjustmentReason'),
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('managementAdjustmentSave'),
          onPressed: () async {
            final amount = double.tryParse(_amountCtrl.text.trim());
            final error = validateAdjustment(
              amount: amount,
              reason: _reasonCtrl.text,
            );
            if (error != null) {
              setState(() => _error = error);
              return;
            }
            // Backend is reached via the dialog's context scope: the
            // dialog is opened from a Consumer widget, so ProviderScope
            // is available above it.
            final container = ProviderScope.containerOf(context);
            try {
              await container.read(cloudBackendProvider).saveAdjustment(
                    CloudAdjustment(
                      id: widget.existing?.id ?? '',
                      uid: widget.uid,
                      type: _type,
                      amount: amount!,
                      reason: _reasonCtrl.text.trim(),
                      weekKey: widget.weekKey,
                      createdBy: widget.existing?.createdBy ?? '',
                      createdAtMillis:
                          widget.existing?.createdAtMillis ?? 0,
                    ),
                  );
            } catch (e) {
              if (context.mounted) setState(() => _error = e.toString());
              return;
            }
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DriverDetail {
  const _DriverDetail({
    required this.name,
    required this.targetUid,
    required this.targetRole,
    required this.targetPhone,
    required this.targetEmail,
    required this.targetBlocked,
    required this.summary,
    required this.weekSummaries,
    required this.weekKeys,
    required this.orderRecord,
    required this.adjustments,
  });

  final String name;
  final String targetUid;
  final CloudRole targetRole;

  /// v27.35: phone + email from the cloud profile, shown on the
  /// detail screen (empty when the profile has none — the
  /// console-created admin has no phone — never rendered as text).
  final String targetPhone;
  final String targetEmail;

  /// v27.35 blacklist: a blocked driver shows only the blocked
  /// state (plus Unblock), never the edit/role/block actions.
  final bool targetBlocked;
  final CloudDaySummary? summary;
  final Map<String, List<CloudDaySummary>> weekSummaries;
  final List<String> weekKeys;
  final Map<String, dynamic>? orderRecord;
  final List<CloudAdjustment> adjustments;
}
