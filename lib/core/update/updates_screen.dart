import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../theme/design_system.dart';
import '../../theme/pressable.dart';
import 'app_update.dart';
import 'app_update_flow.dart';

/// v27.38: the dedicated Updates screen + its settings-list row.
///
/// WHY THIS SCREEN EXISTS (field report 2026-10-30): v27.37 put a
/// standalone blue "Check for updates" button at the very bottom of
/// the My Account list, and tapping it showed a BLANK BLACK screen.
/// Root cause, reproduced in a widget test before this fix: the
/// v27.37 manual check showed a progress DIALOG and dismissed it
/// with an unconditional Navigator.pop() after the network call
/// returned. barrierDismissible:false does NOT block Android's
/// system Back button — so if the user pressed Back while the check
/// was still running, the dialog was already gone when the fetch
/// returned, and the blind pop removed the My Account page itself,
/// leaving the branch navigator empty (Flutter renders that as a
/// blank black screen).
///
/// THE FIX IS STRUCTURAL, not cosmetic:
/// - The manual check now lives IN THIS SCREEN. Tapping "Check for
///   updates" shows a loading indicator inside the screen itself —
///   never a dialog, never a blank route, at any point.
/// - The check never pops anything blindly. Results that arrive
///   after the screen is gone (user pressed Back mid-check) are
///   ignored via mounted + generation-token guards — the page
///   underneath is never touched.
/// - Outcomes: update available → the unchanged iOS-style Software
///   Update screen; no update → a clear "You're on the latest
///   update" message with the installed version; failure → a loud
///   dialog with the exact reason (the service already logs it).
///
/// The screen also shows the installed version and the Automatic
/// Updates (launch-check) toggle, so everything update-related lives
/// in one place. The update-available presentation itself is
/// unchanged from v27.37 (iOS Software Update screen, SHA-256
/// verified before install, one-tap Android confirmation — never a
/// silent install).
class UpdatesScreen extends ConsumerStatefulWidget {
  /// Production callers pass nothing: the real service/flow are
  /// built from the app's providers. Tests inject fakes.
  const UpdatesScreen({super.key, this.service, this.flow});

  final AppUpdateService? service;
  final AppUpdateFlow? flow;

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends ConsumerState<UpdatesScreen> {
  late final AppUpdateService _service;
  late final AppUpdateFlow _flow;

  bool _ready = false;
  bool _autoCheck = true;
  String? _versionLabel;
  bool _checking = false;
  bool _upToDate = false;

  /// Generation counter: a check that finishes after a newer check
  /// started — or after this screen was popped — must not touch
  /// state. Combined with mounted checks, this is what makes the
  /// v27.37 black-screen path impossible here: nothing pops.
  int _checkToken = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ??
        AppUpdateService(log: ref.read(appLogServiceProvider));
    _flow = widget.flow ??
        AppUpdateFlow(
          service: _service,
          log: ref.read(appLogServiceProvider),
        );
    _load();
  }

  Future<void> _load() async {
    final auto = await _flow.autoCheckEnabled();
    final label = await _flow.currentVersionLabel();
    if (!mounted) return;
    setState(() {
      _autoCheck = auto;
      _versionLabel = label;
      _ready = true;
    });
  }

  Future<void> _onCheck() async {
    if (_checking) return;
    final token = ++_checkToken;
    setState(() {
      _checking = true;
      _upToDate = false;
    });
    AppUpdateManifest? manifest;
    String? failure;
    int? current;
    try {
      current = await _flow.currentVersionCode();
      manifest = await _service.fetchManifest();
    } catch (e) {
      failure = e is AppUpdateException ? e.reason : '$e';
    }
    // The screen may be gone (Back pressed mid-check): ignore the
    // result entirely. Never pop, never touch a dead tree.
    if (!mounted || token != _checkToken) return;
    setState(() => _checking = false);
    final l10n = AppLocalizations.of(context);
    if (failure != null || manifest == null) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.updateErrorTitle),
          content: Text(failure ?? l10n.updateErrorTitle),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.close),
            ),
          ],
        ),
      );
      return;
    }
    if (current == null || !manifest.isNewerThan(current)) {
      if (!mounted) return;
      setState(() => _upToDate = true);
      return;
    }
    final auto = await _flow.autoCheckEnabled();
    if (!mounted || token != _checkToken) return;
    await _flow.showUpdateScreen(context, manifest, autoCheck: auto);
  }

  Future<void> _onAutoCheckChanged(bool value) async {
    setState(() => _autoCheck = value);
    await _flow.setAutoCheckEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GlassScaffold(
      appBar: AppBar(title: Text(l10n.updates)),
      body: !_ready
          // Near-instant (SharedPreferences + PackageInfo), but a
          // real indicator beats a blank frame every time.
          ? const Center(
              key: ValueKey('updates-loading'),
              child: CircularProgressIndicator(),
            )
          : SingleChildScrollView(
              padding: GlassTokens.screenPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassCard(
                    key: const ValueKey('updates-current-version'),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            color: LiquidPalette.primaryBlue, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.currentVersion,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          _versionLabel ?? '—',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassCard(
                    child: Row(
                      children: [
                        const Icon(Icons.system_update_rounded,
                            color: LiquidPalette.primaryBlue, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.automaticUpdates,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Switch(
                          key: const ValueKey('updates-auto-check-switch'),
                          value: _autoCheck,
                          onChanged: _onAutoCheckChanged,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassButton(
                    key: const ValueKey('updates-check-button'),
                    label: l10n.checkForUpdates,
                    icon: Icons.system_update_rounded,
                    onPressed: _checking ? null : _onCheck,
                  ),
                  if (_checking) ...[
                    const SizedBox(height: 12),
                    GlassCard(
                      key: const ValueKey('updates-checking-indicator'),
                      child: Row(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(width: 16),
                          Expanded(child: Text(l10n.updateChecking)),
                        ],
                      ),
                    ),
                  ],
                  if (_upToDate && !_checking) ...[
                    const SizedBox(height: 12),
                    GlassCard(
                      key: const ValueKey('updates-up-to-date'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  color: Colors.green, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  l10n.updateUpToDate,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                          fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(l10n.updateUpToDateBody),
                          if (_versionLabel != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _versionLabel!,
                              style:
                                  Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// v27.38: the "Updates" settings row for the My Account list.
///
/// Rendered EXACTLY like the sibling rows (same GlassCard + row
/// layout as _menuRow in the profile hub: blue icon, semibold label,
/// chevron) — the v27.37 standalone bottom button is gone. Tapping
/// pushes the Updates screen via the app router. Kept as a separate
/// widget (rather than inline hub code) so its shape + navigation
/// are widget-testable without pumping the whole profile hub.
class UpdatesHubRow extends StatelessWidget {
  const UpdatesHubRow({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return GlassCard(
      child: Pressable(
        onTap: () => context.push('/updates'),
        borderRadius: BorderRadius.circular(GlassTokens.radiusS),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              const Icon(Icons.system_update_rounded,
                  color: LiquidPalette.primaryBlue, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(l10n.updates,
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
      ),
    );
  }
}
