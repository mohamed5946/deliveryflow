// v27.33 — Account service + offline sync service (backend-agnostic).
//
// Both services work against [CloudBackend], so tests drive them with
// an in-memory fake and production drives them with Firebase. Neither
// service ever sees a password except as a pass-through argument to
// the backend's sign-up/sign-in calls.

import 'cloud_backend.dart';
import 'cloud_types.dart';

/// Exact user-facing taken messages (Mohamed's wording — do not
/// paraphrase). The backend throws English codes ('username taken',
/// 'phone taken'); this service maps them so every surface shows
/// the same Arabic message.
const String usernameTakenMessage =
    'الـ username ده اتاخد قبل كده، اختار username تاني';
const String phoneTakenMessage =
    'رقم الموبايل ده اتاخد قبل كده، استخدم رقم تاني';

/// Thin account facade: sign-up / sign-in / sign-out + role changes,
/// with the client-side role guards (server rules are the real wall).
class CloudAuthService {
  CloudAuthService(this._backend);

  final CloudBackend _backend;

  CloudAccount? get currentAccount => _backend.currentAccount;

  Future<CloudAccount> signUp({
    required String email,
    required String password,
    required String username,
    String phone = '',
  }) async {
    try {
      return await _backend.signUp(
        email: email,
        password: password,
        username: username,
        phone: phone,
      );
    } catch (e) {
      throw _mapTakenError(e);
    }
  }

  Future<CloudAccount> signIn({
    required String email,
    required String password,
  }) =>
      _backend.signIn(email: email, password: password);

  /// Sign in with ONE identifier: username, phone, or email.
  /// Resolves the identifier to the account email, then signs in
  /// with Firebase Auth. Throws when the identifier is unknown or
  /// the password is wrong.
  Future<CloudAccount> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    final email = await _backend.resolveLoginEmail(identifier);
    if (email == null) throw Exception('account not found');
    return _backend.signIn(email: email, password: password);
  }

  /// Live availability check for the sign-up form (cheap single-doc
  /// read, debounced by the UI). True when the username is free.
  Future<bool> isUsernameAvailable(String username) =>
      _backend.isUsernameAvailable(username);

  /// Change the signed-in user's own username (old username stops
  /// resolving immediately). Maps the taken code to the exact Arabic
  /// message, same as sign-up.
  Future<CloudAccount> changeUsername(String newUsername) async {
    try {
      return await _backend.changeUsername(newUsername);
    } catch (e) {
      throw _mapTakenError(e);
    }
  }

  /// Change the signed-in user's own password (re-authenticates with
  /// the current password; old password stops working immediately).
  /// After success, a mustChangePassword flag on the profile is
  /// cleared by the backend.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _backend.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

  /// Forgot flow v1: Firebase-native email reset link.
  Future<void> sendPasswordReset(String email) =>
      _backend.sendPasswordReset(email);

  /// Username reminder for the forgot flow (usernames are not secret).
  Future<String?> lookupUsernameByEmail(String email) =>
      _backend.lookupUsernameByEmail(email);

  /// Restore a persisted Firebase Auth session after an app restart
  /// (see session persistence). Returns null when signed out.
  Future<CloudAccount?> restoreSession() => _backend.restoreSession();

  Exception _mapTakenError(Object e) {
    final text = e.toString();
    if (text.contains('username taken')) {
      return Exception(usernameTakenMessage);
    }
    if (text.contains('phone taken')) {
      return Exception(phoneTakenMessage);
    }
    return e is Exception ? e : Exception(text);
  }

  /// Google sign-in. Returns null when the user cancelled the Google
  /// picker. NO auto-linking: a Google login is a separate account
  /// from an Email/Password login with the same email — drivers must
  /// stick to ONE sign-in method per account (see
  /// google_sign_in_client.dart).
  Future<CloudAccount?> signInWithGoogle() => _backend.signInWithGoogle();

  Future<void> signOut() => _backend.signOut();

  /// Change [targetUid]'s role. Only a signed-in manager may do this,
  /// and nobody may change their own role (including a manager).
  /// Throws [CloudDenied] otherwise; Firestore rules enforce the same.
  Future<void> changeRole(String targetUid, CloudRole role) async {
    final me = _backend.currentAccount;
    if (me == null) throw const CloudDenied('not signed in');
    if (me.uid == targetUid) {
      throw const CloudDenied('cannot change own role');
    }
    if (!me.isManager) {
      throw const CloudDenied('only a manager changes roles');
    }
    final existing = await _backend.fetchProfile(targetUid);
    if (existing == null) throw const CloudDenied('unknown user');
    await _backend.saveProfile(
      CloudAccount(
        uid: existing.uid,
        email: existing.email,
        username: existing.username,
        role: role,
      ),
    );
  }
}

/// Offline-first sync.
///
/// The local Hive store remains the source of truth on the device.
/// Cloud writes go through here: while offline they sit in an
/// in-memory queue and [flushQueue] uploads them on reconnect; while
/// online they upload immediately. A failed flush keeps the queue
/// intact (never silently drops a local edit).
///
/// Download direction: [downloadUserData] returns the user's cloud
/// summaries + raw order docs; the caller (UI wiring) applies them to
/// Hive. Keeping Hive out of this class keeps it unit-testable.
class CloudSyncService {
  CloudSyncService(this._backend);

  final CloudBackend _backend;

  /// Pending uploads: each entry is {'kind': 'summary'|'order',
  /// 'summary': CloudDaySummary} or {'kind': 'order', 'uid': ...,
  /// 'dateKey': ..., 'json': {...}}.
  final List<Map<String, dynamic>> _queue = [];

  List<Map<String, dynamic>> get pendingQueue => List.unmodifiable(_queue);

  bool get hasPending => _queue.isNotEmpty;

  /// Queue a day-summary upload (uploads immediately when online).
  Future<void> queueDaySummary(CloudDaySummary summary) async {
    try {
      await _backend.saveDaySummary(summary);
    } catch (_) {
      _queue.add({'kind': 'summary', 'summary': summary});
    }
  }

  /// Queue a raw order-record upload (uploads immediately when online).
  Future<void> queueOrderRecord(
    String uid,
    String dateKey,
    Map<String, dynamic> json,
  ) async {
    try {
      await _backend.saveOrderRecord(uid, dateKey, json);
    } catch (_) {
      _queue.add({
        'kind': 'order',
        'uid': uid,
        'dateKey': dateKey,
        'json': json,
      });
    }
  }

  /// Upload everything queued, in order. Entries that still fail stay
  /// queued; successful ones are removed. Returns the number uploaded.
  Future<int> flushQueue() async {
    var uploaded = 0;
    final remaining = <Map<String, dynamic>>[];
    for (final entry in _queue) {
      try {
        if (entry['kind'] == 'summary') {
          await _backend.saveDaySummary(entry['summary'] as CloudDaySummary);
        } else {
          await _backend.saveOrderRecord(
            entry['uid'] as String,
            entry['dateKey'] as String,
            entry['json'] as Map<String, dynamic>,
          );
        }
        uploaded++;
      } catch (_) {
        remaining.add(entry);
      }
    }
    _queue
      ..clear()
      ..addAll(remaining);
    return uploaded;
  }

  /// Download everything the cloud has for [uid]: day summaries for
  /// [dateKeys] plus the raw order docs for the same days.
  Future<CloudDownload> downloadUserData(
    String uid,
    List<String> dateKeys,
  ) async {
    final summaries = <CloudDaySummary>[];
    final orders = <String, Map<String, dynamic>>{};
    for (final dateKey in dateKeys) {
      final summary = await _backend.fetchDaySummary(uid, dateKey);
      if (summary != null) summaries.add(summary);
      final order = await _backend.fetchOrderRecord(uid, dateKey);
      if (order != null) orders[dateKey] = order;
    }
    return CloudDownload(summaries: summaries, ordersByDateKey: orders);
  }

  /// First-login migration: upload the device's existing local data
  /// under [uid] EXACTLY ONCE per account. [alreadyMigratedUid] is the
  /// Hive marker (UserSettings.cloudMigratedUid): when it already
  /// equals [uid], nothing is uploaded again. Returns true when an
  /// upload happened, false when skipped. The caller persists the
  /// marker via [markMigrated] only after a true return.
  Future<bool> migrateLocalDataOnce({
    required String uid,
    required String? alreadyMigratedUid,
    required List<CloudDaySummary> localSummaries,
    required List<Map<String, dynamic>> localOrders,
    required Future<void> Function(String uid) markMigrated,
  }) async {
    if (alreadyMigratedUid == uid) return false;
    for (final summary in localSummaries) {
      await _backend.saveDaySummary(summary);
    }
    for (final order in localOrders) {
      final dateKey = order['dateKey'] as String?;
      if (dateKey != null) {
        await _backend.saveOrderRecord(uid, dateKey, order);
      }
    }
    await markMigrated(uid);
    return true;
  }
}

class CloudDownload {
  const CloudDownload({
    required this.summaries,
    required this.ordersByDateKey,
  });

  final List<CloudDaySummary> summaries;
  final Map<String, Map<String, dynamic>> ordersByDateKey;
}
