// v27.33 — Cloud backend interface.
//
// Every cloud operation in the app goes through this interface, never
// directly through Firebase classes. Production uses
// [FirebaseCloudBackend]; tests use an in-memory fake; an unconfigured
// app gets [NotConfiguredBackend], which fails loudly instead of
// pretending to sync.
//
// Data layout (Firestore):
//   users/{uid}                     — profile: email, username, role
//   users/{uid}/orders/{dateKey}    — raw day record (owner's detail)
//   users/{uid}/summaries/{dateKey} — one small summary doc per day
//     (the manager's read path — see CloudDaySummary).

import 'cloud_types.dart';

abstract class CloudBackend {
  /// Signed-in account, if any, as last observed by this backend.
  CloudAccount? get currentAccount;

  /// Create an account (email + password in Firebase Auth) and its
  /// user doc (email + username, role always `driver` at creation).
  /// The password is passed ONLY to Firebase Auth — it is never stored
  /// in Firestore, locally, or in any [CloudAccount].
  /// Sign-up also creates login lookup mappings (see
  /// login_identifier.dart): usernames/{lowercased username} and
  /// phones/{sha256(normalized phone)} → {email, uid}, plus
  /// emailUsernames/{sha256(email)} → {username, uid} for the
  /// username reminder. Username and phone must each be unique —
  /// throws when either is taken (case-insensitive for usernames).
  /// [phone] may be empty for legacy/test accounts; the UI sign-up
  /// form requires it.
  Future<CloudAccount> signUp({
    required String email,
    required String password,
    required String username,
    String phone = '',
  });

  /// Resolve a login identifier (username, phone, or email) to the
  /// account email for Firebase sign-in. Returns null when nothing
  /// matches. This is a single-document lookup, never a listing.
  Future<String?> resolveLoginEmail(String identifier);

  /// Live availability check for sign-up (single-doc read of the
  /// username mapping). True when the username is free.
  Future<bool> isUsernameAvailable(String username);

  /// Restore a persisted Firebase Auth session (app restart, phone
  /// reboot, background kill): returns the signed-in account when
  /// Firebase Auth still holds a session, else null. The fingerprint
  /// lock never clears this; only an explicit sign-out does.
  Future<CloudAccount?> restoreSession();

  /// Change the signed-in user's own username. Checks the new
  /// username is free (case-insensitive), removes the old username
  /// mapping, creates the new one, and updates the profile — so the
  /// old username stops resolving immediately. Throws when taken.
  /// Managers change their own username exactly the same way; there
  /// is no special backdoor.
  Future<CloudAccount> changeUsername(String newUsername);

  /// Change the signed-in user's own password: re-authenticates with
  /// [currentPassword] (Firebase requirement) then updates. The old
  /// password stops working immediately. Throws on wrong current
  /// password. A phone number alone NEVER authorizes this — the
  /// caller must be signed in and know the current password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Forgot flow v1: send Firebase's native password-reset email.
  /// Free, no SMS. Phone-OTP reset is NOT supported (it would need
  /// a backend function; see the build report).
  Future<void> sendPasswordReset(String email);

  /// Username reminder: given an account email, return its username
  /// (usernames are not secrets). Returns null when unknown.
  Future<String?> lookupUsernameByEmail(String email);

  /// Sign in with the account email + password.
  Future<CloudAccount> signIn({
    required String email,
    required String password,
  });

  /// Google sign-in (Firebase Auth GoogleAuthProvider credential).
  /// Creates/loads the SAME user-doc structure as email sign-up:
  /// users/{uid} profile (role defaults to driver), orders and daily
  /// summaries under the same UID. No auto-linking: a Google UID is
  /// distinct from an Email/Password UID even for the same email
  /// address (see google_sign_in_client.dart). Returns null when the
  /// user cancelled the Google picker.
  Future<CloudAccount?> signInWithGoogle();

  Future<void> signOut();

  /// Refresh the signed-in user's profile from users/{uid}.
  Future<CloudAccount?> fetchProfile(String uid);

  /// Write a profile doc. Implementations MUST reject role changes
  /// from non-managers and self-role changes; Firestore rules enforce
  /// the same server-side (defence in depth, not trust in the client).
  /// Manager edits of ANOTHER user's profile are allowed (data fields
  /// and role); a manager editing another user's doc stamps it as a
  /// manager edit. Passwords are NEVER part of a profile doc — they
  /// live only in Firebase Auth and are never readable or writable
  /// through Firestore by anyone, manager included.
  Future<void> saveProfile(CloudAccount account);

  /// Write one day's summary doc for [summary.uid]. Owner or manager.
  /// A manager writing another driver's doc stamps it with the
  /// manager-edit marker (see [CloudDaySummary.editedByManagerUid]).
  Future<void> saveDaySummary(CloudDaySummary summary);

  Future<CloudDaySummary?> fetchDaySummary(String uid, String dateKey);

  /// Raw day record JSON for [uid]/[dateKey] (owner's detail view).
  /// Owner or manager. A manager writing another driver's record
  /// stamps it with editedByManagerUid/editedByManagerAtMillis keys.
  Future<void> saveOrderRecord(
    String uid,
    String dateKey,
    Map<String, dynamic> json,
  );

  Future<Map<String, dynamic>?> fetchOrderRecord(String uid, String dateKey);

  /// Delete one day's data (summary + order record) for [uid].
  /// Owner or manager. User docs themselves are never deletable.
  Future<void> deleteUserDay(String uid, String dateKey);

  /// Manager-only: create or edit an adjustment for [adjustment.uid].
  /// Drivers can NEVER write adjustments (not even their own — a
  /// driver must never be able to grant himself a bonus). A manager
  /// also cannot adjust his OWN pay. Returns the saved adjustment
  /// (with its doc id filled in when the backend generated one).
  /// Throws [CloudDenied] for drivers and for self-adjustment.
  Future<CloudAdjustment> saveAdjustment(CloudAdjustment adjustment);

  /// Manager-only: delete one adjustment.
  Future<void> deleteAdjustment(String uid, String adjustmentId);

  /// Owner or manager: all adjustments for [uid] (any week).
  Future<List<CloudAdjustment>> listAdjustments(String uid);

  /// Manager-only: all user profiles. Throws [CloudDenied] for drivers.
  Future<List<CloudAccount>> listUsers();

  /// Manager-only: every user's summary doc for [dateKey].
  /// Throws [CloudDenied] for drivers.
  Future<List<CloudDaySummary>> listDaySummaries(String dateKey);

  /// Manager-only: summaries for several days at once, keyed by
  /// dateKey. One users fetch serves all days (week view must not
  /// re-read the whole users collection per day — free-tier reads).
  /// Throws [CloudDenied] for drivers.
  Future<Map<String, List<CloudDaySummary>>> listSummariesForDays(
    List<String> dateKeys,
  );
}

/// Backend used when no real Firebase project is configured yet.
/// Every call fails with [CloudNotConfigured] so the UI can show a
/// clear "cloud not configured" state instead of fake success.
class NotConfiguredBackend implements CloudBackend {
  @override
  CloudAccount? get currentAccount => null;

  @override
  Future<CloudAccount> signUp({
    required String email,
    required String password,
    required String username,
    String phone = '',
  }) =>
      throw const CloudNotConfigured();

  @override
  Future<String?> resolveLoginEmail(String identifier) =>
      throw const CloudNotConfigured();

  @override
  Future<bool> isUsernameAvailable(String username) =>
      throw const CloudNotConfigured();

  @override
  Future<CloudAccount?> restoreSession() async => null;

  @override
  Future<CloudAccount> changeUsername(String newUsername) =>
      throw const CloudNotConfigured();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      throw const CloudNotConfigured();

  @override
  Future<void> sendPasswordReset(String email) =>
      throw const CloudNotConfigured();

  @override
  Future<String?> lookupUsernameByEmail(String email) =>
      throw const CloudNotConfigured();

  @override
  Future<CloudAccount> signIn({
    required String email,
    required String password,
  }) =>
      throw const CloudNotConfigured();

  @override
  Future<CloudAccount?> signInWithGoogle() =>
      throw const CloudNotConfigured();

  @override
  Future<void> signOut() => throw const CloudNotConfigured();

  @override
  Future<CloudAccount?> fetchProfile(String uid) =>
      throw const CloudNotConfigured();

  @override
  Future<void> saveProfile(CloudAccount account) =>
      throw const CloudNotConfigured();

  @override
  Future<void> saveDaySummary(CloudDaySummary summary) =>
      throw const CloudNotConfigured();

  @override
  Future<CloudDaySummary?> fetchDaySummary(String uid, String dateKey) =>
      throw const CloudNotConfigured();

  @override
  Future<void> saveOrderRecord(
    String uid,
    String dateKey,
    Map<String, dynamic> json,
  ) =>
      throw const CloudNotConfigured();

  @override
  Future<Map<String, dynamic>?> fetchOrderRecord(String uid, String dateKey) =>
      throw const CloudNotConfigured();

  @override
  Future<void> deleteUserDay(String uid, String dateKey) =>
      throw const CloudNotConfigured();

  @override
  Future<CloudAdjustment> saveAdjustment(CloudAdjustment adjustment) =>
      throw const CloudNotConfigured();

  @override
  Future<void> deleteAdjustment(String uid, String adjustmentId) =>
      throw const CloudNotConfigured();

  @override
  Future<List<CloudAdjustment>> listAdjustments(String uid) =>
      throw const CloudNotConfigured();

  @override
  Future<List<CloudAccount>> listUsers() =>
      throw const CloudNotConfigured();

  @override
  Future<List<CloudDaySummary>> listDaySummaries(String dateKey) =>
      throw const CloudNotConfigured();

  @override
  Future<Map<String, List<CloudDaySummary>>> listSummariesForDays(
    List<String> dateKeys,
  ) =>
      throw const CloudNotConfigured();
}
