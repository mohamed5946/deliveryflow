import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// v27.24: fingerprint / device-credential app lock (Instagram-style).
///
/// The lock is UI-only: it never touches tracking, GPS, or notifications,
/// and it never reads or stores any gate password — it only asks the OS
/// to confirm the device owner (biometrics first, device PIN/pattern/
/// password as fallback) via [LocalAuthentication].
///
/// v27.26: the v27.24 build swallowed the OS failure (`catch (_) => false`
/// in [LocalAuthClient.authenticate]), so a device where the system
/// prompt never appeared produced only the generic "Verification failed"
/// toast and nobody — not even the diagnostics log — could say why.
/// That hiding is itself fixed here: [AppLockAuthResult] carries the
/// exact failure (mapped [PlatformException] code + message, never any
/// biometric data), the toggle handler logs it, and known codes map to
/// specific user messages. The plain-bool [authenticate] is kept for the
/// lock gate, which only needs ok/not-ok.
///
/// [AppLockAuthClient] exists so widget/unit tests can fake the OS prompt
/// without a device; production uses [LocalAuthClient].

/// Structured outcome of one OS auth attempt.
enum AppLockFailure {
  /// Prompt dismissed by the user, or a plain `false` with no exception.
  /// (On Android a mismatched finger does NOT complete the prompt — it
  /// stays open — so a bare `false` can only come from a cancel path.)
  cancelled,

  /// No biometrics enrolled on this device (plugin code `NotEnrolled`).
  /// The prompt may never appear: Android refuses to build it.
  notEnrolled,

  /// OS reports no usable auth at all (plugin code `NotAvailable`:
  /// hardware unavailable / no device credential / not supported).
  /// This is the "no prompt at all" class on OEM devices.
  notAvailable,

  /// Temporarily or permanently locked out after failed attempts
  /// (plugin codes `LockedOut`, `PermanentlyLockedOut`).
  lockedOut,

  /// Another auth attempt is already in flight (`auth_in_progress`) or
  /// the activity is gone (`no_activity`, `no_fragment_activity`).
  busy,

  /// Any other exception, or an unknown plugin code.
  unknown,
}

/// Maps a thrown object from the local_auth plugin to [AppLockFailure].
AppLockFailure mapAuthException(Object error) {
  if (error is PlatformException) {
    return switch (error.code) {
      'NotEnrolled' => AppLockFailure.notEnrolled,
      'NotAvailable' => AppLockFailure.notAvailable,
      'LockedOut' || 'PermanentlyLockedOut' => AppLockFailure.lockedOut,
      'auth_in_progress' ||
      'no_activity' ||
      'no_fragment_activity' =>
        AppLockFailure.busy,
      _ => AppLockFailure.unknown,
    };
  }
  return AppLockFailure.unknown;
}

class AppLockAuthResult {
  const AppLockAuthResult({required this.ok, this.failure, this.detail});

  /// True only when the OS confirmed the device owner.
  final bool ok;

  /// Null on success. Never contains biometric data — only the mapped
  /// failure class (see [detail] for the raw plugin code/message).
  final AppLockFailure? failure;

  /// Raw plugin error for the diagnostics log, e.g.
  /// `NotAvailable: Security credentials not available.` Null when the
  /// attempt simply returned false with no exception.
  final String? detail;
}

abstract class AppLockAuthClient {
  /// True when the device can run an OS auth prompt at all (hardware +
  /// OS support). This is the toggle-availability check: false means the
  /// Settings toggle must be shown disabled, never a fake ON toggle.
  Future<bool> isDeviceSupported();

  /// Runs the OS prompt. [biometricOnly] is always false here on purpose:
  /// a user with no enrolled biometrics, or with failed biometrics, must
  /// still be able to fall back to device credentials instead of being
  /// hard-locked out of the app.
  Future<bool> authenticate({required String localizedReason});

  /// Biometrics the OS reports as enrolled (empty = none enrolled).
  /// Default: unknown (old fakes) — production overrides this.
  /// Used as a precheck: an empty list before authenticating explains
  /// a prompt that never appears, without guessing.
  Future<List<BiometricType>> getAvailableBiometrics() async => [];

  /// Same prompt as [authenticate], but with the structured outcome.
  /// Default: wraps [authenticate] so existing fakes keep working.
  Future<AppLockAuthResult> authenticateDetailed({
    required String localizedReason,
  }) async {
    try {
      final ok = await authenticate(localizedReason: localizedReason);
      return AppLockAuthResult(
        ok: ok,
        failure: ok ? null : AppLockFailure.cancelled,
      );
    } on PlatformException catch (e) {
      return AppLockAuthResult(
        ok: false,
        failure: mapAuthException(e),
        detail: '${e.code}: ${e.message}',
      );
    } catch (e) {
      return AppLockAuthResult(
        ok: false,
        failure: AppLockFailure.unknown,
        detail: '$e',
      );
    }
  }
}

class LocalAuthClient implements AppLockAuthClient {
  LocalAuthClient([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String localizedReason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<AppLockAuthResult> authenticateDetailed({
    required String localizedReason,
  }) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      return AppLockAuthResult(
        ok: ok,
        failure: ok ? null : AppLockFailure.cancelled,
      );
    } on PlatformException catch (e) {
      return AppLockAuthResult(
        ok: false,
        failure: mapAuthException(e),
        detail: '${e.code}: ${e.message}',
      );
    } catch (e) {
      return AppLockAuthResult(
        ok: false,
        failure: AppLockFailure.unknown,
        detail: '$e',
      );
    }
  }
}

/// Pure lock state machine — unit-testable without widgets or the OS.
///
/// Rules (see AppLockGate):
/// * locked starts true: a cold start with the setting ON is locked.
/// * [onForeground] re-locks on every foreground entry while ON.
/// * [onBackground] re-arms the lock; the next foreground entry locks.
/// * [onAuthSuccess] unlocks only the current foreground session.
/// * The setting being OFF always yields unlocked.
class AppLockState {
  AppLockState({required bool enabled}) : _enabled = enabled, locked = enabled;

  bool _enabled;
  bool locked;

  bool get enabled => _enabled;

  void setEnabled(bool value) {
    _enabled = value;
    if (!value) locked = false;
  }

  void onBackground() {
    if (_enabled) locked = true;
  }

  void onForeground() {
    if (_enabled) locked = true;
  }

  void onAuthSuccess() {
    locked = false;
  }
}

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService(LocalAuthClient());
});

/// Shared app-lock gate status, owned (written) by [AppLockGate] and
/// read by widgets that must wait for unlock — currently the splash
/// entry (v27.30 lock-first ordering).
///
/// Value true means the app is NOT currently locked: either the lock
/// setting is off (or the gates are unpassed, so the lock suppresses
/// itself) or the user just unlocked. Value false means the lock
/// screen is showing. Initial value true is only a placeholder: the
/// gate syncs it in its own initState, which runs before any route
/// widget (including the splash) mounts, so readers never observe a
/// stale "open" on a locked cold start.
final appLockGateOpenProvider = Provider<ValueNotifier<bool>>((ref) {
  return ValueNotifier<bool>(true);
});

/// Thin service around [AppLockAuthClient] for screens to call.
class AppLockService {
  AppLockService(this._client);

  final AppLockAuthClient _client;

  Future<bool> canUseLock() => _client.isDeviceSupported();

  Future<bool> authenticate({required String localizedReason}) =>
      _client.authenticate(localizedReason: localizedReason);

  Future<List<BiometricType>> enrolledBiometrics() =>
      _client.getAvailableBiometrics();

  Future<AppLockAuthResult> authenticateDetailed(
          {required String localizedReason}) =>
      _client.authenticateDetailed(localizedReason: localizedReason);
}
