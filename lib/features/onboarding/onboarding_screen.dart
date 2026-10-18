import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../theme/design_system.dart';

/// First-launch setup: name, language, theme, reminder time, notifications,
/// optional weekly goals. Non-essential steps can be skipped.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  final _goalOrders = TextEditingController();
  final _goalHours = TextEditingController();
  String _lang = 'ar';
  int _theme = 0;
  TimeOfDay _reminder = const TimeOfDay(hour: 21, minute: 0);
  bool _notifications = true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _goalOrders.dispose();
    _goalHours.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _reminder);
    if (t != null) setState(() => _reminder = t);
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.update((s) => s
      ..displayName = _name.text.trim()
      ..languageCode = _lang
      ..themeMode = _theme
      ..dailyReminderHour = _reminder.hour
      ..dailyReminderMinute = _reminder.minute
      ..notificationsEnabled = _notifications
      ..dailyReminderEnabled = _notifications
      ..scheduleReminderEnabled = _notifications
      ..reportReminderEnabled = _notifications
      ..weeklyOrderGoal = int.tryParse(_goalOrders.text.trim())
      ..weeklyWorkHoursGoal = double.tryParse(_goalHours.text.trim())
      ..onboardingDone = true);
    if (_notifications) {
      try {
        await ref
            .read(notificationServiceProvider)
            .requestPermission();
      } catch (_) {}
    }
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // v23: guarantee contrast on the first-launch screen — white text when
    // the effective background is dark, near-black when it is light,
    // regardless of theme text-style drift.
    final onBg = isDark ? Colors.white : const Color(0xFF111418);
    final onBgSoft = (isDark ? Colors.white : const Color(0xFF111418))
        .withValues(alpha: 0.72);
    return Scaffold(
      backgroundColor: Colors.transparent,
      // v23: same Liquid Glass skin as the rest of the app — the onboarding
      // route sits outside the shell, so it needs its own AuroraBackground
      // (otherwise it floats over an undefined backdrop).
      body: Stack(
        children: [
          const AuroraBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 8),
                // v23: brand mark — same 72dp gradient tile as the
                // registration gate, so both first-launch screens share
                // the app's Liquid Glass identity.
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LiquidPalette.brandGradientLg,
                      boxShadow: [
                        BoxShadow(
                          color: LiquidPalette.primaryBlue
                              .withValues(alpha: 0.4),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.waving_hand_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(l10n.onboardingTitle,
                    style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800, color: onBg),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(l10n.onboardingSubtitle,
                    style:
                        text.bodyMedium?.copyWith(color: onBgSoft),
                    textAlign: TextAlign.center),
                const SizedBox(height: 32),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.displayNameLabel,
                      style: text.titleSmall?.copyWith(color: onBg)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                        hintText: l10n.displayNameHint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.preferredLanguage,
                      style: text.titleSmall?.copyWith(color: onBg)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'ar', label: Text('العربية')),
                      ButtonSegment(value: 'en', label: Text('English')),
                    ],
                    selected: {_lang},
                    onSelectionChanged: (s) =>
                        setState(() => _lang = s.first),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.preferredTheme,
                      style: text.titleSmall?.copyWith(color: onBg)),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                          value: 0, label: Text(l10n.themeSystem)),
                      ButtonSegment(
                          value: 1, label: Text(l10n.themeLight)),
                      ButtonSegment(
                          value: 2, label: Text(l10n.themeDark)),
                    ],
                    selected: {_theme},
                    onSelectionChanged: (s) =>
                        setState(() => _theme = s.first),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text(l10n.reminderTimeLabel,
                              style: text.titleSmall?.copyWith(color: onBg))),
                      TextButton(
                        onPressed: _pickTime,
                        child: Text(_reminder.format(context),
                            style: const TextStyle(fontSize: 18)),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.notificationsEnabled,
                        style: text.titleSmall?.copyWith(color: onBg)),
                    value: _notifications,
                    onChanged: (v) =>
                        setState(() => _notifications = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.weeklyOrderGoal,
                      style: text.titleSmall?.copyWith(color: onBg)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _goalOrders,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(hintText: l10n.skip),
                  ),
                  const SizedBox(height: 12),
                  Text(l10n.weeklyHoursGoal,
                      style: text.titleSmall?.copyWith(color: onBg)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _goalHours,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    decoration:
                        InputDecoration(hintText: l10n.skip),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: GlassButton(
                label: _saving ? '…' : l10n.done,
                onPressed: _saving ? null : _finish,
                icon: Icons.check_rounded,
              ),
            ),
          ],
        ),
      ),
      ],
      ),
    );
  }
}
