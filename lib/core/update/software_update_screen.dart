import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';

import 'app_update.dart';

/// v27.37: the Software Update screen, replicating the user's iOS
/// reference picture as closely as Flutter allows:
///
/// - Light gray screen background (#F2F2F7), white rounded cards.
/// - Top bar: back arrow (left, in a white circle) + centered
///   "Software Update" title.
/// - First card, one row: "Automatic Updates" | "On/Off >". Tapping
///   opens an On/Off choice: it toggles the automatic update CHECK
///   on launch ONLY. It never means silent install — there is no
///   silent install for sideloaded apps, and this screen never
///   implies one.
/// - Main card: app icon (rounded square) + "DeliveryFlow" and the
///   version name big + real APK size below it + the REAL changelog
///   from the manifest (never invented notes).
/// - BIG blue pill button "Update Now": foreground download with
///   progress, SHA-256 + size verification, then the Android system
///   install prompt (one-tap confirmation is unavoidable).
/// - Below it, a blue text link "Remind Me Tonight": NOT an
///   overnight install (impossible for sideloaded apps, and XOS
///   kills background work). It dismisses now and re-shows this
///   screen at the next evening launch.
/// - Small gray line under the card: an honest neutral line. No
///   invented legal terms, no fake terms link.
/// - The reference's "ALSO AVAILABLE / Upgrade to iOS 27" section is
///   DELIBERATELY OMITTED: DeliveryFlow has no parallel major-version
///   line, so there is nothing else available to offer.
///
/// Closing the screen (back arrow or system back) counts as a
/// session dismissal (via [onClosed]); the launch check will not nag
/// again this session. A manual check always re-opens it.
class SoftwareUpdateScreen extends StatefulWidget {
  final AppUpdateManifest manifest;
  final AppUpdateService service;

  /// Current automatic-check setting (true = check on launch).
  final bool autoCheckEnabled;

  /// Called when the user picks a new automatic-check value.
  final ValueChanged<bool> onAutoCheckChanged;

  /// Called when the user taps "Remind Me Tonight" (before pop).
  final VoidCallback onRemindTonight;

  /// Called when the screen closes WITHOUT an update action
  /// (back arrow / system back). Not called after Update Now or
  /// Remind Me Tonight.
  final VoidCallback onClosed;

  const SoftwareUpdateScreen({
    super.key,
    required this.manifest,
    required this.service,
    required this.autoCheckEnabled,
    required this.onAutoCheckChanged,
    required this.onRemindTonight,
    required this.onClosed,
  });

  @override
  State<SoftwareUpdateScreen> createState() => _SoftwareUpdateScreenState();
}

class _SoftwareUpdateScreenState extends State<SoftwareUpdateScreen> {
  static const _iosBlue = Color(0xFF007AFF);
  static const _iosGrayBg = Color(0xFFF2F2F7);
  static const _iosGrayText = Color(0xFF8A8A8E);
  static const _iosCardRadius = 12.0;

  late bool _autoCheck = widget.autoCheckEnabled;
  bool _downloading = false;
  double? _progress;
  String? _error;

  /// True once a close callback has been reported, so the PopScope
  /// handler never double-reports after an explicit button close.
  bool _closeReported = false;

  void _finish({required bool reminded}) {
    if (_closeReported) return;
    _closeReported = true;
    if (reminded) {
      widget.onRemindTonight();
    } else {
      widget.onClosed();
    }
    Navigator.of(context).pop();
  }

  Future<void> _pickAutoCheck() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                l10n.updateAutoCheckTitle,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                l10n.updateAutoCheckDesc,
                style: const TextStyle(fontSize: 14, color: _iosGrayText),
              ),
            ),
            _autoCheckOption(ctx, true, l10n.updateAutoCheckOn),
            _autoCheckOption(ctx, false, l10n.updateAutoCheckOff),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _autoCheck = picked);
    widget.onAutoCheckChanged(picked);
  }

  Widget _autoCheckOption(BuildContext ctx, bool value, String label) {
    final selected = _autoCheck == value;
    return ListTile(
      title: Text(label),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: _iosBlue)
          : null,
      onTap: () => Navigator.of(ctx).pop(value),
    );
  }

  Future<void> _showError(String reason) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = reason);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.updateErrorTitle),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _showPermissionGuidance() async {
    final l10n = AppLocalizations.of(context);
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.updatePermissionTitle),
        content: Text(l10n.updatePermissionBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.updateOpenSettings),
          ),
        ],
      ),
    );
    if (open == true) {
      try {
        await widget.service.openUnknownAppsSettings();
      } catch (e) {
        if (mounted) await _showError('$e');
      }
    }
  }

  Future<void> _onUpdateNow() async {
    // Unknown-apps permission FIRST: without it Android cannot show
    // the install prompt at all, so downloading first would waste
    // the user's data and time.
    bool allowed;
    try {
      allowed = await widget.service.canInstallUnknownApps();
    } catch (e) {
      await _showError('$e');
      return;
    }
    if (!mounted) return;
    if (!allowed) {
      await _showPermissionGuidance();
      return;
    }
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      final file = await widget.service.downloadAndVerify(
        widget.manifest,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // Verified: hand to Android's system install prompt. This is
      // the one-tap confirmation — never a silent install.
      await widget.service.installVerifiedApk(file);
      if (!mounted) return;
      // The install prompt is now on top; close this screen behind it.
      _closeReported = true;
      Navigator.of(context).pop();
      return;
    } on AppUpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _progress = null;
      });
      await _showError(e.reason);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _progress = null;
      });
      await _showError('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manifest = widget.manifest;
    final sizeText = formatApkSize(manifest.apkSizeBytes);
    final changelog = manifest.changelog.isEmpty
        ? l10n.updateChangelogFallback
        : manifest.changelog;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_closeReported) {
          _closeReported = true;
          widget.onClosed();
        }
      },
      child: Scaffold(
        backgroundColor: _iosGrayBg,
        appBar: AppBar(
          backgroundColor: _iosGrayBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          leading: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton(
              key: const ValueKey('software-update-back'),
              icon: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.black87,
                  size: 26,
                ),
              ),
              onPressed: () => _finish(reminded: false),
            ),
          ),
          title: Text(
            l10n.softwareUpdateTitle,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Automatic Updates row (reference card 1) ──
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_iosCardRadius),
                ),
                child: InkWell(
                  key: const ValueKey('automatic-updates-row'),
                  borderRadius: BorderRadius.circular(_iosCardRadius),
                  onTap: _pickAutoCheck,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Text(
                          l10n.automaticUpdates,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const Spacer(),
                        Text(
                          _autoCheck
                              ? l10n.updateAutoCheckOn
                              : l10n.updateAutoCheckOff,
                          style: const TextStyle(
                              fontSize: 16, color: _iosGrayText),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: _iosGrayText,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ── Main update card (reference card 2) ──
              // NOTE: the reference's "ALSO AVAILABLE / Upgrade to
              // iOS 27" section is deliberately omitted — DeliveryFlow
              // has no parallel version line, so there is nothing
              // else available to offer.
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_iosCardRadius),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/icon/app_icon.png',
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: _iosBlue,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'D',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DeliveryFlow ${manifest.versionName}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              if (sizeText.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  sizeText,
                                  style: const TextStyle(
                                      fontSize: 15, color: _iosGrayText),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      changelog,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.45,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        key: const ValueKey('update-now-button'),
                        onPressed: _downloading ? null : _onUpdateNow,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _iosBlue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              _iosBlue.withValues(alpha: 0.6),
                          disabledForegroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          _downloading
                              ? (_progress == null
                                  ? l10n.updateVerifying
                                  : l10n.updateDownloading(
                                      (_progress! * 100).round()))
                              : l10n.updateNow,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    if (_downloading && _progress != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _progress,
                          backgroundColor:
                              _iosBlue.withValues(alpha: 0.15),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              _iosBlue),
                          minHeight: 6,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton(
                      key: const ValueKey('remind-tonight-button'),
                      onPressed: _downloading
                          ? null
                          : () => _finish(reminded: true),
                      child: Text(
                        l10n.remindMeTonight,
                        style: const TextStyle(
                            fontSize: 16, color: _iosBlue),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  l10n.updateTermsLine,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: _iosGrayText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
