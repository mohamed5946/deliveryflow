// v27.33 — Account service + offline sync service (backend-agnostic).
//
// Both services work against [CloudBackend], so tests drive them with
// an in-memory fake and production drives them with Firebase. Neither
// service ever sees a password except as a pass-through argument to
// the backend's sign-up/sign-in calls.

import 'cloud_backend.dart';
import 'cloud_types.dart';
import 'adjustment_logic.dart';
import 'retention_logic.dart';

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

  /// Live availability check for the sign-up completion form.
  /// True when the phone is free.
  Future<bool> isPhoneAvailable(String phone) =>
      _backend.isPhoneAvailable(phone);

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

  /// Google SIGN-UP (v27.35): start the Google flow without
  /// creating a profile, so the completion form can collect
  /// username + phone first. See [CloudBackend.beginGoogleSignUp].
  Future<GoogleSignUpStart> beginGoogleSignUp() =>
      _backend.beginGoogleSignUp();

  /// Finish a Google sign-up: create the driver profile + mappings
  /// with the given username + phone. Maps taken codes to the exact
  /// Arabic messages, same as email sign-up.
  Future<CloudAccount> completeGoogleSignUp({
    required String username,
    required String phone,
  }) async {
    try {
      return await _backend.completeGoogleSignUp(
        username: username,
        phone: phone,
      );
    } catch (e) {
      throw _mapTakenError(e);
    }
  }

  /// Abandon a Google sign-up in progress.
  Future<void> cancelGoogleSignUp() => _backend.cancelGoogleSignUp();

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
    // v27.35: the role is the ONLY field this changes — every other
    // profile field (phone, payout prefs, blocked flags,
    // forced-change flag) is carried over from the existing doc, so
    // a promotion or demotion never silently wipes a driver's data.
    await _backend.saveProfile(
      CloudAccount(
        uid: existing.uid,
        email: existing.email,
        username: existing.username,
        role: role,
        phone: existing.phone,
        mustChangePassword: existing.mustChangePassword,
        blocked: existing.blocked,
        blockedAt: existing.blockedAt,
        blockedBy: existing.blockedBy,
        payoutMethod: existing.payoutMethod,
        payoutNumber: existing.payoutNumber,
        payoutName: existing.payoutName,
      ),
    );
  }

  /// v27.35 blacklist: block / unblock a driver (manager-only, see
  /// [CloudBackend.blockUser] / [CloudBackend.unblockUser]).
  Future<void> blockUser(String targetUid) =>
      _backend.blockUser(targetUid);

  Future<void> unblockUser(String targetUid) =>
      _backend.unblockUser(targetUid);

  /// v27.35 payout preferences (own prefs only, see
  /// [CloudBackend.updatePayoutPrefs]).
  Future<void> updatePayoutPrefs({
    required CloudPayoutMethod method,
    required String number,
    required String name,
  }) =>
      _backend.updatePayoutPrefs(
        method: method,
        number: number,
        name: name,
      );

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
  /// [now] is a test seam: production uses [DateTime.now]; tests pass
  /// a controllable clock to prove the retention filter drops docs
  /// that expire between queueing and flushing.
  CloudSyncService(this._backend, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final CloudBackend _backend;
  final DateTime Function() _now;

  /// Pending uploads: each entry is {'kind': 'summary'|'order',
  /// 'summary': CloudDaySummary} or {'kind': 'order', 'uid': ...,
  /// 'dateKey': ..., 'json': {...}}.
  final List<Map<String, dynamic>> _queue = [];

  List<Map<String, dynamic>> get pendingQueue => List.unmodifiable(_queue);

  bool get hasPending => _queue.isNotEmpty;

  /// Queue a day-summary upload (uploads immediately when online).
  ///
  /// v27.35 retention: a summary old enough to have expired (its date
  /// + 21 days reached) is DROPPED, never queued — uploading it would
  /// resurrect a detail doc TTL already deleted.
  Future<void> queueDaySummary(CloudDaySummary summary) async {
    if (isDetailExpired(summary.dateKey, _now())) return;
    try {
      await _backend.saveDaySummary(summary);
    } catch (_) {
      _queue.add({'kind': 'summary', 'summary': summary});
    }
  }

  /// Queue a raw order-record upload (uploads immediately when online).
  /// Same retention drop as [queueDaySummary].
  Future<void> queueOrderRecord(
    String uid,
    String dateKey,
    Map<String, dynamic> json,
  ) async {
    if (isDetailExpired(dateKey, _now())) return;
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
  ///
  /// v27.35 retention: an entry that expired WHILE queued (its date
  /// crossed date + 21 days since queueing) is dropped, not uploaded
  /// — a queued upload must never resurrect a TTL-deleted doc.
  Future<int> flushQueue() async {
    var uploaded = 0;
    final remaining = <Map<String, dynamic>>[];
    for (final entry in _queue) {
      final dateKey = entry['kind'] == 'summary'
          ? (entry['summary'] as CloudDaySummary).dateKey
          : entry['dateKey'] as String;
      if (isDetailExpired(dateKey, _now())) continue;
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
    // v27.35 retention: expired local detail docs are never uploaded
    // (they would be TTL-deleted immediately anyway, and uploading
    // them could resurrect docs TTL already deleted). Their weeks'
    // totals are preserved separately by the sign-in backfill, which
    // builds rollups from the local data itself.
    final now = _now();
    for (final summary in localSummaries) {
      if (isDetailExpired(summary.dateKey, now)) continue;
      await _backend.saveDaySummary(summary);
    }
    for (final order in localOrders) {
      final dateKey = order['dateKey'] as String?;
      if (dateKey != null && !isDetailExpired(dateKey, now)) {
        await _backend.saveOrderRecord(uid, dateKey, order);
      }
    }
    await markMigrated(uid);
    return true;
  }

  /// v27.35 retention backfill, run on sign-in (best-effort,
  /// fire-and-forget from the account screen — it never blocks
  /// sign-in, and re-running it is idempotent).
  ///
  /// For every week present in the device's local summaries, in this
  /// strict order per week:
  ///   1. Build the week's permanent rollup from the UNION of local
  ///      summaries and the cloud's summaries for that week (cloud
  ///      wins on a shared dateKey, so a manager edit is never
  ///      overwritten by stale local data) plus the week's cloud
  ///      adjustments, folded into the stored total.
  ///   2. Write the rollup.
  ///   3. ONLY THEN stamp expireAt on that week's detail docs
  ///      (day summaries, order records, adjustments) that exist in
  ///      the cloud. A week with no rollup never gets stamped, so
  ///      TTL can never delete details for an un-rolled-up week.
  ///
  /// Identity docs are never touched: this writes weekRollups and
  /// expireAt stamps on work data only.
  Future<void> backfillWeekRollups({
    required String uid,
    required List<CloudDaySummary> localSummaries,
  }) async {
    final weeks = <String, List<CloudDaySummary>>{};
    for (final summary in localSummaries) {
      weeks.putIfAbsent(
        weekKeyForDateKey(summary.dateKey),
        () => [],
      ).add(summary);
    }
    final allAdjustments = await _backend.listAdjustments(uid);
    for (final entry in weeks.entries) {
      final weekKey = entry.key;
      final cloud = <CloudDaySummary>[];
      for (final dateKey in weekDateKeys(weekKey)) {
        final summary = await _backend.fetchDaySummary(uid, dateKey);
        if (summary != null) cloud.add(summary);
      }
      final merged = mergeDaySummaries(local: entry.value, cloud: cloud);
      final weekAdjustments = adjustmentsForWeek(allAdjustments, weekKey);
      final rollup = buildWeekRollup(
        uid: uid,
        weekKey: weekKey,
        summaries: merged,
        adjustments: weekAdjustments,
        updatedAtMillis: _now().millisecondsSinceEpoch,
      );
      // Rollup FIRST...
      await _backend.saveWeekRollup(rollup);
      // ...then stamp expiry on this week's existing detail docs.
      for (final summary in merged) {
        await _backend.stampDetailExpiry(uid, summary.dateKey);
      }
      for (final adjustment in weekAdjustments) {
        await _backend.stampAdjustmentExpiry(
          uid,
          adjustment.id,
          weekKey,
        );
      }
    }
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
