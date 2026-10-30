import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_log_service.dart';
import 'app_update.dart';
import 'software_update_screen.dart';

/// v27.37: coordinates the update check from both entry points —
/// the automatic on-launch check and the manual bottom button on the
/// My Account settings list. One policy object, so the two entries
/// can never disagree:
///
/// LAUNCH CHECK (foreground only — runs once per app session, from
/// the main tab shell, after the first frame):
/// - Skipped when the user turned "Automatic Updates" OFF.
/// - Silent on every non-update outcome: no update, check failure,
///   session dismissal, or an active "remind tonight" suppression.
///   Failures land in the diagnostics log with the real reason; the
///   user is never interrupted by a check that found nothing.
/// - Shows the Software Update screen only for a strictly newer
///   versionCode. Closing it marks that versionCode dismissed for
///   this session (see [AppUpdateSession]).
///
/// MANUAL CHECK (bottom button): always fetches fresh, ignores the
/// session dismissal and the remind-tonight suppression, and always
/// reports an outcome: the update screen, an "up to date" dialog, or
/// a loud error dialog with the real reason.
///
/// "REMIND ME TONIGHT": stores the versionCode + time. The launch
/// check suppresses that version only until 18:00 on the same day
/// ([AppUpdateSession.isRemindSuppressed]); at the next evening
/// launch — or any later day — the screen returns. It never
/// installs anything by itself.
class AppUpdateFlow {
  AppUpdateFlow({
    required this.service,
    AppLogService? log,
    AppUpdateSession? session,
    SharedPreferences? prefs,
  })  : _log = log,
        _session = session ?? AppUpdateSession(),
        _prefs = prefs;

  final AppUpdateService service;
  final AppLogService? _log;
  final AppUpdateSession _session;
  SharedPreferences? _prefs;

  static const String autoCheckKey = 'df_update_auto_check';
  static const String remindCodeKey = 'df_update_remind_code';
  static const String remindTimeKey = 'df_update_remind_time_millis';

  AppUpdateSession get sessionForTest => _session;

  Future<SharedPreferences> _prefsInstance() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<bool> autoCheckEnabled() async {
    final prefs = await _prefsInstance();
    // Default ON: a fresh install checks on launch until the user
    // turns "Automatic Updates" off on the update screen.
    return prefs.getBool(autoCheckKey) ?? true;
  }

  Future<void> setAutoCheckEnabled(bool value) async {
    final prefs = await _prefsInstance();
    await prefs.setBool(autoCheckKey, value);
    _log?.info(AppLogCategory.system,
        'Automatic update check ${value ? 'enabled' : 'disabled'}');
  }

  Future<void> _setRemindTonight(int versionCode) async {
    final prefs = await _prefsInstance();
    await prefs.setInt(remindCodeKey, versionCode);
    await prefs.setInt(
        remindTimeKey, DateTime.now().millisecondsSinceEpoch);
    _log?.info(AppLogCategory.system,
        'Update $versionCode: remind tonight (no install scheduled)');
  }

  Future<bool> _remindSuppressed(int versionCode) async {
    final prefs = await _prefsInstance();
    final code = prefs.getInt(remindCodeKey);
    final millis = prefs.getInt(remindTimeKey);
    return AppUpdateSession.isRemindSuppressed(
      remindCode: code,
      remindSetAt:
          millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis),
      manifestCode: versionCode,
      now: DateTime.now(),
    );
  }

  Future<int?> _currentVersionCode() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber);
    } catch (_) {
      return null;
    }
  }

  Future<void> _showUpdateScreen(
    BuildContext context,
    AppUpdateManifest manifest, {
    required bool autoCheck,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SoftwareUpdateScreen(
          manifest: manifest,
          service: service,
          autoCheckEnabled: autoCheck,
          onAutoCheckChanged: setAutoCheckEnabled,
          onRemindTonight: () => _setRemindTonight(manifest.versionCode),
          onClosed: () => _session.dismiss(manifest.versionCode),
        ),
      ),
    );
  }

  /// Automatic launch check. Never throws, never shows anything
  /// except the update screen for a genuinely newer version.
  Future<void> checkOnLaunch(BuildContext context) async {
    try {
      if (!await autoCheckEnabled()) return;
      final current = await _currentVersionCode();
      if (current == null) {
        _log?.warn(AppLogCategory.system,
            'Update check skipped: installed build number unreadable');
        return;
      }
      final manifest = await service.fetchManifest();
      if (!manifest.isNewerThan(current)) return;
      if (_session.isDismissed(manifest.versionCode)) return;
      if (await _remindSuppressed(manifest.versionCode)) return;
      if (!context.mounted) return;
      _log?.info(AppLogCategory.system,
          'Update available on launch: ${manifest.versionName}');
      // The screen's own Automatic Updates row must reflect the
      // real setting, not a hardcoded value.
      final auto = await autoCheckEnabled();
      if (!context.mounted) return;
      await _showUpdateScreen(context, manifest, autoCheck: auto);
    } catch (_) {
      // Launch check is silent by design: the failure is already in
      // the diagnostics log (service logs every fetch failure).
    }
  }

  /// Manual check from the settings bottom button. Always reports
  /// an outcome; [l10n]-free by design — the caller passes the
  /// already-localized strings for the dialogs.
  Future<void> checkManually(
    BuildContext context, {
    required String checkingTitle,
    required String upToDateTitle,
    required String upToDateBody,
    required String errorTitle,
    required String closeLabel,
  }) async {
    // Progress dialog while fetching (dismissed before any outcome).
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(checkingTitle),
        content: const Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: SizedBox()),
          ],
        ),
      ),
    );
    AppUpdateManifest? manifest;
    String? failure;
    int? current;
    try {
      current = await _currentVersionCode();
      manifest = await service.fetchManifest();
    } catch (e) {
      failure = e is AppUpdateException ? e.reason : '$e';
    }
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss the progress dialog
    if (!context.mounted) return;
    if (failure != null || manifest == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(errorTitle),
          content: Text(failure ?? errorTitle),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(closeLabel),
            ),
          ],
        ),
      );
      return;
    }
    if (current == null || !manifest.isNewerThan(current)) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(upToDateTitle),
          content: Text(upToDateBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(closeLabel),
            ),
          ],
        ),
      );
      return;
    }
    final auto = await autoCheckEnabled();
    if (!context.mounted) return;
    await _showUpdateScreen(context, manifest, autoCheck: auto);
  }
}

/// Non-visual widget that runs the launch check exactly once per
/// app session. It lives inside the main tab shell (under the shell
/// Navigator, so it can push the update screen) and renders nothing.
class AppUpdateLaunchCheck extends StatefulWidget {
  final AppUpdateFlow flow;

  const AppUpdateLaunchCheck({super.key, required this.flow});

  @override
  State<AppUpdateLaunchCheck> createState() => _AppUpdateLaunchCheckState();
}

class _AppUpdateLaunchCheckState extends State<AppUpdateLaunchCheck> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started || !mounted) return;
      _started = true;
      widget.flow.checkOnLaunch(context);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
