import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/database/models.dart';
import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/design_system.dart';
import '../../theme/pressable.dart';

/// Profile / account hub: the single settings control center.
/// Replaces the standalone settings page — the bottom-nav "حسابي" tab
/// and the dashboard avatar both land here.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _setupNameCtrl;
  final _nameFocus = FocusNode();
  Timer? _nameDebounce;
  final _picker = ImagePicker();
  bool _pickingPhoto = false;

  /// v21: real staged photo-save progress — picked → copied → saved.
  /// Advances only on real stages, never by timer.
  double _photoProgress = 0;

  @override
  void initState() {
    super.initState();
    final name = ref.read(settingsProvider).displayName;
    _nameCtrl = TextEditingController(text: name);
    _setupNameCtrl = TextEditingController();
    _nameFocus.addListener(() {
      // When the field loses focus, flush any pending debounced save.
      if (!_nameFocus.hasFocus) _flushNameSave();
    });
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _nameCtrl.dispose();
    _setupNameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _onNameChanged(String _) {
    _nameDebounce?.cancel();
    _nameDebounce = Timer(const Duration(milliseconds: 700), _flushNameSave);
  }

  Future<void> _flushNameSave() async {
    _nameDebounce?.cancel();
    final trimmed = _nameCtrl.text.trim();
    final current = ref.read(settingsProvider).displayName;
    if (trimmed == current) return;
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s..displayName = trimmed);
  }

  /// Pick a photo from the gallery, copy it into the app documents dir as
  /// `profile_photo.jpg` (deleting the previous one), and persist the path.
  Future<void> _pickPhoto() async {
    if (_pickingPhoto) return;
    setState(() {
      _pickingPhoto = true;
      _photoProgress = 0;
    });
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        imageQuality: 85,
      );
      if (x == null) return;
      // v21 stage 1/3: image picked from the gallery.
      if (mounted) setState(() => _photoProgress = 1 / 3);
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/profile_photo.jpg');
      final settings = ref.read(settingsProvider);
      // Delete the previous saved photo if it lived somewhere else.
      if (settings.photoPath.isNotEmpty && settings.photoPath != dest.path) {
        try {
          await File(settings.photoPath).delete();
        } catch (_) {}
      }
      await File(x.path).copy(dest.path);
      // v21 stage 2/3: file copied into app storage.
      if (mounted) setState(() => _photoProgress = 2 / 3);
      await ref
          .read(settingsProvider.notifier)
          .update((s) => s..photoPath = dest.path);
      // v21 stage 3/3: settings persisted — exactly 1.0 when done.
      if (mounted) setState(() => _photoProgress = 1);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).done)),
        );
      }
    } catch (_) {
      // Gallery cancelled / unavailable — stay silent, nothing to persist.
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

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
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
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

  // ── Bottom sheets ──────────────────────────────────────────

  Future<void> _showSheet(Widget body) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SheetShell(child: body),
    );
  }

  void _showNotificationsSheet(UserSettings settings) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(settingsProvider.notifier);
    final dailyTime = TimeOfDay(
        hour: settings.dailyReminderHour, minute: settings.dailyReminderMinute);
    _showSheet(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetTitle(l10n.notificationsSection),
          const SizedBox(height: 12),
          ..._notificationRows(
            l10n: l10n,
            settings: settings,
            notifier: notifier,
            dailyTime: dailyTime,
          ),
        ],
      ),
    );
  }

  void _showHelpSheet() {
    final l10n = AppLocalizations.of(context);
    _showSheet(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetTitle(l10n.helpSupport),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 12),
                GlassButton(
                  label: l10n.callUs,
                  icon: Icons.call_rounded,
                  onPressed: () =>
                      launchUrl(Uri.parse('tel:01557887719')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────

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

    // Keep the header name field in sync with the stored name when it
    // changes elsewhere (e.g. the first-run setup card below).
    if (!_nameFocus.hasFocus && _nameCtrl.text != settings.displayName) {
      _nameCtrl.text = settings.displayName;
    }

    return GlassScaffold(
      // SafeArea for breathing space below the status bar on pushed
      // routes; on the tab shell it is harmless.
      body: SafeArea(
        top: true,
        bottom: false,
        child: SingleChildScrollView(
          padding: GlassTokens.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── أول مرة: إعداد الحساب ───────────────────────
              if (settings.displayName.isEmpty) ...[
                _setupCard(l10n, settings),
                const SizedBox(height: 12),
              ],
              // ── بطاقة الهوية ───────────────────────────────
              _identityCard(l10n, settings),
              const SizedBox(height: 12),
              // ── روابط سريعة ────────────────────────────────
              _section(l10n.appSection),
              GlassCard(
                child: Column(
                  children: [
                    _menuRow(
                      icon: Icons.bar_chart_rounded,
                      label: l10n.reportsMenu,
                      onTap: () => context.go('/reports'),
                    ),
                    const SizedBox(height: 4),
                    _menuRow(
                      icon: Icons.notifications_none_rounded,
                      label: l10n.notificationsSection,
                      onTap: () => _showNotificationsSheet(settings),
                    ),
                    const SizedBox(height: 4),
                    _menuRow(
                      icon: Icons.map_rounded,
                      label: l10n.offlineMaps,
                      onTap: () => context.go('/offline-maps'),
                    ),
                    const SizedBox(height: 4),
                    _menuRow(
                      icon: Icons.support_agent_rounded,
                      label: l10n.helpSupport,
                      onTap: _showHelpSheet,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ── المظهر ────────────────────────────────────
              _section(l10n.appearanceSection),
              GlassCard(
                child: Column(
                  children: [
                    _radioRow(
                      icon: Icons.brightness_auto_rounded,
                      label: l10n.themeSystem,
                      selected: settings.themeMode == 0,
                      onTap: () =>
                          notifier.update((s) => s..themeMode = 0),
                    ),
                    const SizedBox(height: 4),
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
              _presetsGrid(settings, notifier),
              const SizedBox(height: 12),
              // ── الإشعارات ─────────────────────────────────
              _section(l10n.notificationsSection),
              GlassCard(
                child: Column(
                  children: _notificationRows(
                    l10n: l10n,
                    settings: settings,
                    notifier: notifier,
                    dailyTime: dailyTime,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ── اللغة ────────────────────────────────────
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
              // ── تفضيلات العمل ─────────────────────────────
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
              // ── الراتب ────────────────────────────────────
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
              // ── البيانات ──────────────────────────────────
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
              // ── عن التطبيق ────────────────────────────────
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
      ),
    );
  }

  // ── بطاقة إعداد الحساب (أول مرة) ───────────────────────────

  Widget _setupCard(AppLocalizations l10n, UserSettings settings) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(l10n.profileSetup),
          Center(child: _photoCircle(settings, radius: 40)),
          const SizedBox(height: 10),
          TextField(
            controller: _setupNameCtrl,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.fullName,
              hintText: l10n.tapToAddPhoto,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(GlassTokens.radiusS),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GlassButton(
            label: l10n.save,
            icon: Icons.check_rounded,
            onPressed: () async {
              final name = _setupNameCtrl.text.trim();
              await ref.read(settingsProvider.notifier).update(
                    (s) => s..displayName = name,
                  );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.done)),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // ── بطاقة الهوية ───────────────────────────────────────────

  Widget _identityCard(AppLocalizations l10n, UserSettings settings) {
    return GlassCard(
      child: Row(
        children: [
          _photoCircle(settings, radius: 44),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  textInputAction: TextInputAction.done,
                  onChanged: _onNameChanged,
                  onSubmitted: (_) => _flushNameSave(),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    labelText: l10n.fullName,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: LiquidPalette.primaryBlue
                        .withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(GlassTokens.radiusS),
                  ),
                  child: Text(
                    l10n.driverRole,
                    style: const TextStyle(
                      color: LiquidPalette.primaryBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tappable photo circle: saved photo (FileImage) when present, else the
  /// first letter of the name. Dark ring is near-black (#1C1C1E-based), not
  /// navy — per the dark dashboard mockup.
  Widget _photoCircle(UserSettings settings, {double radius = 44}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = settings.displayName.trim();
    final initial = name.isNotEmpty ? name.characters.first : 'م';
    final path = settings.photoPath;
    final file =
        path.isNotEmpty ? File(path) : null;
    final hasPhoto =
        file != null && file.existsSync();

    Widget circle = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : LiquidPalette.glassTint,
        border: Border.all(
          color: LiquidPalette.primaryBlue.withValues(alpha: 0.5),
          width: 2,
        ),
        image: hasPhoto
            ? DecorationImage(
                image: FileImage(file), fit: BoxFit.cover)
            : null,
      ),
      child: hasPhoto
          ? null
          : Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: radius * 0.8,
                  fontWeight: FontWeight.w800,
                  color: LiquidPalette.primaryBlue,
                ),
              ),
            ),
    );

    if (_pickingPhoto) {
      circle = Stack(
        alignment: Alignment.center,
        children: [
          circle,
          // v21: real staged progress, not a looping fake.
          DeliveryLoadingBar(
              width: 120, trackHeight: 5, progress: _photoProgress),
        ],
      );
    }

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Pressable(
          onTap: _pickPhoto,
          borderRadius: BorderRadius.circular(radius * 2),
          child: Tooltip(
            message: AppLocalizations.of(context).changePhoto,
            child: circle,
          ),
        ),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: LiquidPalette.brandGradient,
            ),
            border: Border.all(
              color: isDark
                  ? LiquidPalette.darkSurface
                  : Colors.white,
              width: 2,
            ),
          ),
          child: const Icon(Icons.camera_alt_rounded,
              size: 14, color: Colors.white),
        ),
      ],
    );
  }

  // ── صفوف الإشعارات (مشتركة بين القسم والـ sheet) ────────────

  List<Widget> _notificationRows({
    required AppLocalizations l10n,
    required UserSettings settings,
    required SettingsNotifier notifier,
    required TimeOfDay dailyTime,
  }) {
    return [
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
              if (!mounted) return;
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(l10n.notificationPermissionNeeded)));
              }
            } catch (_) {}
          }
          await notifier.update((s) => s..notificationsEnabled = v);
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
    ];
  }

  // ── شبكة الـ 10 ثيمات ──────────────────────────────────────

  Widget _presetsGrid(UserSettings settings, SettingsNotifier notifier) {
    return GlassCard(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
            onTap: () =>
                notifier.update((s) => s..themePreset = preset.id),
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
                              color:
                                  scheme.primary.withValues(alpha: 0.4),
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
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w400,
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

  Widget _sheetTitle(String title) {
    final text = Theme.of(context).textTheme;
    return Text(
      title,
      style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      textAlign: TextAlign.center,
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

  /// Menu row: icon + label on the right, chevron on the left.
  Widget _menuRow({
    required IconData icon,
    required String label,
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

/// Bottom-sheet shell: dark surface is near-black #1C1C1E-based (never
/// navy), light surface is white glass — matching the mockup identity.
class _SheetShell extends StatelessWidget {
  final Widget child;

  const _SheetShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(top: 48),
      decoration: BoxDecoration(
        color: isDark
            ? LiquidPalette.darkSurface
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(GlassTokens.radiusL)),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.6),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(child: child),
        ),
      ),
    );
  }
}
