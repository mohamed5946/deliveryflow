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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final db = ref.watch(databaseServiceProvider);
    final counts = db.recordCounts();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: GlassTokens.screenPadding,
        children: [
          _section(l10n.appearanceSection, text),
          GlassCard(
            child: RadioGroup<int>(
              groupValue: settings.themeMode,
              onChanged: (v) =>
                  notifier.update((s) => s..themeMode = v ?? 0),
              child: Column(
                children: [
                  for (final entry in [
                    (0, l10n.themeSystem),
                    (1, l10n.themeLight),
                    (2, l10n.themeDark),
                  ])
                    RadioListTile<int>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.$2),
                      value: entry.$1,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _section(l10n.chooseTheme, text),
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
          _section(l10n.languageSection, text),
          GlassCard(
            child: RadioGroup<String>(
              groupValue: settings.languageCode,
              onChanged: (v) =>
                  notifier.update((s) => s..languageCode = v ?? 'ar'),
              child: const Column(
                children: [
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('العربية'),
                    value: 'ar',
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('English'),
                    value: 'en',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _section(l10n.notificationsSection, text),
          GlassCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.notificationsEnabled),
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
                const Divider(height: 8),
                _timeRow(
                  context,
                  l10n.dailyReminderTime,
                  TimeOfDay(
                      hour: settings.dailyReminderHour,
                      minute: settings.dailyReminderMinute),
                  (t) => notifier.update((s) => s
                    ..dailyReminderHour = t.hour
                    ..dailyReminderMinute = t.minute),
                  enabled: settings.notificationsEnabled,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.dailyReminderEnabled),
                  value: settings.dailyReminderEnabled,
                  onChanged: settings.notificationsEnabled
                      ? (v) => notifier.update(
                          (s) => s..dailyReminderEnabled = v)
                      : null,
                ),
                const Divider(height: 8),
                _timeRow(
                  context,
                  l10n.scheduleReminderTime,
                  TimeOfDay(
                      hour: settings.scheduleReminderHour,
                      minute: settings.scheduleReminderMinute),
                  (t) => notifier.update((s) => s
                    ..scheduleReminderHour = t.hour
                    ..scheduleReminderMinute = t.minute),
                  enabled: settings.notificationsEnabled,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.scheduleReminderEnabled),
                  value: settings.scheduleReminderEnabled,
                  onChanged: settings.notificationsEnabled
                      ? (v) => notifier.update(
                          (s) => s..scheduleReminderEnabled = v)
                      : null,
                ),
                const Divider(height: 8),
                _timeRow(
                  context,
                  l10n.reportReminderTime,
                  TimeOfDay(
                      hour: settings.reportReminderHour,
                      minute: settings.reportReminderMinute),
                  (t) => notifier.update((s) => s
                    ..reportReminderHour = t.hour
                    ..reportReminderMinute = t.minute),
                  enabled: settings.notificationsEnabled,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.reportReminderEnabled),
                  value: settings.reportReminderEnabled,
                  onChanged: settings.notificationsEnabled
                      ? (v) => notifier.update(
                          (s) => s..reportReminderEnabled = v)
                      : null,
                ),
                const Divider(height: 8),
                _timeRow(
                  context,
                  l10n.followUpReminderTime,
                  TimeOfDay(
                      hour: settings.followUpReminderHour,
                      minute: settings.followUpReminderMinute),
                  (t) => notifier.update((s) => s
                    ..followUpReminderHour = t.hour
                    ..followUpReminderMinute = t.minute),
                  enabled: settings.notificationsEnabled,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.followUpReminderEnabled),
                  value: settings.followUpReminderEnabled,
                  onChanged: settings.notificationsEnabled
                      ? (v) => notifier.update(
                          (s) => s..followUpReminderEnabled = v)
                      : null,
                ),
                const Divider(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.testNotification),
                  trailing:
                      const Icon(Icons.notifications_active_rounded),
                  onTap: settings.notificationsEnabled
                      ? () async {
                          try {
                            await ref
                                .read(notificationServiceProvider)
                                .showTest(
                                  title: l10n.appTitle,
                                  body: l10n.notifDailyBody,
                                );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                      content: Text(l10n
                                          .testNotificationSent)));
                            }
                          } catch (_) {}
                        }
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _section(l10n.workPrefsSection, text),
          GlassCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.weeklyOrderGoalLabel),
                  trailing: Text(
                      settings.weeklyOrderGoal?.toString() ?? '–',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
                  onTap: () => _askNumber(
                    title: l10n.weeklyOrderGoalLabel,
                    initial:
                        settings.weeklyOrderGoal?.toString() ?? '',
                    onDone: (v) => notifier.update(
                        (s) => s..weeklyOrderGoal = v?.toInt()),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.weeklyHoursGoalLabel),
                  trailing: Text(
                      settings.weeklyWorkHoursGoal?.toString() ??
                          '–',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.defaultBreakLabel),
                  trailing: Text(
                      '${settings.defaultBreakDurationMinutes}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
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
          _section(l10n.salarySection, text),
          GlassCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.orderPriceLabel),
                  trailing: Text(
                      settings.orderPrice?.toString() ?? '–',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
                  onTap: () => _askNumber(
                    title: l10n.orderPriceLabel,
                    initial: settings.orderPrice?.toString() ?? '',
                    decimal: true,
                    onDone: (v) => notifier.update(
                        (s) => s..orderPrice = v),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.dailyFixedLabel),
                  trailing: Text(
                      settings.dailyFixedPay?.toString() ?? '–',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
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
          _section(l10n.dataSection, text),
          GlassCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.exportRecordsCsv),
                  trailing:
                      const Icon(Icons.download_rounded),
                  onTap: _exportCsv,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.backupData),
                  trailing:
                      const Icon(Icons.backup_rounded),
                  onTap: _backup,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.restoreBackup),
                  trailing:
                      const Icon(Icons.restore_rounded),
                  onTap: _restore,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.recordCounts),
                  trailing: Text(
                    '${counts['schedules']}/${counts['orderRecords']}/${counts['sessions']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.clearAllData,
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .error)),
                  trailing: Icon(Icons.delete_forever_rounded,
                      color:
                          Theme.of(context).colorScheme.error),
                  onTap: _clearAll,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _section(l10n.appSection, text),
          GlassCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.aboutApp),
                  subtitle: Text(
                      '${l10n.versionLabel}: 1.0.0+1'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.designedBy),
                  subtitle: Text(l10n.designerName),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.contactLabel),
                  subtitle: const Text('01557887719',
                      textDirection: TextDirection.ltr),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.privacyInfo),
                  subtitle: Text(l10n.privacyBody,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section(String title, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style:
              text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
    );
  }

  Widget _timeRow(
    BuildContext context,
    String label,
    TimeOfDay value,
    Future<void> Function(TimeOfDay) onPick, {
    bool enabled = true,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(value.format(context),
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700)),
      onTap: enabled
          ? () => _pickTime(initial: value, onPick: onPick)
          : null,
    );
  }
}
