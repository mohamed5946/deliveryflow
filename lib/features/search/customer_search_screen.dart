import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';
import '../../theme/page_transitions.dart';
import '../../theme/pressable.dart';
import '../daily_orders/order_detail_screen.dart';

/// Customer search: find past customers by phone number.
///
/// Only orders with a saved phone number are searchable. Typing 3+
/// digits shows live suggestions of saved numbers starting with the
/// prefix; tapping one selects it and lists the customer's orders.
/// Selecting a row opens the existing [OrderDetailScreen] — the detail
/// UI is reused, not duplicated.
class CustomerSearchScreen extends ConsumerStatefulWidget {
  const CustomerSearchScreen({super.key});

  @override
  ConsumerState<CustomerSearchScreen> createState() =>
      _CustomerSearchScreenState();
}

class _CustomerSearchScreenState
    extends ConsumerState<CustomerSearchScreen> {
  static const int _minDigits = 3;

  late final TextEditingController _controller;
  String? _selectedPhone;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    if (_selectedPhone != null && text != _selectedPhone) {
      setState(() => _selectedPhone = null);
    } else {
      setState(() {});
    }
  }

  void _selectPhone(String phone) {
    _controller.text = phone;
    _controller.selection =
        TextSelection.fromPosition(TextPosition(offset: phone.length));
    setState(() => _selectedPhone = phone);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(settingsProvider.select((s) => s.languageCode));
    final loc = locale == 'ar' ? 'ar' : 'en';

    final db = ref.watch(databaseServiceProvider);
    ref.watch(dataVersionProvider);

    final query = _controller.text.trim();
    final showResults = _selectedPhone != null;
    final results = showResults
        ? db.searchOrdersByPhone(_selectedPhone!)
        : const <({String dateKey, OrderEntry entry})>[];
    final suggestions = !showResults && query.length >= _minDigits
        ? db.distinctPhonesByPrefix(query)
        : const <String>[];

    return GlassScaffold(
      appBar: AppBar(title: Text(l10n.searchCustomers)),
      body: Padding(
        padding: GlassTokens.screenPadding,
        child: Column(
          children: [
            GlassCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 4),
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (v) {
                  final q = v.trim();
                  if (q.length >= _minDigits) _selectPhone(q);
                },
                style: text.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: l10n.searchPhoneHint,
                  hintStyle: text.bodyMedium?.copyWith(
                    color:
                        scheme.onSurface.withValues(alpha: 0.45),
                  ),
                  border: InputBorder.none,
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: scheme.primary,
                  ),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(
                            Icons.clear_rounded,
                            color: scheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _selectedPhone = null);
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: showResults
                  ? _ResultsList(
                      l10n: l10n,
                      phone: _selectedPhone!,
                      results: results,
                      loc: loc,
                    )
                  : query.length < _minDigits
                      ? _EmptyHint(
                          message: l10n.typeMoreDigits,
                        )
                      : suggestions.isEmpty
                          ? _EmptyHint(
                              message: l10n.noCustomersFound,
                            )
                          : ListView.builder(
                              itemCount: suggestions.length,
                              itemBuilder: (ctx, i) {
                                final phone = suggestions[i];
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 8),
                                  child: Pressable(
                                    onTap: () => _selectPhone(phone),
                                    child: GlassCard(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding:
                                                const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: scheme.primary
                                                  .withValues(
                                                      alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      10),
                                            ),
                                            child: Icon(
                                              Icons.phone_rounded,
                                              size: 18,
                                              color: scheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              phone,
                                              style: text.bodyLarge
                                                  ?.copyWith(
                                                fontWeight:
                                                    FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            size: 18,
                                            color: scheme.onSurface
                                                .withValues(alpha: 0.4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Orders for the selected phone: header with visit count, then the
/// day-list row styling (date, km, status badge) reused from history.
class _ResultsList extends ConsumerWidget {
  final AppLocalizations l10n;
  final String phone;
  final List<({String dateKey, OrderEntry entry})> results;
  final String loc;

  const _ResultsList({
    required this.l10n,
    required this.phone,
    required this.results,
    required this.loc,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (results.isEmpty) {
      return _EmptyHint(message: l10n.noCustomersFound);
    }

    return ListView.builder(
      itemCount: results.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassCard(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A84FF)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Color(0xFF0A84FF),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          phone,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.customerVisits(results.length),
                          style: text.bodyMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final r = results[i - 1];
        final entry = r.entry;
        final day = WeekCalendar.parseDateKey(r.dateKey);
        final dateLabel =
            DateFormat.yMd(loc).format(day);
        final (statusLabel, statusColor) = switch (entry.status) {
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
            onTap: () => Navigator.of(context).push(
              SmoothPageRoute(
                builder: (_) => OrderDetailScreen(
                  dateKey: r.dateKey,
                  entryId: entry.id,
                ),
              ),
            ),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          scheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      dateLabel,
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
                              '${entry.effectiveKmTotal.toStringAsFixed(2)} ${l10n.kmUnit}',
                              style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (entry.hasManualKm) ...[
                              const SizedBox(width: 6),
                              const ManualBadge(),
                            ],
                          ],
                        ),
                        if (entry.notes.isNotEmpty)
                          Text(
                            entry.notes,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                      color:
                          statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
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
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String message;

  const _EmptyHint({required this.message});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
