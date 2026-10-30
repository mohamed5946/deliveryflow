// v27.36 — Wires CloudLiveSync into the app shell's lifecycle.
//
// Placed once in the shell Stack (router.dart) so it lives under the
// app's Navigator for its whole lifetime:
//
//   - Account changes drive the service: sign-in / session restore
//     starts live sync, sign-out stops it (listeners detach, so no
//     previous user's data can leak into the next session).
//   - Live-sync failures surface as LOUD dialogs with the exact
//     reason (never a silent stale screen): Retry re-attaches,
//     Dismiss silences until a NEW failure episode arrives.
//   - Live data changes bump the data version (driver screens
//     refetch) and the management refresh signal (the Management
//     dashboard refetches), so visible screens update at once
//     without any manual refresh.
//   - App-foreground returns retry queued uploads.
//
// This widget renders nothing.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloud/cloud_live_sync.dart';
import '../../core/cloud/cloud_providers.dart';
import '../../core/providers.dart';
import 'cloud_download_apply.dart';

class CloudLiveSyncBootstrapper extends ConsumerStatefulWidget {
  const CloudLiveSyncBootstrapper({super.key});

  @override
  ConsumerState<CloudLiveSyncBootstrapper> createState() =>
      _CloudLiveSyncBootstrapperState();
}

class _CloudLiveSyncBootstrapperState
    extends ConsumerState<CloudLiveSyncBootstrapper>
    with WidgetsBindingObserver {
  CloudLiveSync? _liveSync;
  StreamSubscription<LiveSyncFailure>? _failureSub;
  StreamSubscription<void>? _dataChangedSub;
  bool _dialogOpen = false;
  bool _firstBuildDone = false;

  CloudLiveSync _ensureLiveSync() {
    var live = _liveSync;
    if (live == null) {
      final db = ref.read(databaseServiceProvider);
      live = CloudLiveSync(
        backend: ref.read(cloudBackendProvider),
        sync: ref.read(cloudSyncServiceProvider),
        db: db,
        applyDownload: (download) async {
          final result =
              await applyCloudDownload(db: db, download: download);
          return result.changedDays + result.clearedDays;
        },
        log: ref.read(appLogServiceProvider),
      );
      _failureSub = live.failures.listen(_showFailureDialog);
      _dataChangedSub = live.dataChanged.listen((_) {
        if (!mounted) return;
        bumpDataVersion(ref);
        ref.read(managementRefreshProvider.notifier).state++;
      });
      _liveSync = live;
    }
    return live;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _failureSub?.cancel();
    _dataChangedSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_liveSync?.onAppResumed() ?? Future.value());
    }
  }

  Future<void> _showFailureDialog(LiveSyncFailure failure) async {
    if (!mounted || _dialogOpen) return;
    _dialogOpen = true;
    try {
      final account = ref.read(cloudAccountProvider).account;
      final retry = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('المزامنة المباشرة توقفت'),
          content: Text(
            'حدث خطأ أثناء المزامنة التلقائية:\n\n${failure.reason}\n\n'
            'البيانات المحلية محفوظة ولم تضِع. جرّب إعادة الاتصال، '
            'أو استخدم زر المزامنة اليدوية.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تجاهل'),
            ),
            if (account != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('إعادة الاتصال'),
              ),
          ],
        ),
      );
      if (retry == true && account != null && mounted) {
        await _liveSync?.restart(account);
      }
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CloudAccountState>(cloudAccountProvider, (previous, next) {
      final account = next.account;
      if (account != null) {
        unawaited(_ensureLiveSync().start(account));
      } else {
        unawaited(_liveSync?.stop() ?? Future.value());
      }
    });
    // Restored sessions are seeded before the first frame, so no
    // provider change fires for them: start once on first build.
    if (!_firstBuildDone) {
      _firstBuildDone = true;
      final account = ref.read(cloudAccountProvider).account;
      if (account != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_ensureLiveSync().start(account));
        });
      }
    }
    return const SizedBox.shrink();
  }
}
