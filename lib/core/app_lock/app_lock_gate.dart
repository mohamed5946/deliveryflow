import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';

import '../../core/app_lock/app_lock_service.dart';
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
  int _epoch = 0;
  int _attemptedEpoch = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = ref.read(settingsProvider);
    final active = settings.appLockEnabled &&
        settings.registered &&
        settings.onboardingDone;
    _state = AppLockState(enabled: active);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_authInProgress) return; // own biometric prompt — see class doc.
    // Only paused/detached re-arm the lock: transient inactive (system
    // dialogs, notification shade, permission prompts) must NOT lock the
    // app, or every system dialog return would demand a fingerprint.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_state.locked) return;
      setState(() {
        _state.onBackground();
        _epoch++;
      });
    } else if (state == AppLifecycleState.resumed) {
      if (_state.locked) return;
      setState(() {
        _state.onForeground();
        _epoch++;
      });
    }
  }

  Future<void> _tryAuth() async {
    if (_authInProgress || !_state.locked) return;
    _attemptedEpoch = _epoch;
    setState(() {
      _authInProgress = true;
      _authFailed = false;
    });
    final l10n = AppLocalizations.of(context);
    final ok = await ref
        .read(appLockServiceProvider)
        .authenticate(localizedReason: l10n.appLockAuthReason);
    if (!mounted) return;
    setState(() {
      _authInProgress = false;
      if (ok) {
        _state.onAuthSuccess();
        _authFailed = false;
      } else {
        _authFailed = true;
      }
    });
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

    // Auto-prompt once per lock appearance; cancel/failure falls back to
    // the Retry button below (the prompt itself is never re-fired in a loop).
    if (!_authInProgress && _attemptedEpoch != _epoch) {
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
                          child: Text(l10n.appLockAuthFailed,
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
