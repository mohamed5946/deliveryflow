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
  void _requireUsableAccount() {
    if (_account?.mustChangePassword == true) {
      throw const CloudDenied('password change required');
    }
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
    if (taken.exists) throw Exception('username taken');
    // Create new mapping first, then remove the old one, then update
    // the profile — so the old username stops resolving only after
    // the new one is live.
    await _firestore.collection('usernames').doc(newKey).set({
      'email': me.email,
      'uid': me.uid,
    });
    if (oldKey.isNotEmpty) {
      await _firestore.collection('usernames').doc(oldKey).delete();
    }
    final updated = CloudAccount(
      uid: me.uid,
      email: me.email,
      username: newUsername.trim(),
      role: me.role,
      phone: me.phone,
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

  @override
  Future<void> saveDaySummary(CloudDaySummary summary) async {
    _requireOwnerOrManager(summary.uid);
    await _firestore
        .collection('users')
        .doc(summary.uid)
        .collection('summaries')
        .doc(summary.dateKey)
        .set(_stampIfManagerEdit(summary.uid, summary.toJson()));
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
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('orders')
        .doc(dateKey)
        .set(_stampIfManagerEdit(uid, Map<String, dynamic>.from(json)));
  }

  @override
  Future<void> deleteUserDay(String uid, String dateKey) async {
    _requireOwnerOrManager(uid);
    final userRef = _firestore.collection('users').doc(uid);
    await userRef.collection('summaries').doc(dateKey).delete();
    await userRef.collection('orders').doc(dateKey).delete();
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
    await ref.set(data);
    return CloudAdjustment.fromJson(ref.id, adjustment.uid, data);
  }

  @override
  Future<void> deleteAdjustment(String uid, String adjustmentId) async {
    _requireManagerAdjustingOther(uid);
    await _adjustmentsRef(uid).doc(adjustmentId).delete();
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
