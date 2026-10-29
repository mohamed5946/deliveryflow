// v27.33 — Riverpod wiring for the cloud layer.
//
// Defaults are the safe unconfigured state: [cloudBackendProvider]
// serves [NotConfiguredBackend] and [cloudConfiguredProvider] is
// false. main() overrides both ONLY when a real Firebase project is
// configured (placeholder options replaced); until then every cloud
// call fails with [CloudNotConfigured] and the UI shows the
// not-configured state instead of crashing or faking sync.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud_backend.dart';
import 'cloud_services.dart';
import 'cloud_types.dart';

/// True only when a real Firebase project is configured. Overridden in
/// main() alongside [cloudBackendProvider].
final cloudConfiguredProvider = Provider<bool>((ref) => false);

final cloudBackendProvider =
    Provider<CloudBackend>((ref) => NotConfiguredBackend());

final cloudAuthServiceProvider = Provider<CloudAuthService>(
  (ref) => CloudAuthService(ref.watch(cloudBackendProvider)),
);

final cloudSyncServiceProvider = Provider<CloudSyncService>(
  (ref) => CloudSyncService(ref.watch(cloudBackendProvider)),
);

/// Account session state. [lastDownload] is the per-account cloud
/// cache: it is CLEARED on sign-out so no previous user's downloaded
/// cloud data can leak into the next session's cloud surfaces. (The
/// device's own local Hive records are separate: they belong to the
/// device owner and stay for offline use; cloud surfaces never read
/// another account's download.)
class CloudAccountState {
  const CloudAccountState({
    this.account,
    this.busy = false,
    this.error,
    this.lastDownload,
    this.pendingGoogle,
  });

  final CloudAccount? account;
  final bool busy;
  final String? error;
  final CloudDownload? lastDownload;

  /// Google sign-up in progress (v27.35): set when
  /// [CloudAccountNotifier.beginGoogleSignUp] returns a
  /// needs-completion result. Null otherwise — never a signed-in
  /// account on its own.
  final GoogleSignUpStart? pendingGoogle;

  bool get signedIn => account != null;

  CloudAccountState copyWith({
    CloudAccount? account,
    bool? busy,
    String? error,
    CloudDownload? lastDownload,
    GoogleSignUpStart? pendingGoogle,
    bool clearAccount = false,
    bool clearDownload = false,
    bool clearPendingGoogle = false,
  }) {
    return CloudAccountState(
      account: clearAccount ? null : (account ?? this.account),
      busy: busy ?? this.busy,
      error: error,
      lastDownload:
          clearDownload ? null : (lastDownload ?? this.lastDownload),
      pendingGoogle: clearPendingGoogle
          ? null
          : (pendingGoogle ?? this.pendingGoogle),
    );
  }
}

class CloudAccountNotifier extends StateNotifier<CloudAccountState> {
  CloudAccountNotifier(this._auth, this._sync)
      : super(const CloudAccountState());

  final CloudAuthService _auth;
  final CloudSyncService _sync;

  Future<bool> signUp({
    required String email,
    required String password,
    required String username,
    String phone = '',
  }) async {
    state = state.copyWith(busy: true);
    try {
      final account = await _auth.signUp(
        email: email,
        password: password,
        username: username,
        phone: phone,
      );
      state = state.copyWith(account: account, busy: false);
      return true;
    } catch (e) {
      state = state.copyWith(busy: false, error: e.toString());
      return false;
    }
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(busy: true);
    try {
      final account = await _auth.signIn(email: email, password: password);
      state = state.copyWith(account: account, busy: false);
      return true;
    } catch (e) {
      state = state.copyWith(busy: false, error: e.toString());
      return false;
    }
  }

  /// Sign in with username, phone, or email + password.
  Future<bool> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(busy: true);
    try {
      final account = await _auth.signInWithIdentifier(
        identifier: identifier,
        password: password,
      );
      state = state.copyWith(account: account, busy: false);
      return true;
    } catch (e) {
      state = state.copyWith(busy: false, error: e.toString());
      return false;
    }
  }

  /// Live username availability for the sign-up form.
  Future<bool> isUsernameAvailable(String username) =>
      _auth.isUsernameAvailable(username);

  /// Live phone availability for the sign-up completion form.
  Future<bool> isPhoneAvailable(String phone) =>
      _auth.isPhoneAvailable(phone);

  /// Google SIGN-UP (v27.35). Returns the start result so the UI can
  /// branch: cancelled → stay; existing account → signed in;
  /// needs-completion → completion form (pendingGoogle set).
  /// Returns null on failure (error set).
  Future<GoogleSignUpStart?> beginGoogleSignUp() async {
    state = state.copyWith(busy: true);
    try {
      final start = await _auth.beginGoogleSignUp();
      if (start.cancelled) {
        state = state.copyWith(busy: false);
        return start;
      }
      if (start.account != null) {
        state = state.copyWith(account: start.account, busy: false);
        return start;
      }
      state = state.copyWith(pendingGoogle: start, busy: false);
      return start;
    } catch (e) {
      state = state.copyWith(busy: false, error: e.toString());
      return null;
    }
  }

  /// Finish a Google sign-up with the completion form's username +
  /// phone. Returns false with the error set when either is taken.
  Future<bool> completeGoogleSignUp({
    required String username,
    required String phone,
  }) async {
    state = state.copyWith(busy: true);
    try {
      final account = await _auth.completeGoogleSignUp(
        username: username,
        phone: phone,
      );
      state = state.copyWith(
        account: account,
        busy: false,
        clearPendingGoogle: true,
      );
      return true;
    } catch (e) {
      state = state.copyWith(busy: false, error: e.toString());
      return false;
    }
  }

  /// Abandon a Google sign-up in progress (completion form
  /// dismissed): ends the session and clears the pending state.
  Future<void> cancelGoogleSignUp() async {
    try {
      await _auth.cancelGoogleSignUp();
    } catch (_) {
      // Session ends locally even if the backend call fails.
    }
    state = state.copyWith(clearPendingGoogle: true);
  }

  /// Change the signed-in user's own username.
  Future<bool> changeUsername(String newUsername) async {
    try {
      final account = await _auth.changeUsername(newUsername);
      state = state.copyWith(account: account);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Change the signed-in user's own password. Returns false with
  /// the error set when the current password is wrong.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _auth.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      // Refresh the session account so a cleared mustChangePassword
      // flag (admin rule) is reflected immediately.
      final refreshed = _auth.currentAccount;
      if (refreshed != null) state = state.copyWith(account: refreshed);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Forgot flow: Firebase-native email reset link.
  Future<bool> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordReset(email);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Forgot flow: username reminder for an email.
  Future<String?> lookupUsernameByEmail(String email) =>
      _auth.lookupUsernameByEmail(email);

  /// Seed a session restored from Firebase Auth persistence (called
  /// once at startup from main()). Only seeds when no account is
  /// set yet — never overwrites a live session.
  void seedRestoredSession(CloudAccount account) {
    if (state.account == null) {
      state = state.copyWith(account: account);
    }
  }

  /// Restore a persisted session (simulated restart in tests, real
  /// restart in production): asks the backend for its stored Auth
  /// session and adopts it when present.
  Future<bool> restoreSession() async {
    final account = await _auth.restoreSession();
    if (account == null) return false;
    state = state.copyWith(account: account);
    return true;
  }

  /// Google sign-in. Returns false on failure; returns true with no
  /// account change when the user cancelled the Google picker
  /// (cancellation is not an error — the form stays usable).
  Future<bool> signInWithGoogle() async {
    state = state.copyWith(busy: true);
    try {
      final account = await _auth.signInWithGoogle();
      if (account == null) {
        state = state.copyWith(busy: false);
        return true;
      }
      state = state.copyWith(account: account, busy: false);
      return true;
    } catch (e) {
      state = state.copyWith(busy: false, error: e.toString());
      return false;
    }
  }

  /// Manager-only: change another user's role (promote/demote).
  /// Self-role-change is refused by [CloudAuthService] (and by the
  /// Firestore rules) — a manager can never demote or escalate
  /// himself from the app.
  Future<bool> changeRole(String targetUid, CloudRole role) async {
    try {
      await _auth.changeRole(targetUid, role);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// v27.35 blacklist: block / unblock a driver. Returns false (and
  /// sets [CloudAccountState.error]) when the backend refuses
  /// (driver caller, self, manager target, wrong block state).
  Future<bool> blockUser(String targetUid) async {
    try {
      await _auth.blockUser(targetUid);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> unblockUser(String targetUid) async {
    try {
      await _auth.unblockUser(targetUid);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// v27.35 payout preferences (own prefs only). On success the
  /// account state refreshes from the backend's updated account so
  /// the form shows the saved values at once.
  Future<bool> updatePayoutPrefs({
    required CloudPayoutMethod method,
    required String number,
    required String name,
  }) async {
    try {
      await _auth.updatePayoutPrefs(
        method: method,
        number: number,
        name: name,
      );
      final account = _auth.currentAccount;
      if (account != null) {
        state = state.copyWith(account: account);
      }
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Seed an error surfaced before the widget tree exists — used by
  /// main() when a restored session turns out to belong to a blocked
  /// account (the restore gate signed the session out; the account
  /// screen shows this message on its choice view).
  void seedError(String message) {
    state = state.copyWith(error: message);
  }

  /// Sign out AND drop the per-account cloud cache, so the next
  /// account's session starts with no previous user's cloud data.
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Session ends locally even if the backend call fails.
    }
    state = const CloudAccountState();
  }

  Future<bool> downloadFor(List<String> dateKeys) async {
    final account = state.account;
    if (account == null) return false;
    state = state.copyWith(busy: true);
    try {
      final download = await _sync.downloadUserData(account.uid, dateKeys);
      state = state.copyWith(lastDownload: download, busy: false);
      return true;
    } catch (e) {
      state = state.copyWith(busy: false, error: e.toString());
      return false;
    }
  }

  void clearError() => state = state.copyWith();
}

/// v27.35 blacklist: dashboard refresh signal. The Management
/// dashboard builds its team list from a FutureBuilder whose future
/// is created in build, so any rebuild refetches — bump this after
/// a block/unblock so the blocked driver leaves (or rejoins) the
/// team list immediately, without waiting for a day change.
final managementRefreshProvider = StateProvider<int>((ref) => 0);

final cloudAccountProvider =
    StateNotifierProvider<CloudAccountNotifier, CloudAccountState>((ref) {
  return CloudAccountNotifier(
    ref.watch(cloudAuthServiceProvider),
    ref.watch(cloudSyncServiceProvider),
  );
});
