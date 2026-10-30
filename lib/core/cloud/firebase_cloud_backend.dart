// v27.33 — Real Firebase implementation of [CloudBackend].
//
// Instantiated by [initCloudBackend] when Firebase initializes with
// the project's real options. All role rules from the interface
// are enforced here AND in firestore.rules — the rules are the real
// enforcement; these client checks exist to fail fast with clear
// errors, never as the security boundary.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'cloud_backend.dart';
import 'cloud_types.dart';
import 'google_sign_in_client.dart';
import 'adjustment_logic.dart';
import 'login_identifier.dart';
import 'retention_logic.dart';

class FirebaseCloudBackend implements CloudBackend {
  FirebaseCloudBackend({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignInClient? googleClient,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _google = googleClient ?? PluginGoogleSignInClient();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignInClient _google;

  CloudAccount? _account;

  @override
  CloudAccount? get currentAccount => _account;

  DocumentReference<Map<String, dynamic>> _profileRef(String uid) =>
      _firestore.collection('users').doc(uid);

  /// Owner or manager — throws [CloudDenied] otherwise. Rules enforce
  /// the same server-side; this fails fast with a clear error.
  void _requireOwnerOrManager(String uid) {
    final me = _account;
    if (me == null) throw const CloudDenied('not signed in');
    if (me.uid != uid && !me.isManager) {
      throw const CloudDenied('not owner or manager');
    }
    _requireUsableAccount();
  }

  /// Forced-change gate (admin first-login rule): an account with
  /// mustChangePassword may not read or write ANY data — only
  /// fetchProfile (display) and changePassword (the way out) work.
  /// The UI gate is primary; this is defence in depth.
  /// A blocked account (v27.35 blacklist) may not do anything either:
  /// the sign-in/restore gates normally prevent a blocked account
  /// from ever holding a session, so this is defence in depth for a
  /// session that was live when the block landed (the Firestore rules
  /// deny its reads/writes server-side regardless).
  void _requireUsableAccount() {
    if (_account?.mustChangePassword == true) {
      throw const CloudDenied('password change required');
    }
    if (_account?.blocked == true) {
      throw const CloudDenied('account blocked');
    }
  }

  /// v27.35 blacklist gate: a blocked profile ends the session
  /// immediately and the caller surfaces the blocked message. Used by
  /// every entry point that adopts a fetched profile (sign-in,
  /// Google sign-in/sign-up, session restore) — never adopt a
  /// blocked profile as the signed-in account.
  Future<Never> _signOutAndThrowBlocked() async {
    await signOut();
    throw const CloudAccountBlocked();
  }

  /// Manager-edit stamp for a doc owned by someone else. Returns the
  /// data unchanged for own edits and for non-managers.
  Map<String, dynamic> _stampIfManagerEdit(
    String ownerUid,
    Map<String, dynamic> data,
  ) {
    final me = _account;
    if (me == null || !me.isManager || me.uid == ownerUid) return data;
    return {
      ...data,
      'editedByManagerUid': me.uid,
      'editedByManagerAtMillis': DateTime.now().millisecondsSinceEpoch,
    };
  }

  @override
  Future<CloudAccount> signUp({
    required String email,
    required String password,
    required String username,
    String phone = '',
  }) async {
    // Uniqueness BEFORE creating the Auth user, so a taken username
    // or phone never leaves an orphan Auth account behind. (A race
    // between two simultaneous sign-ups is still possible client-side;
    // the Firestore rules' create-only guard is the backstop: the
    // second mapping write is rejected server-side.)
    final usernameKey = usernameLookupKey(username);
    if (usernameKey.isNotEmpty) {
      final taken = await _firestore
          .collection('usernames')
          .doc(usernameKey)
          .get();
      if (taken.exists) throw Exception('username taken');
    }
    final normalizedPhone = phone.isEmpty ? '' : normalizeEgyptPhone(phone);
    final phoneKey = normalizedPhone.isEmpty
        ? ''
        : phoneLookupKey(normalizedPhone);
    if (phoneKey.isNotEmpty) {
      final taken =
          await _firestore.collection('phones').doc(phoneKey).get();
      if (taken.exists) throw Exception('phone taken');
    }
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = cred.user!.uid;
    // New accounts are ALWAYS drivers. Role upgrades happen only via
    // [changeRole] (manager-only) or a manual console edit for the
    // very first manager.
    final account = CloudAccount(
      uid: uid,
      email: email,
      username: username,
      role: CloudRole.driver,
      phone: normalizedPhone,
    );
    await _profileRef(uid).set(account.toJson());
    if (usernameKey.isNotEmpty) {
      await _firestore.collection('usernames').doc(usernameKey).set({
        'email': email,
        'uid': uid,
      });
    }
    if (phoneKey.isNotEmpty) {
      await _firestore.collection('phones').doc(phoneKey).set({
        'email': email,
        'uid': uid,
      });
    }
    await _firestore
        .collection('emailUsernames')
        .doc(emailLookupKey(email))
        .set({'username': username, 'uid': uid});
    _account = account;
    return account;
  }

  @override
  Future<String?> resolveLoginEmail(String identifier) async {
    final trimmed = identifier.trim();
    if (trimmed.contains('@')) return trimmed;
    if (looksLikePhone(trimmed)) {
      final snap = await _firestore
          .collection('phones')
          .doc(phoneLookupKey(trimmed))
          .get();
      return snap.data()?['email'] as String?;
    }
    final snap = await _firestore
        .collection('usernames')
        .doc(usernameLookupKey(trimmed))
        .get();
    return snap.data()?['email'] as String?;
  }

  @override
  Future<CloudAccount> changeUsername(String newUsername) async {
    final me = _account;
    if (me == null) throw const CloudDenied('not signed in');
    _requireUsableAccount();
    final newKey = usernameLookupKey(newUsername);
    if (newKey.isEmpty) throw Exception('username required');
    final oldKey = usernameLookupKey(me.username);
    if (newKey == oldKey) return me; // Same username, any case: no-op.
    final taken =
        await _firestore.collection('usernames').doc(newKey).get();
    // v27.35: an orphaned mapping left by a failed earlier attempt
    // (same uid) is the caller's own — treat it as available, not
    // taken. Only a mapping owned by someone else blocks the name.
    // The emailUsernames write below uses set(), which tolerates a
    // missing doc the same way.
    if (taken.exists && taken.data()?['uid'] != me.uid) {
      throw Exception('username taken');
    }
    // Create new mapping first, then remove the old one, then update
    // the profile — so the old username stops resolving only after
    // the new one is live.
    await _firestore.collection('usernames').doc(newKey).set({
      'email': me.email,
      'uid': me.uid,
    });
    if (oldKey.isNotEmpty) {
      // v27.35: a console-created account never got a lookup doc, so
      // deleting a NON-EXISTENT mapping is denied by the rules
      // (resource.data.uid fails on a null resource). Get first and
      // skip silently when it is missing.
      final old =
          await _firestore.collection('usernames').doc(oldKey).get();
      if (old.exists) {
        await _firestore.collection('usernames').doc(oldKey).delete();
      }
    }
    final updated = CloudAccount(
      uid: me.uid,
      email: me.email,
      username: newUsername.trim(),
      role: me.role,
      phone: me.phone,
      blocked: me.blocked,
      blockedAt: me.blockedAt,
      blockedBy: me.blockedBy,
    );
    await _profileRef(me.uid).set(updated.toJson());
    await _firestore
        .collection('emailUsernames')
        .doc(emailLookupKey(me.email))
        .set({'username': updated.username, 'uid': me.uid});
    _account = updated;
    return updated;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final me = _account;
    final user = _auth.currentUser;
    if (me == null || user == null) {
      throw const CloudDenied('not signed in');
    }
    // Firebase requires recent authentication for a password change:
    // re-authenticate with the CURRENT password, then update. The
    // old password stops working immediately after this call.
    final credential = EmailAuthProvider.credential(
      email: me.email,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
    // A successful change clears a forced-change flag on the profile
    // (admin first-login rule): the account is usable from now on.
    // The flag lives on the user doc, never in Auth — and clearing
    // it is an owner edit of the caller's OWN doc, always allowed.
    try {
      await _profileRef(me.uid).set(
        {'mustChangePassword': false},
        SetOptions(merge: true),
      );
    } catch (_) {
      // Profile doc may not exist yet (console-created Auth user
      // whose doc was never written); the flag defaults to false on
      // read, so a missing doc is already unflagged.
    }
    if (me.mustChangePassword) {
      _account = CloudAccount(
        uid: me.uid,
        email: me.email,
        username: me.username,
        role: me.role,
        phone: me.phone,
      );
    }
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  @override
  Future<String?> lookupUsernameByEmail(String email) async {
    final snap = await _firestore
        .collection('emailUsernames')
        .doc(emailLookupKey(email))
        .get();
    return snap.data()?['username'] as String?;
  }

  @override
  Future<bool> isUsernameAvailable(String username) async {
    final key = usernameLookupKey(username);
    if (key.isEmpty) return false;
    final snap =
        await _firestore.collection('usernames').doc(key).get();
    return !snap.exists;
  }

  @override
  Future<CloudAccount?> restoreSession() async {
    // Firebase Auth persistence is native: the SDK restores the user
    // from its stored refresh token across restarts. Nothing here
    // signs out, clears, or times out — only an explicit sign-out
    // (which calls _auth.signOut) ends the session.
    final user = _auth.currentUser;
    if (user == null) return null;
    final profile = await fetchProfile(user.uid);
    // v27.35 blacklist gate: a blocked profile never becomes a
    // restored session — the session is signed out on the spot.
    if (profile?.blocked == true) {
      await _signOutAndThrowBlocked();
    }
    final account = profile ??
        CloudAccount(
          uid: user.uid,
          email: user.email ?? '',
          username: user.displayName ?? '',
          role: CloudRole.driver,
        );
    _account = account;
    return account;
  }

  @override
  Future<CloudAccount> signIn({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = cred.user!.uid;
    final profile = await fetchProfile(uid);
    // v27.35 blacklist gate (email/password path).
    if (profile?.blocked == true) {
      await _signOutAndThrowBlocked();
    }
    final account = profile ??
        CloudAccount(uid: uid, email: email, username: '', role: CloudRole.driver);
    _account = account;
    return account;
  }

  @override
  Future<CloudAccount?> signInWithGoogle() async {
    // Android prerequisite (NOT code): the release SHA-1 fingerprint
    // must be registered for this Android app in the Firebase console,
    // or Google sign-in fails with DEVELOPER_ERROR (ApiException 10).
    // The release APK is signed in CI from a CI-secret keystore, so
    // the SHA-1 to register is that keystore's — see the build report.
    final tokens = await _google.signIn();
    if (tokens == null) return null; // User cancelled the picker.
    final credential = GoogleAuthProvider.credential(
      idToken: tokens.idToken,
      accessToken: tokens.accessToken,
    );
    final cred = await _auth.signInWithCredential(credential);
    final user = cred.user!;
    final uid = user.uid;
    // Same doc structure as email sign-up. A first-time Google user
    // gets a driver doc with their Google display name as username;
    // a returning Google user loads their existing doc (and its role
    // — manager gating is identical for Google accounts).
    // NO auto-linking: if this email already has an Email/Password
    // account, signInWithCredential throws
    // account-exists-with-different-credential instead of merging —
    // the driver must then use their original sign-in method.
    final existing = await fetchProfile(uid);
    // v27.35 blacklist gate (Google sign-in path): a blocked Google
    // user is gated, never treated as a returning account.
    if (existing?.blocked == true) {
      await _signOutAndThrowBlocked();
    }
    final email = user.email ?? '';
    final account = existing ??
        CloudAccount(
          uid: uid,
          email: email,
          username: user.displayName ?? '',
          role: CloudRole.driver,
        );
    if (existing == null) {
      await _profileRef(uid).set(account.toJson());
      // Best-effort login mappings for Google users (create-if-absent
      // only: never overwrite another account's mapping — a Google
      // display name may collide with an existing username).
      final gUsername = account.username.trim();
      if (gUsername.isNotEmpty) {
        final key = usernameLookupKey(gUsername);
        final doc =
            await _firestore.collection('usernames').doc(key).get();
        if (!doc.exists) {
          await _firestore.collection('usernames').doc(key).set({
            'email': email,
            'uid': uid,
          });
        }
      }
      if (email.isNotEmpty) {
        final key = emailLookupKey(email);
        final doc = await _firestore
            .collection('emailUsernames')
            .doc(key)
            .get();
        if (!doc.exists) {
          await _firestore
              .collection('emailUsernames')
              .doc(key)
              .set({'username': account.username, 'uid': uid});
        }
      }
    }
    _account = account;
    return account;
  }

  @override
  Future<bool> isPhoneAvailable(String phone) async {
    final normalized = normalizeEgyptPhone(phone);
    if (normalized.isEmpty) return false;
    final snap = await _firestore
        .collection('phones')
        .doc(phoneLookupKey(normalized))
        .get();
    return !snap.exists;
  }

  @override
  Future<GoogleSignUpStart> beginGoogleSignUp() async {
    // Same Android prerequisite as signInWithGoogle: the release
    // SHA-1 must be registered in the Firebase console, or this
    // fails with DEVELOPER_ERROR (ApiException 10) before any
    // profile work happens.
    final tokens = await _google.signIn();
    if (tokens == null) return const GoogleSignUpStart.cancelled();
    final credential = GoogleAuthProvider.credential(
      idToken: tokens.idToken,
      accessToken: tokens.accessToken,
    );
    final cred = await _auth.signInWithCredential(credential);
    final user = cred.user!;
    // Deliberately NO profile creation here: the completion form
    // owns username + phone, so a first-time Google user has no
    // half-made driver doc with a possibly colliding display name.
    final existing = await fetchProfile(user.uid);
    // v27.35 blacklist gate (Google sign-up path): a blocked Google
    // user is gated, never returned as an existing account.
    if (existing?.blocked == true) {
      await _signOutAndThrowBlocked();
    }
    if (existing != null) {
      _account = existing;
      return GoogleSignUpStart.existing(existing);
    }
    return GoogleSignUpStart.needsCompletion(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? '',
    );
  }

  @override
  Future<CloudAccount> completeGoogleSignUp({
    required String username,
    required String phone,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const CloudDenied('not signed in');
    final uid = user.uid;
    // Completed twice (or profile created meanwhile): return the
    // existing account instead of writing a second profile.
    final existing = await fetchProfile(uid);
    // v27.35 blacklist gate (Google completion path).
    if (existing?.blocked == true) {
      await _signOutAndThrowBlocked();
    }
    if (existing != null) {
      _account = existing;
      return existing;
    }
    // Same uniqueness guards as email sign-up, so a taken username
    // or phone never leaves an orphan Auth account behind — here
    // the Auth user already exists, so a taken value must fail
    // BEFORE any profile or mapping write.
    final usernameKey = usernameLookupKey(username);
    if (usernameKey.isNotEmpty) {
      final taken = await _firestore
          .collection('usernames')
          .doc(usernameKey)
          .get();
      if (taken.exists) throw Exception('username taken');
    }
    final normalizedPhone = phone.isEmpty ? '' : normalizeEgyptPhone(phone);
    final phoneKey =
        normalizedPhone.isEmpty ? '' : phoneLookupKey(normalizedPhone);
    if (phoneKey.isNotEmpty) {
      final taken =
          await _firestore.collection('phones').doc(phoneKey).get();
      if (taken.exists) throw Exception('phone taken');
    }
    final email = user.email ?? '';
    final account = CloudAccount(
      uid: uid,
      email: email,
      username: username.trim(),
      role: CloudRole.driver,
      phone: normalizedPhone,
    );
    // Profile first (owner create as driver — allowed by the rules),
    // then the login mappings. A mapping write rejected by the
    // create-only rules (lost race) surfaces as a taken error.
    try {
      await _profileRef(uid).set(account.toJson());
      if (usernameKey.isNotEmpty) {
        await _firestore.collection('usernames').doc(usernameKey).set({
          'email': email,
          'uid': uid,
        });
      }
      if (phoneKey.isNotEmpty) {
        await _firestore.collection('phones').doc(phoneKey).set({
          'email': email,
          'uid': uid,
        });
      }
      if (email.isNotEmpty) {
        await _firestore
            .collection('emailUsernames')
            .doc(emailLookupKey(email))
            .set({'username': account.username, 'uid': uid});
      }
    } catch (e) {
      // Lost a mapping race after the pre-checks: re-read to report
      // WHICH value is taken, in the same terms as email sign-up.
      if (usernameKey.isNotEmpty) {
        final taken = await _firestore
            .collection('usernames')
            .doc(usernameKey)
            .get();
        final owner = taken.data()?['uid'] as String?;
        if (taken.exists && owner != uid) {
          throw Exception('username taken');
        }
      }
      if (phoneKey.isNotEmpty) {
        final taken = await _firestore
            .collection('phones')
            .doc(phoneKey)
            .get();
        final owner = taken.data()?['uid'] as String?;
        if (taken.exists && owner != uid) {
          throw Exception('phone taken');
        }
      }
      rethrow;
    }
    _account = account;
    return account;
  }

  @override
  Future<void> cancelGoogleSignUp() async {
    // Ends the half-started session (Auth + Google picker state)
    // so abandoning the completion form leaves nothing signed in.
    await signOut();
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    // Best effort: also clear the Google session so the next
    // "Sign in with Google" tap re-prompts instead of silently
    // reusing the previous Google account.
    try {
      await _google.signOut();
    } catch (_) {}
    _account = null;
  }

  @override
  Future<CloudAccount?> fetchProfile(String uid) async {
    final snap = await _profileRef(uid).get();
    final data = snap.data();
    if (data == null) return null;
    return CloudAccount.fromJson(uid, data);
  }

  @override
  Future<void> saveProfile(CloudAccount account) async {
    final me = _account;
    if (me == null) throw const CloudDenied('not signed in');
    _requireUsableAccount();
    // A driver may only write their own profile; a manager may write
    // any other user's profile. Nobody writes a profile they do not
    // own unless they are a manager.
    if (me.uid != account.uid && !me.isManager) {
      throw const CloudDenied('not owner or manager');
    }
    // Nobody changes their own role from the client, and only a
    // manager changes anyone's role. Firestore rules enforce this
    // server-side regardless of what the client does.
    final existing = await fetchProfile(account.uid);
    // v27.35 blacklist: a blocked profile is terminal through this
    // path — no edit (role, name, anything) may overwrite it and
    // silently clear the block. Unblock has its own write path.
    if (existing != null && existing.blocked) {
      throw const CloudDenied('blocked account');
    }
    if (existing != null && existing.role != account.role) {
      if (me.uid == account.uid) {
        throw const CloudDenied('cannot change own role');
      }
      if (!me.isManager) {
        throw const CloudDenied('only a manager changes roles');
      }
    }
    await _profileRef(account.uid)
        .set(_stampIfManagerEdit(account.uid, account.toJson()));
    if (account.uid == me.uid) _account = account;
  }

  /// Shared guard for the blacklist actions: the caller must be a
  /// usable manager acting on someone else's existing driver account
  /// (managers are never blocked/unblocked from the app — demote
  /// first). Returns the target profile for the caller to check.
  Future<CloudAccount> _requireBlockableTarget(String targetUid) async {
    final me = _account;
    if (me == null) throw const CloudDenied('not signed in');
    _requireUsableAccount();
    if (!me.isManager) {
      throw const CloudDenied('only a manager blocks drivers');
    }
    if (me.uid == targetUid) {
      throw const CloudDenied('cannot block own account');
    }
    final target = await fetchProfile(targetUid);
    if (target == null) throw const CloudDenied('unknown user');
    if (target.isManager) {
      throw const CloudDenied('demote to driver first');
    }
    return target;
  }

  @override
  Future<void> blockUser(String targetUid) async {
    final target = await _requireBlockableTarget(targetUid);
    if (target.blocked) throw const CloudDenied('already blocked');
    // Flag-only write (merge): the driver's orders, summaries,
    // adjustments, rollups and login lookups are all KEPT — this is
    // a reversible block, not a deletion.
    await _profileRef(targetUid).set({
      'blocked': true,
      'blockedAt': DateTime.now().millisecondsSinceEpoch,
      'blockedBy': _account!.uid,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> unblockUser(String targetUid) async {
    final target = await _requireBlockableTarget(targetUid);
    if (!target.blocked) throw const CloudDenied('not blocked');
    await _profileRef(targetUid).set({
      'blocked': false,
      'blockedAt': 0,
      'blockedBy': '',
    }, SetOptions(merge: true));
  }

  @override
  Future<void> updatePayoutPrefs({
    required CloudPayoutMethod method,
    required String number,
    required String name,
  }) async {
    final me = _account;
    if (me == null) throw const CloudDenied('not signed in');
    _requireUsableAccount();
    final error = validatePayoutPrefs(
      method: method,
      number: number,
      name: name,
    );
    if (error != null) throw Exception(error);
    // Flag-only merge write: role, blocked flags and every other
    // profile field are untouched (the rules' owner branch requires
    // the role to stay unchanged, which a merge satisfies).
    final storedNumber = normalizePayoutNumber(method, number);
    // Manual and unset carry no transfer details — a stale number
    // or name must never linger on those rows.
    final storedName =
        method == CloudPayoutMethod.manual ||
                method == CloudPayoutMethod.none
            ? ''
            : name.trim();
    await _profileRef(me.uid).set({
      'payoutMethod': method.name,
      'payoutNumber': storedNumber,
      'payoutName': storedName,
    }, SetOptions(merge: true));
    _account = CloudAccount(
      uid: me.uid,
      email: me.email,
      username: me.username,
      role: me.role,
      phone: me.phone,
      mustChangePassword: me.mustChangePassword,
      blocked: me.blocked,
      blockedAt: me.blockedAt,
      blockedBy: me.blockedBy,
      payoutMethod: method,
      payoutNumber: storedNumber,
      payoutName: storedName,
    );
  }

  // v27.35 retention — rollup refresh after a write, best-effort:
  // the user's day/adjustment write itself must NEVER fail because
  // the rollup refresh failed (offline, rules, anything). A missed
  // refresh is healed by the next write or the sign-in backfill,
  // and a missing rollup only ever delays expiry — it can never
  // corrupt a total, because TTL only deletes docs that carry an
  // expireAt stamped after their week's rollup was written (see
  // retention_logic.dart for the ordering invariant).
  Future<void> _refreshRollupBestEffort(String uid, String weekKey) async {
    try {
      await refreshWeekRollup(uid, weekKey);
    } catch (_) {}
  }

  CollectionReference<Map<String, dynamic>> _weekRollupsRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('weekRollups');

  @override
  Future<void> saveDaySummary(CloudDaySummary summary) async {
    _requireOwnerOrManager(summary.uid);
    // v27.35 retention: every summary doc carries its TTL expiry
    // (its date + 21 days). The rollup refresh below runs in the
    // same write — for current data expireAt is in the future, so
    // TTL cannot act before the rollup exists; for an old day edited
    // by a manager, TTL's up-to-24h lag covers the same-second
    // refresh. The explicit backfill keeps the strict order
    // (rollup first, then stamp) for pre-v27.35 weeks.
    final data = _stampIfManagerEdit(summary.uid, summary.toJson())
      ..['expireAt'] =
          Timestamp.fromDate(detailExpireAtDate(summary.dateKey));
    await _firestore
        .collection('users')
        .doc(summary.uid)
        .collection('summaries')
        .doc(summary.dateKey)
        .set(data);
    await _refreshRollupBestEffort(
      summary.uid,
      weekKeyForDateKey(summary.dateKey),
    );
  }

  @override
  Future<CloudDaySummary?> fetchDaySummary(String uid, String dateKey) async {
    _requireUsableAccount();
    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('summaries')
        .doc(dateKey)
        .get();
    final data = snap.data();
    if (data == null) return null;
    return CloudDaySummary.fromJson(uid, data);
  }

  @override
  Future<void> saveOrderRecord(
    String uid,
    String dateKey,
    Map<String, dynamic> json,
  ) async {
    _requireOwnerOrManager(uid);
    // v27.35 retention: raw order docs carry the same TTL expiry.
    // No rollup refresh here — order records do not change salary;
    // the summary write for the same day refreshes the rollup.
    final data = _stampIfManagerEdit(uid, Map<String, dynamic>.from(json))
      ..['expireAt'] = Timestamp.fromDate(detailExpireAtDate(dateKey));
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('orders')
        .doc(dateKey)
        .set(data);
  }

  @override
  Future<void> deleteUserDay(String uid, String dateKey) async {
    _requireOwnerOrManager(uid);
    final userRef = _firestore.collection('users').doc(uid);
    await userRef.collection('summaries').doc(dateKey).delete();
    await userRef.collection('orders').doc(dateKey).delete();
    // The week's totals dropped with the day: refresh its rollup
    // (a week whose days are all deleted keeps a zero rollup — the
    // permanent record of that week — never a deleted rollup).
    await _refreshRollupBestEffort(uid, weekKeyForDateKey(dateKey));
  }

  CollectionReference<Map<String, dynamic>> _adjustmentsRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('adjustments');

  /// Manager-only write guard for adjustments, shared by save/delete.
  /// A manager also cannot adjust his own pay (same abuse vector as
  /// a driver granting himself a bonus).
  void _requireManagerAdjustingOther(String uid) {
    final me = _account;
    if (me == null) throw const CloudDenied('not signed in');
    _requireUsableAccount();
    if (!me.isManager) {
      throw const CloudDenied('only a manager writes adjustments');
    }
    if (me.uid == uid) {
      throw const CloudDenied('a manager cannot adjust his own pay');
    }
  }

  @override
  Future<CloudAdjustment> saveAdjustment(CloudAdjustment adjustment) async {
    _requireManagerAdjustingOther(adjustment.uid);
    final error = validateAdjustment(
      amount: adjustment.amount,
      reason: adjustment.reason,
    );
    if (error != null) throw Exception(error);
    final ref = adjustment.id.isEmpty
        ? _adjustmentsRef(adjustment.uid).doc()
        : _adjustmentsRef(adjustment.uid).doc(adjustment.id);
    // createdBy is always the calling manager — never trust a
    // client-supplied stamp.
    final data = adjustment.toJson()..['createdBy'] = _account!.uid;
    // v27.35 retention: adjustment docs expire at week-start + 21
    // days. The rollup refresh below folds this adjustment into the
    // week's stored total in the same write, so the total survives
    // after this doc TTL-expires.
    data['expireAt'] =
        Timestamp.fromDate(adjustmentExpireAtDate(adjustment.weekKey));
    await ref.set(data);
    final saved = CloudAdjustment.fromJson(ref.id, adjustment.uid, data);
    await _refreshRollupBestEffort(adjustment.uid, adjustment.weekKey);
    return saved;
  }

  @override
  Future<void> deleteAdjustment(String uid, String adjustmentId) async {
    _requireManagerAdjustingOther(uid);
    // The week's rollup must drop this adjustment: read its week
    // before deleting (a missing doc simply skips the refresh).
    String? weekKey;
    try {
      final snap = await _adjustmentsRef(uid).doc(adjustmentId).get();
      weekKey = snap.data()?['weekKey'] as String?;
    } catch (_) {}
    await _adjustmentsRef(uid).doc(adjustmentId).delete();
    if (weekKey != null && weekKey.isNotEmpty) {
      await _refreshRollupBestEffort(uid, weekKey);
    }
  }

  @override
  Future<void> saveWeekRollup(CloudWeekRollup rollup) async {
    _requireOwnerOrManager(rollup.uid);
    // No expireAt, ever: weekRollups is the permanent record and
    // has no TTL policy. No manager stamp either — rollups are
    // computed from summaries + adjustments, not hand-edited.
    await _weekRollupsRef(rollup.uid).doc(rollup.weekKey).set(
          rollup.toJson(),
        );
  }

  @override
  Future<CloudWeekRollup?> fetchWeekRollup(
    String uid,
    String weekKey,
  ) async {
    _requireOwnerOrManager(uid);
    final snap = await _weekRollupsRef(uid).doc(weekKey).get();
    final data = snap.data();
    if (data == null) return null;
    return CloudWeekRollup.fromJson(uid, weekKey, data);
  }

  @override
  Future<void> refreshWeekRollup(String uid, String weekKey) async {
    _requireOwnerOrManager(uid);
    final summaries = <CloudDaySummary>[];
    for (final dateKey in weekDateKeys(weekKey)) {
      final summary = await fetchDaySummary(uid, dateKey);
      if (summary != null) summaries.add(summary);
    }
    final adjustments = adjustmentsForWeek(
      await listAdjustments(uid),
      weekKey,
    );
    final rollup = buildWeekRollup(
      uid: uid,
      weekKey: weekKey,
      summaries: summaries,
      adjustments: adjustments,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    await saveWeekRollup(rollup);
  }

  @override
  Future<void> stampDetailExpiry(String uid, String dateKey) async {
    _requireOwnerOrManager(uid);
    // Merge-set on EXISTING docs only: a missing doc is left alone,
    // so stamping never creates a detail doc out of nothing (and
    // never resurrects one TTL already deleted — the caller only
    // stamps weeks whose rollup was just written, and the sync
    // filter never uploads docs old enough to have expired).
    final expireAt = Timestamp.fromDate(detailExpireAtDate(dateKey));
    final userRef = _firestore.collection('users').doc(uid);
    final summarySnap =
        await userRef.collection('summaries').doc(dateKey).get();
    if (summarySnap.exists) {
      await userRef.collection('summaries').doc(dateKey).set(
        {'expireAt': expireAt},
        SetOptions(merge: true),
      );
    }
    final orderSnap = await userRef.collection('orders').doc(dateKey).get();
    if (orderSnap.exists) {
      await userRef.collection('orders').doc(dateKey).set(
        {'expireAt': expireAt},
        SetOptions(merge: true),
      );
    }
  }

  @override
  Future<void> stampAdjustmentExpiry(
    String uid,
    String adjustmentId,
    String weekKey,
  ) async {
    _requireOwnerOrManager(uid);
    final ref = _adjustmentsRef(uid).doc(adjustmentId);
    final snap = await ref.get();
    if (!snap.exists) return;
    await ref.set(
      {'expireAt': Timestamp.fromDate(adjustmentExpireAtDate(weekKey))},
      SetOptions(merge: true),
    );
  }

  @override
  Future<List<CloudAdjustment>> listAdjustments(String uid) async {
    _requireOwnerOrManager(uid);
    final snap = await _adjustmentsRef(uid).get();
    return [
      for (final doc in snap.docs)
        CloudAdjustment.fromJson(doc.id, uid, doc.data()),
    ];
  }

  @override
  Future<Map<String, dynamic>?> fetchOrderRecord(
    String uid,
    String dateKey,
  ) async {
    _requireUsableAccount();
    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('orders')
        .doc(dateKey)
        .get();
    return snap.data();
  }

  // v27.36 live sync — per-user subcollection snapshots (never a
  // collection-group query: group queries are rejected under these
  // rules even for managers). Reads follow the same guards as the
  // matching .get() calls; a denied listener surfaces its error on
  // the stream for the caller to report loudly.
  @override
  Stream<List<CloudDaySummary>> watchUserSummaries(String uid) {
    _requireUsableAccount();
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('summaries')
        .snapshots()
        .map(
          (snap) => [
            for (final doc in snap.docs)
              CloudDaySummary.fromJson(uid, doc.data()),
          ],
        );
  }

  @override
  Stream<Map<String, Map<String, dynamic>>> watchUserOrders(String uid) {
    _requireUsableAccount();
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('orders')
        .snapshots()
        .map(
          (snap) => {
            for (final doc in snap.docs) doc.id: doc.data(),
          },
        );
  }

  @override
  Stream<List<CloudAdjustment>> watchUserAdjustments(String uid) {
    _requireUsableAccount();
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('adjustments')
        .snapshots()
        .map(
          (snap) => [
            for (final doc in snap.docs)
              CloudAdjustment.fromJson(doc.id, uid, doc.data()),
          ],
        );
  }

  @override
  Stream<List<CloudAccount>> watchUsers() {
    _requireUsableAccount();
    final me = _account;
    if (me == null || !me.isManager) {
      throw const CloudDenied('manager only');
    }
    return _firestore.collection('users').snapshots().map(
          (snap) => [
            for (final doc in snap.docs)
              CloudAccount.fromJson(doc.id, doc.data()),
          ],
        );
  }

  @override
  Future<List<CloudAccount>> listUsers() async {
    _requireUsableAccount();
    final me = _account;
    if (me == null || !me.isManager) {
      throw const CloudDenied('manager only');
    }
    final snap = await _firestore.collection('users').get();
    return [
      for (final doc in snap.docs)
        CloudAccount.fromJson(doc.id, doc.data()),
    ];
  }

  @override
  Future<List<CloudDaySummary>> listDaySummaries(String dateKey) async {
    final me = _account;
    if (me == null || !me.isManager) {
      throw const CloudDenied('manager only');
    }
    final users = await listUsers();
    final out = <CloudDaySummary>[];
    for (final user in users) {
      final summary = await fetchDaySummary(user.uid, dateKey);
      if (summary != null) out.add(summary);
    }
    return out;
  }

  @override
  Future<Map<String, List<CloudDaySummary>>> listSummariesForDays(
    List<String> dateKeys,
  ) async {
    final me = _account;
    if (me == null || !me.isManager) {
      throw const CloudDenied('manager only');
    }
    final users = await listUsers();
    final out = {for (final d in dateKeys) d: <CloudDaySummary>[]};
    for (final user in users) {
      for (final dateKey in dateKeys) {
        final summary = await fetchDaySummary(user.uid, dateKey);
        if (summary != null) out[dateKey]!.add(summary);
      }
    }
    return out;
  }
}
