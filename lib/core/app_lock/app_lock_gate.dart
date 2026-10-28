import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';

import '../../core/app_lock/app_lock_service.dart';
import '../../core/logging/app_log_service.dart';
import '../../core/providers.dart';

/// v27.24: Instagram-style app lock overlay.
///
/// Wired in [DeliveryFlowApp]'s MaterialApp builder so it sits above EVERY
/// route (tabs, order screens, dialogs). It is opaque: locked content is
/// never visible underneath it. It is UI-only — it never touches the
/// foreground tracking service, GPS, or notifications.
///
/// Gate order (deadlock avoidance): the lock is active ONLY when the
/// setting is ON **and** registration + onboarding are done. The lock
/// toggle lives in Profile, which is only reachable after both, so this
/// matches reality — but if the setting were somehow ON with the gates
/// unpassed, the overlay suppresses itself instead of hiding a gate the
/// user must complete (there is deliberately NO way to turn the setting
/// off from inside the lock screen).
///
/// Lifecycle trap handled here: the OS biometric prompt itself moves the
/// app through inactive/resumed. While an auth prompt is in flight
/// ([_authInProgress]), lifecycle transitions are ignored, otherwise the
/// resumed-after-prompt event would re-lock the app right after a
/// successful unlock.
///
/// v27.28: that guard alone was NOT enough. The plugin can deliver its
/// success result BEFORE the activity-resume event propagates to Flutter,
/// so a resumed event arriving after a successful unlock used to hit the
/// old "re-lock on every foreground entry" branch and lock the app again
/// at once — the next prompt then re-asked forever, intermittently
/// (second open fine, third open looping, same finger, same call).
/// A resumed event may now re-lock ONLY after a real backgrounding
/// (paused/detached set [_wentBackground]); prompt-dismissal resumed
/// noise is ignored. The auto-prompt is also armed only after a resumed
/// event plus one settled frame (cold start: the first frame only renders
/// once the activity is resumed), never straight from a transition.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  late final AppLockState _state;
  bool _authInProgress = false;
  bool _authFailed = false;
  AppLockFailure? _lastFailure;
  int _epoch = 0;
  int _attemptedEpoch = -1;
  // v27.28: set only by a real paused/detached while unlocked; a resumed
  // event re-locks ONLY when this is true (see class doc).
  bool _wentBackground = false;
  // v27.28: the auto-prompt fires only while armed — after the first
  // frame on cold start, or after a resumed event plus one settled frame
  // on return from background. Never straight from a lifecycle transition.
  bool _autoPromptArmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = ref.read(settingsProvider);
    final active = settings.appLockEnabled &&
        settings.registered &&
        settings.onboardingDone;
    _state = AppLockState(enabled: active);
    // Cold start: the first frame only renders once the activity is
    // resumed, so arming here cannot fire before resume.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _autoPromptArmed = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _armAutoPromptAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _autoPromptArmed = true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_authInProgress) return; // own biometric prompt — see class doc.
    // Only paused/detached re-arm the lock: transient inactive (system
    // dialogs, notification shade, permission prompts) must NOT lock the
    // app, or every system dialog return would demand a fingerprint.
    // (A prompt dismissal is inactive, never paused, so this cannot fire
    // from our own prompt; the _authInProgress guard above covers the
    // device-credential flow, which DOES pause the app while its PIN
    // activity is on top.)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _autoPromptArmed = false;
      if (_state.locked) return;
      setState(() {
        _state.onBackground();
        _wentBackground = true;
        _epoch++;
      });
    } else if (state == AppLifecycleState.resumed) {
      if (_state.locked) {
        // Already locked (e.g. return from background): re-arm the
        // auto-prompt after one settled frame.
        _armAutoPromptAfterFrame();
        return;
      }
      // Unlocked + resumed: either a genuine return from background
      // (_wentBackground set above) or prompt-dismissal noise. Only the
      // former may re-lock — see the v27.28 note in the class doc.
      if (!_wentBackground) return;
      setState(() {
        _wentBackground = false;
        _state.onForeground();
        _epoch++;
      });
      _armAutoPromptAfterFrame();
    }
  }

  Future<void> _tryAuth() async {
    if (_authInProgress || !_state.locked) return;
    _attemptedEpoch = _epoch;
    setState(() {
      _authInProgress = true;
      _authFailed = false;
      _lastFailure = null;
    });
    final l10n = AppLocalizations.of(context);
    // v27.28: one automatic retry on a busy-class failure (a stale
    // auth_in_progress / no_activity from a previous attempt racing this
    // one). Serialized inside this single call — never two concurrent
    // attempts — with a short pause so the OS can settle.
    var result = await ref
        .read(appLockServiceProvider)
        .authenticateDetailed(localizedReason: l10n.appLockAuthReason);
    if (!result.ok && result.failure == AppLockFailure.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted && _state.locked) {
        result = await ref
            .read(appLockServiceProvider)
            .authenticateDetailed(localizedReason: l10n.appLockAuthReason);
      }
    }
    if (!mounted) return;
    setState(() {
      _authInProgress = false;
      if (result.ok) {
        _state.onAuthSuccess();
        _authFailed = false;
        _lastFailure = null;
        _wentBackground = false;
      } else {
        _authFailed = true;
        _lastFailure = result.failure;
      }
    });
    if (!result.ok) {
      ref.read(appLogServiceProvider).error(
            AppLogCategory.settings,
            'App lock unlock failed: ${result.failure}'
            ' — ${result.detail ?? 'no exception (prompt cancelled or '
                'failed without an error)'}',
          );
    }
  }

  /// v27.28: the lock screen shows the SPECIFIC failure reason (reusing
  /// the v27.26 toggle messages) instead of only the generic line, so a
  /// locked-out user is told to wait/use the PIN instead of retrying a
  /// fingerprint that the OS will keep refusing.
  String _failureText(AppLocalizations l10n) {
    return switch (_lastFailure) {
      AppLockFailure.lockedOut => l10n.appLockLockedOut,
      AppLockFailure.busy => l10n.appLockBusy,
      AppLockFailure.notAvailable => l10n.appLockHardwareUnavailable,
      AppLockFailure.notEnrolled => l10n.appLockNoBiometrics,
      AppLockFailure.cancelled => l10n.appLockAuthCancelled,
      _ => l10n.appLockAuthFailed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final active = settings.appLockEnabled &&
        settings.registered &&
        settings.onboardingDone;
    // Sync the state machine with the setting. Enabling from inside the
    // app does NOT lock the current session (locked stays false until the
    // next background/foreground cycle); disabling always unlocks.
    if (active != _state.enabled) {
      _state.setEnabled(active);
    }
    if (!active || !_state.locked) return widget.child;

    // Auto-prompt once per lock appearance and only while armed (v27.28:
    // first frame on cold start, or resumed + one settled frame on return
    // from background); cancel/failure falls back to the Retry button
    // below (the prompt itself is never re-fired in a loop).
    if (!_authInProgress &&
        _autoPromptArmed &&
        _attemptedEpoch != _epoch) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryAuth());
    }

    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        widget.child,
        // Opaque: no app content may show through the lock screen.
        Positioned.fill(
          child: Scaffold(
            backgroundColor: scheme.surface,
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fingerprint_rounded,
                          size: 72, color: scheme.primary),
                      const SizedBox(height: 24),
                      Text(l10n.appLockUnlockTitle,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      Text(l10n.appLockUnlockHint,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 24),
                      if (_authFailed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(_failureText(l10n),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: scheme.error,
                                  fontWeight: FontWeight.w700)),
                        ),
                      if (_authInProgress)
                        const CircularProgressIndicator()
                      else
                        FilledButton.icon(
                          onPressed: _tryAuth,
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: Text(l10n.appLockRetry),
                        ),
                      // Deliberately NO way to disable the lock from here:
                      // that would defeat the lock entirely.
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
