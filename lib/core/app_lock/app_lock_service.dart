import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// v27.24: fingerprint / device-credential app lock (Instagram-style).
///
/// The lock is UI-only: it never touches tracking, GPS, or notifications,
/// and it never reads or stores any gate password — it only asks the OS
/// to confirm the device owner (biometrics first, device PIN/pattern/
/// password as fallback) via [LocalAuthentication].
///
/// [AppLockAuthClient] exists so widget/unit tests can fake the OS prompt
/// without a device; production uses [LocalAuthClient].
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
}

class LocalAuthClient implements AppLockAuthClient {
  LocalAuthClient([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

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

/// Thin service around [AppLockAuthClient] for screens to call.
class AppLockService {
  AppLockService(this._client);

  final AppLockAuthClient _client;

  Future<bool> canUseLock() => _client.isDeviceSupported();

  Future<bool> authenticate({required String localizedReason}) =>
      _client.authenticate(localizedReason: localizedReason);
}
