import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../logging/app_log_service.dart';

/// v27.37: in-app self-update for this sideloaded app (no Google Play).
///
/// HOW IT WORKS — and its honest limits (these are stated in code on
/// purpose, so no later edit can quietly promise more):
/// - The app fetches a version manifest from the stable GitHub
///   "latest" release ([defaultManifestUrl]). The release workflow
///   regenerates that manifest on EVERY release (versionCode,
///   versionName, changelog, APK URL, APK SHA-256, APK size), so the
///   manifest is never hand-edited and never stale while CI runs.
/// - If the manifest's versionCode is HIGHER than the installed build
///   number, the iOS-style Software Update screen is shown. The update
///   is NEVER forced: closing the screen (back arrow) dismisses it for
///   the session, and "Update Tonight" only re-shows it at the next
///   evening launch — it is NOT a silent overnight install.
/// - On "Update Now" the APK downloads over HTTPS in the FOREGROUND
///   (no background work while the app is closed — the user's Infinix
///   XOS kills background work anyway), the SHA-256 (and size) are
///   verified BEFORE anything installs, and only then is the Android
///   system install prompt opened via FileProvider.
/// - Android REQUIRES a one-tap install confirmation for sideloaded
///   apps. There is no fully silent update and this feature never
///   claims otherwise, in UI copy or in logs.
/// - Update-over-install works because every release build is signed
///   with the same stable release key (already in the API-key
///   restriction); no new fingerprint is needed for this feature.

/// Stable manifest URL: the `version.json` asset of the "latest"
/// GitHub release. GitHub redirects this to the real asset; the http
/// client follows redirects for GET.
const String defaultManifestUrl =
    'https://github.com/mohamed5946/deliveryflow/releases/download/latest/version.json';

/// Stable APK URL: the `app-release.apk` asset of the "latest"
/// release. NEVER an expiring fast link — the updater must keep
/// working months after a release, not 48 hours.
const String defaultApkUrl =
    'https://github.com/mohamed5946/deliveryflow/releases/download/latest/app-release.apk';

/// One version manifest, as published by CI. Parsing is tolerant: a
/// manifest missing a required field, or with a non-numeric
/// versionCode, is rejected (null) rather than half-trusted — a
/// half-parsed manifest must never trigger a download.
class AppUpdateManifest {
  final int versionCode;
  final String versionName;
  final String changelog;
  final String apkUrl;
  final String apkSha256;
  final int apkSizeBytes;

  const AppUpdateManifest({
    required this.versionCode,
    required this.versionName,
    required this.changelog,
    required this.apkUrl,
    required this.apkSha256,
    required this.apkSizeBytes,
  });

  static AppUpdateManifest? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final m = Map<String, dynamic>.from(decoded);
      final versionCode = (m['versionCode'] as num?)?.toInt();
      final versionName = m['versionName'] as String?;
      final apkUrl = m['apkUrl'] as String?;
      final apkSha256 = m['apkSha256'] as String?;
      if (versionCode == null ||
          versionName == null ||
          versionName.isEmpty ||
          apkUrl == null ||
          apkUrl.isEmpty ||
          apkSha256 == null ||
          apkSha256.isEmpty) {
        return null;
      }
      return AppUpdateManifest(
        versionCode: versionCode,
        versionName: versionName,
        changelog: (m['changelog'] as String?) ?? '',
        apkUrl: apkUrl,
        apkSha256: apkSha256,
        apkSizeBytes: (m['apkSizeBytes'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// An update exists only when the manifest is STRICTLY newer.
  /// Equal or older versionCodes never prompt — so v27.37 launching
  /// against its own manifest (27.37.0+70) stays silent.
  bool isNewerThan(int currentVersionCode) =>
      versionCode > currentVersionCode;
}

/// SHA-256 of [bytes] as a lowercase hex string.
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Verifies a downloaded APK against the manifest. Returns null when
/// the bytes are good, otherwise a human-readable reason (shown loudly
/// in the UI and in the diagnostics log). A mismatch must NEVER
/// install: the caller deletes the file on any non-null result.
String? verifyDownloadedApk(List<int> bytes, AppUpdateManifest manifest) {
  if (manifest.apkSizeBytes > 0 && bytes.length != manifest.apkSizeBytes) {
    return 'Download size mismatch: got ${bytes.length} bytes, '
        'expected ${manifest.apkSizeBytes} bytes.';
  }
  final actual = sha256Hex(bytes);
  if (actual.toLowerCase() != manifest.apkSha256.toLowerCase()) {
    return 'SHA-256 mismatch: the downloaded file does not match the '
        'published release. The file was deleted and nothing was installed.';
  }
  return null;
}

/// Human APK size, iOS-style: "74 MB", "6.25 GB". Real sizes only —
/// callers pass the manifest's byte count, never a guess.
String formatApkSize(int bytes) {
  if (bytes <= 0) return '';
  const gb = 1024 * 1024 * 1024;
  const mb = 1024 * 1024;
  if (bytes >= gb) {
    return '${_trim2(bytes / gb)} GB';
  }
  if (bytes >= mb) {
    final v = bytes / mb;
    return v >= 10 ? '${v.round()} MB' : '${_trim2(v)} MB';
  }
  return '${(bytes / 1024).round()} KB';
}

String _trim2(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}

/// Failure of any update step, carrying the REAL reason (never a
/// swallowed generic error — the standing diagnostics rule).
class AppUpdateException implements Exception {
  final String reason;
  const AppUpdateException(this.reason);
  @override
  String toString() => 'AppUpdateException: $reason';
}

/// Session dismissal policy (in-memory only — a fresh launch checks
/// again, which is the correct behaviour for a new session).
///
/// - [dismissedVersionCode]: the versionCode the user closed (back
///   arrow / Later) this session. The launch check skips exactly that
///   code; a manual check always shows it again.
/// - "Update Tonight" is NOT a silent install: it stores the code +
///   time, and [isRemindSuppressed] only suppresses the prompt until
///   the evening of the same day. At the next evening launch (or any
///   later day) the prompt returns.
class AppUpdateSession {
  int? dismissedVersionCode;

  void dismiss(int versionCode) => dismissedVersionCode = versionCode;

  bool isDismissed(int versionCode) =>
      dismissedVersionCode == versionCode;

  /// Pure reminder-suppression rule (kept static so tests can pin it
  /// without SharedPreferences): suppress only while the reminder was
  /// set earlier TODAY and it is still before 18:00. Evening (or a
  /// later day) means "tonight" has arrived — show the prompt.
  static bool isRemindSuppressed({
    required int? remindCode,
    required DateTime? remindSetAt,
    required int manifestCode,
    required DateTime now,
  }) {
    if (remindCode == null || remindSetAt == null) return false;
    if (remindCode != manifestCode) return false;
    final sameDay = remindSetAt.year == now.year &&
        remindSetAt.month == now.month &&
        remindSetAt.day == now.day;
    if (!sameDay) return false;
    return now.hour < 18;
  }
}

/// Native side of the install step (MainActivity MethodChannel
/// `com.valor.deliveryflow/app_update`). Kept behind an interface so
/// tests and the UI never touch a MethodChannel directly.
abstract class AppUpdateInstaller {
  Future<bool> canInstallUnknownApps();
  Future<void> openUnknownAppsSettings();
  Future<void> installApk(File apkFile);
}

class MethodChannelAppUpdateInstaller implements AppUpdateInstaller {
  static const _channel =
      MethodChannel('com.valor.deliveryflow/app_update');

  @override
  Future<bool> canInstallUnknownApps() async {
    try {
      return await _channel.invokeMethod<bool>('canInstallUnknownApps') ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openUnknownAppsSettings() async {
    await _channel.invokeMethod<void>('openUnknownAppsSettings');
  }

  @override
  Future<void> installApk(File apkFile) async {
    await _channel.invokeMethod<void>('installApk', {
      'path': apkFile.path,
    });
  }
}

/// The update service: manifest fetch, APK download + verification,
/// install handoff. The diagnostics log records every outcome with
/// its real reason; [log] is optional so unit tests run without it.
class AppUpdateService {
  AppUpdateService({
    http.Client? client,
    AppUpdateInstaller? installer,
    AppLogService? log,
    this.manifestUrl = defaultManifestUrl,
    Directory Function()? downloadDir,
  })  : _client = client ?? http.Client(),
        _installer = installer ?? MethodChannelAppUpdateInstaller(),
        _log = log,
        _downloadDir = downloadDir;

  final http.Client _client;
  final AppUpdateInstaller _installer;
  final AppLogService? _log;
  final String manifestUrl;
  final Directory Function()? _downloadDir;

  AppUpdateInstaller get installer => _installer;

  void _info(String message, {String? detail}) =>
      _log?.info(AppLogCategory.system, message, detail: detail);

  void _error(String message, {String? detail}) =>
      _log?.error(AppLogCategory.system, message, detail: detail);

  /// Fetches and parses the manifest. Throws [AppUpdateException]
  /// with the real reason on any failure (network, HTTP status,
  /// unparseable body) — callers surface it, never swallow it.
  Future<AppUpdateManifest> fetchManifest() async {
    try {
      final response = await _client
          .get(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        final reason =
            'Update check failed: server returned HTTP ${response.statusCode}.';
        _error('Update check failed', detail: reason);
        throw AppUpdateException(reason);
      }
      final manifest = AppUpdateManifest.tryParse(response.body);
      if (manifest == null) {
        const reason =
            'Update check failed: the version manifest could not be read.';
        _error('Update check failed', detail: reason);
        throw AppUpdateException(reason);
      }
      _info('Update check: latest is ${manifest.versionName}'
          '+${manifest.versionCode}');
      return manifest;
    } on AppUpdateException {
      rethrow;
    } catch (e) {
      final reason = 'Update check failed: $e';
      _error('Update check failed', detail: reason);
      throw AppUpdateException(reason);
    }
  }

  /// Downloads the manifest's APK over HTTPS with progress
  /// (0.0–1.0, or null when the server gives no length), verifies
  /// SHA-256 + size, and returns the verified file. On ANY failure
  /// the partial/bad file is deleted and an [AppUpdateException]
  /// with the reason is thrown — a bad file is never installed.
  Future<File> downloadAndVerify(
    AppUpdateManifest manifest, {
    void Function(double? progress)? onProgress,
  }) async {
    final dir = _downloadDir != null
        ? _downloadDir!()
        : await getTemporaryDirectory();
    final updatesDir = Directory('${dir.path}/updates');
    if (!updatesDir.existsSync()) updatesDir.createSync(recursive: true);
    final file = File('${updatesDir.path}/app-release.apk');
    try {
      final request = http.Request('GET', Uri.parse(manifest.apkUrl));
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (streamed.statusCode != 200) {
        throw AppUpdateException(
          'Download failed: server returned HTTP ${streamed.statusCode}.',
        );
      }
      final total = streamed.contentLength;
      final bytes = <int>[];
      await for (final chunk in streamed.stream) {
        bytes.addAll(chunk);
        if (total != null && total > 0) {
          onProgress?.call(bytes.length / total);
        } else {
          onProgress?.call(null);
        }
      }
      _info('Update download finished: ${bytes.length} bytes');
      final problem = verifyDownloadedApk(bytes, manifest);
      if (problem != null) {
        _error('Update verification failed', detail: problem);
        throw AppUpdateException(problem);
      }
      file.writeAsBytesSync(bytes, flush: true);
      _info('Update verified: SHA-256 matches the published release');
      return file;
    } catch (e) {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
      if (e is AppUpdateException) {
        _error('Update download failed', detail: e.reason);
        rethrow;
      }
      final reason = 'Download failed: $e';
      _error('Update download failed', detail: reason);
      throw AppUpdateException(reason);
    }
  }

  Future<bool> canInstallUnknownApps() =>
      _installer.canInstallUnknownApps();

  Future<void> openUnknownAppsSettings() =>
      _installer.openUnknownAppsSettings();

  /// Hands the VERIFIED file to Android's system install prompt.
  /// Android shows its own one-tap confirmation — this call does not
  /// and cannot install silently.
  Future<void> installVerifiedApk(File apkFile) async {
    _info('Update install prompt requested for verified APK');
    await _installer.installApk(apkFile);
  }

  @visibleForTesting
  http.Client get clientForTest => _client;
}
