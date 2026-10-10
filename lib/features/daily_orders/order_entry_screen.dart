import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';

/// Daily order tracking: big numeric input with +/- steppers, save/edit,
/// optional notes. One record per date; zero is valid; missing != zero.
class OrderEntryScreen extends ConsumerStatefulWidget {
  final String? dateKey;
  const OrderEntryScreen({super.key, this.dateKey});

  @override
  ConsumerState<OrderEntryScreen> createState() => _OrderEntryScreenState();
}

class _OrderEntryScreenState extends ConsumerState<OrderEntryScreen>
    with SingleTickerProviderStateMixin {
  late String _dateKey;
  int _count = 0;
  final _notes = TextEditingController();
  bool _loaded = false;
  bool _existed = false;
  String? _error;
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _dateKey = widget.dateKey ?? WeekCalendar.dateKey(DateTime.now());
    _load();
  }

  void _load() {
    final db = ref.read(databaseServiceProvider);
    final rec = db.orderRecord(_dateKey);
    if (rec != null) {
      _count = rec.completedOrders;
      _notes.text = rec.notes;
      _existed = true;
    }
    _loaded = true;
  }

  @override
  void dispose() {
    _notes.dispose();
    _pop.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_count < 0) {
      setState(
          () => _error = AppLocalizations.of(context).invalidOrderCount);
      return;
    }
    final db = ref.read(databaseServiceProvider);
    await db.upsertOrderRecord(
      dateKey: _dateKey,
      completedOrders: _count,
      notes: _notes.text.trim(),
    );
    if (!mounted) return;
    bumpDataVersion(ref);
    await ref.read(settingsProvider.notifier).refreshReminders();
    if (!mounted) return;
    _pop.forward(from: 0);
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              _existed ? l10n.recordUpdated : l10n.recordSaved)));
      // Return to the previous screen after saving.
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale =
        ref.watch(settingsProvider.select((s) => s.languageCode));
    final date = WeekCalendar.parseDateKey(_dateKey);
    final dateLabel =
        DateFormat.yMMMMEEEEd(locale == 'ar' ? 'ar' : 'en').format(date);
    if (!_loaded) {
      return const GlassScaffold(body: GlassLoading());
    }

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.ordersForDate(dateLabel)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: GlassTokens.screenPadding,
        children: [
          GlassCard(
            child: Column(
              children: [
                Text(l10n.howManyOrders,
                    style: text.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _stepperBtn(context, Icons.remove_rounded, () {
                      if (_count > 0) setState(() => _count--);
                    }),
                    const SizedBox(width: 20),
                    ScaleTransition(
                      scale: Tween(begin: 0.85, end: 1.0).animate(
                          CurvedAnimation(
                              parent: _pop, curve: Curves.elasticOut)),
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              scheme.primary.withValues(alpha: 0.35),
                              scheme.secondary.withValues(alpha: 0.18),
                            ],
                          ),
                          border: Border.all(
                              color: Colors.white
                                  .withValues(alpha: 0.35),
                              width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text('$_count',
                            style: text.displayMedium?.copyWith(
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 20),
                    _stepperBtn(context, Icons.add_rounded,
                        () => setState(() => _count++)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                        hintText: l10n.enterCountHint),
                    onSubmitted: (v) {
                      final n = int.tryParse(v.trim());
                      if (n != null && n >= 0) {
                        setState(() => _count = n);
                      }
                    },
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: TextStyle(color: scheme.error)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.orderNotesHint, style: text.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _notes,
                  maxLines: 3,
                  decoration:
                      InputDecoration(hintText: l10n.notesOptional),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: GlassButton(
              label: l10n.saveRecord,
              icon: Icons.check_rounded,
              onPressed: _save,
            ),
          ),
          if (_existed) ...[
            const SizedBox(height: 8),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 4),
                  Text(l10n.confirmed,
                      style: text.bodySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _stepperBtn(
      BuildContext context, IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [
              scheme.primary.withValues(alpha: 0.3),
              scheme.primary.withValues(alpha: 0.12),
            ]),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: scheme.primary),
        ),
      ),
    );
  }
}
