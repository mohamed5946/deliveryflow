import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/design_system.dart';
import '../../theme/pressable.dart';

/// Complete settings: appearance, language, notifications, work
/// preferences, data management, about.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _pickTime({
    required TimeOfDay initial,
    required Future<void> Function(TimeOfDay) onPick,
  }) async {
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t != null) await onPick(t);
  }

  Future<void> _askNumber({
    required String title,
    required String initial,
    required Future<void> Function(double?) onDone,
    bool decimal = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: decimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(l10n.ok)),
        ],
      ),
    );
    if (v == null) return;
    await onDone(v.isEmpty ? null : double.tryParse(v));
  }

  Future<void> _backup() async {
    final l10n = AppLocalizations.of(context);
    try {
      final db = ref.read(databaseServiceProvider);
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/deliveryflow_backup_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(db.backupJson());
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: 'DeliveryFlow backup',
      ));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.backupCreated)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.backupFailed)));
      }
    }
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null || picked.path == null) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.restoreBackup),
        content: Text(l10n.clearAllConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.confirm)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final content = await File(picked.path!).readAsString();
      await ref.read(databaseServiceProvider).restoreFromJson(content);
      bumpDataVersion(ref);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.backupRestored)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.backupFailed)));
      }
    }
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.clearAllConfirmTitle),
        content: Text(l10n.clearAllConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error),
              child: Text(l10n.delete)),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(databaseServiceProvider).clearAll();
    await ref.read(notificationServiceProvider).cancelAll();
    bumpDataVersion(ref);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.done)));
    }
  }

  Future<void> _exportCsv() async {
    final l10n = AppLocalizations.of(context);
    final db = ref.read(databaseServiceProvider);
    await SharePlus.instance.share(ShareParams(
      text: db.exportCsv(),
      subject: 'deliveryflow.csv',
    ));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.csvExported)));
    }
  }

  /// Enable a reminder toggle: request permission, then turn the reminder
  /// on together with the master notifications switch (reminders only fire
  /// when the master switch is on).
  Future<void> _setReminder(
    bool v, {
    required bool daily,
  }) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(settingsProvider.notifier);
    if (v) {
      try {
        final ok =
            await ref.read(notificationServiceProvider).requestPermission();
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.notificationPermissionNeeded)));
        }
      } catch (_) {}
      await notifier.update((s) {
        if (daily) {
          s.dailyReminderEnabled = true;
        } else {
          s.scheduleReminderEnabled = true;
        }
        s.notificationsEnabled = true;
        return s;
      });
    } else {
      await notifier.update((s) {
        if (daily) {
          s.dailyReminderEnabled = false;
        } else {
          s.scheduleReminderEnabled = false;
        }
        return s;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final db = ref.watch(databaseServiceProvider);
    final counts = db.recordCounts();
    final dailyTime = TimeOfDay(
        hour: settings.dailyReminderHour,
        minute: settings.dailyReminderMinute);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      // SingleChildScrollView + Column (instead of a lazy ListView) so every
      // row exists in the tree without scrolling — widget tests assert on
      // labels deep in the list.
      body: SingleChildScrollView(
        padding: GlassTokens.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // ── المظهر ────────────────────────────────────────────
          _section(l10n.appearanceSection),
          GlassCard(
            child: Column(
              children: [
                _radioRow(
                  icon: Icons.wb_sunny_rounded,
                  label: l10n.themeLight,
                  selected: settings.themeMode == 1,
                  onTap: () =>
                      notifier.update((s) => s..themeMode = 1),
                ),
                const SizedBox(height: 4),
                _radioRow(
                  icon: Icons.nightlight_rounded,
                  label: l10n.themeDark,
                  selected: settings.themeMode == 2,
                  onTap: () =>
                      notifier.update((s) => s..themeMode = 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _section(l10n.chooseTheme),
          GlassCard(
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 12,
                crossAxisSpacing: 8,
                childAspectRatio: 0.78,
              ),
              itemCount: AppThemePreset.all.length,
              itemBuilder: (ctx, i) {
                final preset = AppThemePreset.all[i];
                final selected = settings.themePreset == preset.id;
                final scheme = Theme.of(ctx).colorScheme;
                final text = Theme.of(ctx).textTheme;
                return GestureDetector(
                  onTap: () => notifier
                      .update((s) => s..themePreset = preset.id),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              preset.auroraDark[0],
                              preset.auroraDark[1],
                              preset.auroraDark[3],
                            ],
                          ),
                          border: Border.all(
                            color: selected
                                ? scheme.primary
                                : Colors.white.withValues(alpha: 0.25),
                            width: selected ? 3 : 1.5,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: scheme.primary
                                        .withValues(alpha: 0.4),
                                    blurRadius: 10,
                                  )
                                ]
                              : null,
                        ),
                        child: selected
                            ? const Icon(Icons.check_rounded,
                                color: Colors.white, size: 22)
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preset.name(settings.languageCode),
                        style: text.bodySmall?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w400,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // ── الإشعارات ─────────────────────────────────────────
          _section(l10n.notificationsSection),
          GlassCard(
            child: Column(
              children: [
                _toggleRow(
                  icon: Icons.notifications_none_rounded,
                  label: l10n.endOfDayNotif,
                  value: settings.dailyReminderEnabled,
                  onChanged: (v) => _setReminder(v, daily: true),
                ),
                const SizedBox(height: 4),
                _toggleRow(
                  icon: Icons.history_rounded,
                  label: l10n.weeklyScheduleNotif,
                  value: settings.scheduleReminderEnabled,
                  onChanged: (v) => _setReminder(v, daily: false),
                ),
                const SizedBox(height: 4),
                _timeRow2(
                  label: l10n.notifTime,
                  time: dailyTime,
                  onTap: () => _pickTime(
                    initial: dailyTime,
                    onPick: (t) => notifier.update((s) => s
                      ..dailyReminderHour = t.hour
                      ..dailyReminderMinute = t.minute),
                  ),
                ),
                const Divider(height: 20),
                _toggleRow(
                  icon: Icons.notifications_rounded,
                  label: l10n.notificationsEnabled,
                  value: settings.notificationsEnabled,
                  onChanged: (v) async {
                    if (v) {
                      try {
                        final ok = await ref
                            .read(notificationServiceProvider)
                            .requestPermission();
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(l10n
                                      .notificationPermissionNeeded)));
                        }
                      } catch (_) {}
                    }
                    await notifier.update(
                        (s) => s..notificationsEnabled = v);
                  },
                ),
                const SizedBox(height: 4),
                _timeRow2(
                  label: l10n.dailyReminderTime,
                  time: dailyTime,
                  onTap: () => _pickTime(
                    initial: dailyTime,
                    onPick: (t) => notifier.update((s) => s
                      ..dailyReminderHour = t.hour
                      ..dailyReminderMinute = t.minute),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── اللغة ────────────────────────────────────────────
          _section(l10n.languageSection),
          GlassCard(
            child: Column(
              children: [
                _radioRow(
                  icon: Icons.language_rounded,
                  label: 'العربية',
                  selected: settings.languageCode == 'ar',
                  onTap: () => notifier
                      .update((s) => s..languageCode = 'ar'),
                ),
                const SizedBox(height: 4),
                _radioRow(
                  icon: Icons.language_rounded,
                  label: 'English',
                  selected: settings.languageCode == 'en',
                  onTap: () => notifier
                      .update((s) => s..languageCode = 'en'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── تفضيلات العمل ────────────────────────────────────
          _section(l10n.workPrefsSection),
          GlassCard(
            child: Column(
              children: [
                _valueRow(
                  icon: Icons.flag_rounded,
                  label: l10n.weeklyOrderGoalLabel,
                  value: settings.weeklyOrderGoal?.toString() ?? '–',
                  onTap: () => _askNumber(
                    title: l10n.weeklyOrderGoalLabel,
                    initial:
                        settings.weeklyOrderGoal?.toString() ?? '',
                    onDone: (v) => notifier.update(
                        (s) => s..weeklyOrderGoal = v?.toInt()),
                  ),
                ),
                const SizedBox(height: 4),
                _valueRow(
                  icon: Icons.schedule_rounded,
                  label: l10n.weeklyHoursGoalLabel,
                  value:
                      settings.weeklyWorkHoursGoal?.toString() ?? '–',
                  onTap: () => _askNumber(
                    title: l10n.weeklyHoursGoalLabel,
                    initial:
                        settings.weeklyWorkHoursGoal?.toString() ??
                            '',
                    decimal: true,
                    onDone: (v) => notifier.update(
                        (s) => s..weeklyWorkHoursGoal = v),
                  ),
                ),
                const SizedBox(height: 4),
                _valueRow(
                  icon: Icons.coffee_rounded,
                  label: l10n.defaultBreakLabel,
                  value: '${settings.defaultBreakDurationMinutes}',
                  onTap: () => _askNumber(
                    title: l10n.defaultBreakLabel,
                    initial: settings.defaultBreakDurationMinutes
                        .toString(),
                    onDone: (v) => notifier.update((s) => s
                      ..defaultBreakDurationMinutes =
                          v?.toInt() ?? 30),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── الراتب ──────────────────────────────────────────
          _section(l10n.salarySection),
          GlassCard(
            child: Column(
              children: [
                _valueRow(
                  icon: Icons.payments_rounded,
                  label: l10n.orderPriceLabel,
                  value: settings.orderPrice?.toString() ?? '–',
                  onTap: () => _askNumber(
                    title: l10n.orderPriceLabel,
                    initial: settings.orderPrice?.toString() ?? '',
                    decimal: true,
                    onDone: (v) => notifier.update(
                        (s) => s..orderPrice = v),
                  ),
                ),
                const SizedBox(height: 4),
                _valueRow(
                  icon: Icons.wallet_rounded,
                  label: l10n.dailyFixedLabel,
                  value:
                      settings.dailyFixedPay?.toString() ?? '–',
                  onTap: () => _askNumber(
                    title: l10n.dailyFixedLabel,
                    initial:
                        settings.dailyFixedPay?.toString() ?? '',
                    decimal: true,
                    onDone: (v) => notifier.update(
                        (s) => s..dailyFixedPay = v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── البيانات ────────────────────────────────────────
          _section(l10n.dataSection),
          GlassCard(
            child: Column(
              children: [
                _actionRow(
                  icon: Icons.download_rounded,
                  label: l10n.exportRecordsCsv,
                  onTap: _exportCsv,
                ),
                const SizedBox(height: 4),
                _actionRow(
                  icon: Icons.backup_rounded,
                  label: l10n.backupData,
                  onTap: _backup,
                ),
                const SizedBox(height: 4),
                _actionRow(
                  icon: Icons.restore_rounded,
                  label: l10n.restoreBackup,
                  onTap: _restore,
                ),
                const SizedBox(height: 4),
                _infoRow(
                  icon: Icons.folder_copy_rounded,
                  label: l10n.recordCounts,
                  value:
                      '${counts['schedules']}/${counts['orderRecords']}/${counts['sessions']}',
                ),
                const SizedBox(height: 4),
                _actionRow(
                  icon: Icons.delete_forever_rounded,
                  label: l10n.clearAllData,
                  destructive: true,
                  onTap: _clearAll,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── التطبيق ─────────────────────────────────────────
          _section(l10n.appSection),
          GlassCard(
            child: Column(
              children: [
                _infoRow(
                  icon: Icons.info_rounded,
                  label: l10n.aboutApp,
                  value: '${l10n.versionLabel}: 1.0.0+1',
                ),
                const SizedBox(height: 4),
                _infoRow(
                  icon: Icons.brush_rounded,
                  label: l10n.designedBy,
                  value: l10n.designerName,
                ),
                const SizedBox(height: 4),
                _infoRow(
                  icon: Icons.phone_rounded,
                  label: l10n.contactLabel,
                  value: '01557887719',
                ),
                const SizedBox(height: 4),
                _aboutRow(l10n),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

  // ── Row builders (mockup menu identity) ──────────────────────

  Widget _section(String title) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style:
              text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    );
  }

  /// Mockup radio row: icon + label on the right, radio dot on the left.
  Widget _radioRow({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final text = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassTokens.radiusS),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon,
                color: LiquidPalette.primaryBlue, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            _radioDot(selected),
          ],
        ),
      ),
    );
  }

  Widget _radioDot(bool selected) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? LiquidPalette.primaryBlue
            : Colors.transparent,
        border: Border.all(
          color: selected
              ? LiquidPalette.primaryBlue
              : scheme.outline.withValues(alpha: 0.6),
          width: 2,
        ),
      ),
      child: selected
          ? const Center(
              child: SizedBox(
                width: 8,
                height: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: Colors.white),
                ),
              ),
            )
          : null,
    );
  }

  /// Mockup toggle row: icon + label on the right, switch on the left.
  Widget _toggleRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Icon(icon,
              color: LiquidPalette.primaryBlue, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(!value),
              child: Text(label,
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  /// Mockup time row: label on the right, time + chevron on the left.
  Widget _timeRow2({
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassTokens.radiusS),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color:
                      scheme.onSurface.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 4),
                Text(
                  time.format(context),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Menu row: icon + label on the right, value + chevron on the left.
  Widget _valueRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassTokens.radiusS),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon,
                color: LiquidPalette.primaryBlue, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Text(value,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurface.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }

  /// Menu action row: icon + label on the right, chevron on the left.
  Widget _actionRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final color =
        destructive ? scheme.error : LiquidPalette.primaryBlue;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassTokens.radiusS),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: destructive ? scheme.error : null)),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: destructive
                  ? scheme.error.withValues(alpha: 0.7)
                  : scheme.onSurface.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }

  /// Menu info row: icon + label on the right, static value on the left.
  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          Icon(icon,
              color: LiquidPalette.primaryBlue, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: text.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _aboutRow(AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.privacy_tip_rounded,
              color: LiquidPalette.primaryBlue, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.privacyInfo,
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(l10n.privacyBody,
                    style: text.bodySmall,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
