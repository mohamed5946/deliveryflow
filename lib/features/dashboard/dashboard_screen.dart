import 'dart:io';

import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/models.dart';
import '../../core/date_time/week_calendar.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';
import '../../theme/page_transitions.dart';
import '../../theme/pressable.dart';
import '../daily_orders/order_detail_screen.dart';
import '../history/day_orders_screen.dart';

/// Home dashboard mirroring the approved Arabic mockup:
/// greeting header, today chips, stat cards, week-progress ring,
/// mini week strip, and a week-details CTA.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _saturdayPromptShown = false;
  late final DateTime _today = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final reportAsync = ref.watch(weeklyReportProvider(_today));

    final now = DateTime.now();
    final todayKey = WeekCalendar.dateKey(_today);
    final db = ref.watch(databaseServiceProvider);
    final todayOrder = db.orderRecord(todayKey);
    final todayMinutes = db.recordedMinutesForDate(todayKey);
    final completedToday = todayOrder?.completedOrders ?? 0;

    // Mockup greeting: fixed "مرحباً" + profile name.
    final greeting = l10n.greetingHello;
    final name =
        settings.displayName.isEmpty ? 'محمد' : settings.displayName;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async => bumpDataVersion(ref),
        color: LiquidPalette.primaryBlue,
        child: reportAsync.when(
          loading: () => const GlassLoading(),
          error: (e, _) => Center(child: Text('$e')),
          data: (report) {
            final hasAnyData = report.recordedDaysCount > 0 ||
                db.scheduleForWeek(_today) != null;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _saturdayPrompt(context, ref, l10n),
                  // Greeting header: text + avatar + bell
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(greeting,
                                style: text.bodyMedium?.copyWith(
                                    color: text.bodyMedium?.color
                                        ?.withValues(alpha: 0.65))),
                            Text(
                              name,
                              style: text.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800, height: 1.2),
                            ),
                          ],
                        ),
                      ),
                      Pressable(
                        scaleOnly: true,
                        onTap: () => context.go('/profile'),
                        child: _avatarContent(context, settings, name),
                      ),
                      const SizedBox(width: 10),
                      Pressable(
                        scaleOnly: true,
                        onTap: () => _showTodayDialog(
                            context, l10n, completedToday,
                            todayMinutes, todayOrder),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).brightness ==
                                    Brightness.dark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.white.withValues(alpha: 0.7),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          child: const Icon(
                            Icons.notifications_outlined,
                            color: LiquidPalette.primaryBlue,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (!hasAnyData)
                    EmptyState(
                      icon: Icons.delivery_dining_rounded,
                      title: l10n.emptyStateTitle,
                      body: l10n.emptyStateBody,
                      actionLabel: l10n.emptyStateAction,
                      onAction: () =>
                          context.push('/orders?date=$todayKey'),
                    )
                  else ...[
                    // Today chips row
                    Row(
                      children: [
                        Expanded(
                          child: _todayChip(
                            context,
                            DateFormat('EEEE', settings.languageCode == 'ar' ? 'ar' : 'en').format(now),
                            DateFormat('d MMMM', settings.languageCode == 'ar' ? 'ar' : 'en').format(now),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _completedChip(
                              context, l10n, completedToday, todayKey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Stat cards: total orders / work hours
                    Row(
                      children: [
                        Expanded(
                          child: _statCard(
                            context,
                            l10n.totalOrders,
                            '${report.totalOrders}',
                            Icons.shopping_bag_rounded,
                            onTap: () => context.go('/history'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statCard(
                            context,
                            l10n.weekHours,
                            WeekCalendar.formatHoursMinutes(
                                (report.totalRecordedHours * 60).round()),
                            Icons.schedule_rounded,
                            onTap: () =>
                                context.push('/hours?date=$todayKey'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Week progress ring
                    if (settings.weeklyOrderGoal != null)
                      _weekProgressCard(context, l10n, report,
                          settings.weeklyOrderGoal!.toDouble()),
                    if (settings.weeklyOrderGoal != null)
                      const SizedBox(height: 12),
                    // Mini week strip
                    SectionHeader(title: l10n.scheduleTitle),
                    GlassCard(
                      child: WeekDayStrip(
                        weekStart: WeekCalendar.weekStart(_today),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Quick actions: add order + week details
                    SectionHeader(title: l10n.quickActions),
                    Row(
                      children: [
                        Expanded(
                          child: GlassButton(
                            label: l10n.addOrder,
                            icon: Icons.add_rounded,
                            onPressed: _addOrderNow,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GlassButton(
                            label: l10n.viewWeekDetails,
                            icon: Icons.arrow_forward_rounded,
                            onPressed: () => context.go('/reports'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _todayChip(BuildContext context, String weekday, String date) {
    final text = Theme.of(context).textTheme;
    return GlassCard(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('اليوم',
              style: text.bodySmall?.copyWith(
                  color: text.bodySmall?.color
                      ?.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('$weekday $date',
              style: text.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _completedChip(BuildContext context, AppLocalizations l10n,
      int completed, String dateKey) {
    final text = Theme.of(context).textTheme;
    // Tappable: opens today's orders list (v9 DayOrdersScreen).
    return Pressable(
      onTap: () => Navigator.of(context).push(
        SmoothPageRoute(builder: (_) => DayOrdersScreen(dateKey: dateKey)),
      ),
      child: GlassCard(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: LiquidPalette.primaryBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.inventory_2_rounded,
                color: LiquidPalette.primaryBlue, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$completed',
                    style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: LiquidPalette.primaryBlue,
                        height: 1.0)),
                Text(l10n.completedOrdersLabel,
                    style: text.bodySmall?.copyWith(
                        color: text.bodySmall?.color
                            ?.withValues(alpha: 0.65))),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _statCard(BuildContext context, String label, String value,
      IconData icon, {VoidCallback? onTap}) {
    final text = Theme.of(context).textTheme;
    final card = GlassCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LiquidPalette.brandGradientLg,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: LiquidPalette.primaryBlue
                      .withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800, height: 1.0),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(label,
                    style: text.bodySmall?.copyWith(
                        color: text.bodySmall?.color
                            ?.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
    // Tappable cards use the Pressable dip feedback.
    if (onTap == null) return card;
    return Pressable(onTap: onTap, child: card);
  }

  /// v5.1 instant-create flow: creates a pending order immediately and
  /// opens its detail screen so GPS tracking can start.
  Future<void> _addOrderNow() async {
    final todayKey = WeekCalendar.dateKey(_today);
    final db = ref.read(databaseServiceProvider);
    final entry = await db.addOrderEntry(
      dateKey: todayKey,
      timestampMillis: DateTime.now().millisecondsSinceEpoch,
    );
    if (!mounted) return;
    bumpDataVersion(ref);
    await Navigator.of(context).push(
      SmoothPageRoute(
        builder: (_) => OrderDetailScreen(
          dateKey: todayKey,
          entryId: entry.id,
        ),
      ),
    );
  }

  Widget _weekProgressCard(BuildContext context, AppLocalizations l10n,
      WeeklyReport report, double goal) {
    final text = Theme.of(context).textTheme;
    final progress =
        goal <= 0 ? 0.0 : (report.totalOrders / goal).clamp(0.0, 1.0);
    return GlassCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.weekProgress,
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  '${report.totalOrders} / ${goal.toStringAsFixed(goal % 1 == 0 ? 0 : 1)}',
                  style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: LiquidPalette.primaryBlue),
                ),
              ],
            ),
          ),
          ProgressRing(
            progress: progress,
            size: 92,
            strokeWidth: 10,
            centerTop: '${(progress * 100).round()}%',
            centerBottom: '',
          ),
        ],
      ),
    );
  }

  Widget _avatarContent(
      BuildContext context, UserSettings settings, String name) {
    final photoPath = settings.photoPath;
    final photoFile =
        photoPath.isNotEmpty ? File(photoPath) : null;
    final hasPhoto = photoFile != null && photoFile.existsSync();
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasPhoto ? null : LiquidPalette.brandGradientLg,
        image: hasPhoto
            ? DecorationImage(image: FileImage(photoFile), fit: BoxFit.cover)
            : null,
        boxShadow: [
          BoxShadow(
            color:
                LiquidPalette.primaryBlue.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: hasPhoto
          ? null
          : Text(
              name.isEmpty ? 'م' : name.characters.first,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 20),
            ),
    );
  }

  void _showTodayDialog(BuildContext context, AppLocalizations l10n,
      int completed, int minutes, DailyOrderRecord? todayOrder) {
    final km = todayOrder == null
        ? '–'
        : '${WeekCalendar.formatKm(todayOrder.totalKm)} ${l10n.kmUnit}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.daySummary),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.completedOrdersChip(completed)),
            const SizedBox(height: 6),
            Text(
                '${l10n.weekHours}: ${WeekCalendar.formatHoursMinutes(minutes)}'),
            const SizedBox(height: 6),
            Text('${l10n.totalDistances}: $km'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.close)),
        ],
      ),
    );
  }

  Widget _saturdayPrompt(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    if (_saturdayPromptShown) return const SizedBox.shrink();
    final now = DateTime.now();
    if (now.weekday != DateTime.saturday) return const SizedBox.shrink();
    final db = ref.read(databaseServiceProvider);
    final nextStart = WeekCalendar.nextWeekStart(now);
    if (db.hasScheduleForWeek(nextStart)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.saturdayPromptTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(l10n.saturdayPromptBody),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: l10n.createSchedule,
                    icon: Icons.calendar_month_rounded,
                    onPressed: () {
                      setState(() => _saturdayPromptShown = true);
                      context.go('/schedule');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () =>
                      setState(() => _saturdayPromptShown = true),
                  child: Text(l10n.remindMeLater),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
