// v27.35 payouts — manager payout detail for one driver and one
// week (opened by tapping a Payouts row on the Management
// dashboard).
//
// The week is the dashboard's selected week (Sunday–Saturday,
// derived from [dateKey]). The day list shows each day's total from
// its day summary; days without summaries show "No data". Days are
// marked when they carry a bonus (day-level bonus components > 0,
// and/or a bonus adjustment created that day) or a deduction (a
// deduction adjustment created that day). Adjustments map to days
// by createdAtMillis → calendar day (local timezone, same rule as
// the week chart). Each adjustment line shows its reason + amount.
//
// The net week total uses the SAME [payoutWeek] computation as the
// Payouts row, so the detail can never disagree with the row:
// base (day totals, day bonuses included) + bonus adjustments −
// deduction adjustments. Adjustments whose weekKey is this week but
// whose created day falls outside it (e.g. entered late) are listed
// separately at the bottom, so the arithmetic always reconciles.
//
// Blocked drivers never appear in the Payouts list; a direct link
// here for a blocked driver shows only the blocked state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloud/adjustment_logic.dart';
import '../../core/cloud/cloud_backend.dart';
import '../../core/cloud/cloud_providers.dart';
import '../../core/cloud/cloud_types.dart';
import '../../core/date_time/week_calendar.dart';
import '../../theme/design_system.dart';
import 'management_dashboard_logic.dart';

class ManagementPayoutScreen extends ConsumerWidget {
  const ManagementPayoutScreen({
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
      appBar: AppBar(title: const Text('Payout detail')),
      body: SingleChildScrollView(
        padding: GlassTokens.screenPadding,
        child: account == null || !account.isManager
            ? const GlassCard(
                key: ValueKey('managementPayoutDenied'),
                child: Text(
                  'Access denied: this section is for manager '
                  'accounts only.',
                ),
              )
            : account.mustChangePassword
                ? const GlassCard(
                    key: ValueKey('managementPayoutDenied'),
                    child: Text(
                      'Password change required before any '
                      'dashboard access. Open Cloud account to '
                      'change your password.',
                    ),
                  )
                : FutureBuilder<_PayoutDetail>(
                    future: _load(backend),
                    builder: (context, snap) {
                      if (snap.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (snap.hasError) {
                        return GlassCard(
                          child: Text(
                            'Could not load payout: ${snap.error}',
                          ),
                        );
                      }
                      final data = snap.data!;
                      if (data.target == null) {
                        return const GlassCard(
                          child: Text('Driver not found.'),
                        );
                      }
                      final target = data.target!;
                      if (target.blocked) {
                        return const GlassCard(
                          key: ValueKey('managementPayoutBlocked'),
                          child: Text(
                            'This account is blocked. Blocked '
                            'drivers are not part of the team and '
                            'have no payout row.',
                          ),
                        );
                      }
                      final payout = payoutWeek(
                        summaries: data.daySummaries,
                        adjustments: data.adjustments,
                        weekKey: data.weekKeys.first,
                      );
                      final scheme = Theme.of(context).colorScheme;
                      // Adjustments grouped by the calendar day they
                      // were created on (local timezone).
                      final byDay = <String, List<CloudAdjustment>>{};
                      for (final a in adjustmentsForWeek(
                        data.adjustments,
                        data.weekKeys.first,
                      )) {
                        final dayKey = managementDateKey(
                          DateTime.fromMillisecondsSinceEpoch(
                            a.createdAtMillis,
                          ),
                        );
                        (byDay[dayKey] ??= []).add(a);
                      }
                      final outsideWeek = adjustmentsForWeek(
                        data.adjustments,
                        data.weekKeys.first,
                      ).where(
                        (a) => !data.weekKeys.contains(
                          managementDateKey(
                            DateTime.fromMillisecondsSinceEpoch(
                              a.createdAtMillis,
                            ),
                          ),
                        ),
                      ).toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GlassCard(
                            key: const ValueKey('managementPayoutHeader'),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  target.displayName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Week of ${data.weekKeys.first}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Payout: ${target.payoutMethod.label}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium,
                                ),
                                if (target.payoutMethod ==
                                        CloudPayoutMethod.instapay ||
                                    target.payoutMethod ==
                                        CloudPayoutMethod.vodafoneCash) ...[
                                  if (target.payoutNumber.isNotEmpty)
                                    Text(target.payoutNumber),
                                  if (target.payoutName.isNotEmpty)
                                    Text(
                                      target.payoutName,
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
                            key: const ValueKey('managementPayoutTotal'),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Amount due',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Day totals: '
                                  '${payout.base.toStringAsFixed(0)} EGP',
                                ),
                                if (payout.bonus > 0)
                                  Text(
                                    'Bonus adjustments: '
                                    '+${payout.bonus.toStringAsFixed(0)} EGP',
                                    style: TextStyle(
                                      color: scheme.primary,
                                    ),
                                  ),
                                if (payout.deduction > 0)
                                  Text(
                                    'Deduction adjustments: '
                                    '−${payout.deduction.toStringAsFixed(0)} EGP',
                                    style: TextStyle(
                                      color: scheme.error,
                                    ),
                                  ),
                                const Divider(),
                                Text(
                                  key: const ValueKey(
                                    'managementPayoutNet',
                                  ),
                                  '${payout.net.toStringAsFixed(0)} EGP',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final dayKey in data.weekKeys) ...[
                            _PayoutDayCard(
                              dayKey: dayKey,
                              summary: _summaryForDay(
                                data.daySummaries,
                                dayKey,
                              ),
                              adjustments: byDay[dayKey] ?? const [],
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (outsideWeek.isNotEmpty) ...[
                            GlassCard(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Other adjustments for this week',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Counted in the week total, but '
                                    'created outside this week.',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 8),
                                  for (final a in outsideWeek)
                                    _AdjustmentLine(adjustment: a),
                                ],
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

  Future<_PayoutDetail> _load(CloudBackend backend) async {
    final users = await backend.listUsers();
    CloudAccount? target;
    for (final u in users) {
      if (u.uid == uid) target = u;
    }
    final parsed = WeekCalendar.parseDateKey(dateKey);
    final weekDays = WeekCalendar.weekDays(parsed);
    final weekKeys = [for (final d in weekDays) managementDateKey(d)];
    final week = await backend.listSummariesForDays(weekKeys);
    final daySummaries = week.values
        .expand((list) => list)
        .where((s) => s.uid == uid)
        .toList();
    final adjustments = await backend.listAdjustments(uid);
    return _PayoutDetail(
      target: target,
      weekKeys: weekKeys,
      daySummaries: daySummaries,
      adjustments: adjustments,
    );
  }
}

/// The day summary for [dayKey] in [summaries] (at most one per
/// driver per day), or null when the driver has no summary that day.
CloudDaySummary? _summaryForDay(
  List<CloudDaySummary> summaries,
  String dayKey,
) {
  for (final s in summaries) {
    if (s.dateKey == dayKey) return s;
  }
  return null;
}

class _PayoutDetail {
  const _PayoutDetail({
    required this.target,
    required this.weekKeys,
    required this.daySummaries,
    required this.adjustments,
  });

  final CloudAccount? target;
  final List<String> weekKeys;
  final List<CloudDaySummary> daySummaries;
  final List<CloudAdjustment> adjustments;
}

/// One day row: total (or "No data"), bonus / deduction markers,
/// and that day's adjustment lines with reasons + amounts.
class _PayoutDayCard extends StatelessWidget {
  const _PayoutDayCard({
    required this.dayKey,
    required this.summary,
    required this.adjustments,
  });

  final String dayKey;
  final CloudDaySummary? summary;
  final List<CloudAdjustment> adjustments;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dayBonus = summary == null
        ? 0.0
        : summary!.manualBonus +
            summary!.distanceBonus +
            summary!.flatBonus;
    final hasBonus = dayBonus > 0 ||
        adjustments.any((a) => a.isBonus);
    final hasDeduction = adjustments.any((a) => !a.isBonus);
    return GlassCard(
      key: ValueKey('managementPayoutDay-$dayKey'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dayKey,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (summary != null)
                Text(
                  '${summary!.salaryTotal.toStringAsFixed(0)} EGP',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                )
              else
                const Text('No data'),
            ],
          ),
          if (hasBonus || hasDeduction) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (hasBonus)
                  Text(
                    'Bonus',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (hasBonus && hasDeduction) const SizedBox(width: 12),
                if (hasDeduction)
                  Text(
                    'Deduction',
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
          for (final a in adjustments) ...[
            const SizedBox(height: 4),
            _AdjustmentLine(adjustment: a),
          ],
        ],
      ),
    );
  }
}

/// One adjustment line: reason + signed amount.
class _AdjustmentLine extends StatelessWidget {
  const _AdjustmentLine({required this.adjustment});

  final CloudAdjustment adjustment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            adjustment.reason,
            key: ValueKey(
              'managementPayoutAdjustment-${adjustment.id}',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          adjustment.isBonus
              ? '+${adjustment.amount.toStringAsFixed(0)} EGP'
              : '−${adjustment.amount.toStringAsFixed(0)} EGP',
          style: TextStyle(
            color: adjustment.isBonus ? scheme.primary : scheme.error,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
