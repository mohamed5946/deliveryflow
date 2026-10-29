// v27.33 — Phase 1 of the Firebase multi-account + manager system.
//
// Cloud value types. These are plain data — no Firebase imports here,
// so the sync logic and tests never touch a real backend.

import 'login_identifier.dart';

// Roles. A user doc's `role` is `driver` by default. `manager` is
// NEVER self-assignable from the client: only an existing manager (or
// a manual edit in the Firebase console for the very first manager)
// may set it. Firestore rules enforce the same server-side.
enum CloudRole { driver, manager }

CloudRole cloudRoleFromString(String? value) {
  if (value == 'manager') return CloudRole.manager;
  return CloudRole.driver;
}

/// One signed-in account: Firebase Auth UID + profile fields from the
/// user doc. Passwords are NEVER stored here, in Firestore, or locally
/// — Firebase Auth owns credentials and only ever returns a UID.
class CloudAccount {
  const CloudAccount({
    required this.uid,
    required this.email,
    required this.username,
    this.role = CloudRole.driver,
    this.phone = '',
    this.mustChangePassword = false,
    this.blocked = false,
    this.blockedAt = 0,
    this.blockedBy = '',
    this.payoutMethod = CloudPayoutMethod.none,
    this.payoutNumber = '',
    this.payoutName = '',
  });

  final String uid;
  final String email;

  /// Display username picked at sign-up. Login itself uses the account
  /// email (Firebase Auth is email-based); the username is a profile
  /// field shown in the app and in the manager's team list.
  final String username;
  final CloudRole role;

  /// Normalized Egyptian mobile collected at sign-up (digits only,
  /// see login_identifier.dart). Used for phone login resolution;
  /// never a credential.
  final String phone;

  /// Forced password change (admin first-login rule): when true, the
  /// app must show the password-change screen BEFORE any dashboard
  /// or data access, and the account cannot be used until the
  /// password is changed. Set ONLY by the project owner in the
  /// Firebase console on the user doc (never by the app, never
  /// seeded); cleared by a successful password change. There is NO
  /// default or initial password anywhere in code — the initial
  /// password is set by the owner in the console only.
  final bool mustChangePassword;

  /// v27.35 blacklist (reversible block, NOT a deletion): when true,
  /// the driver cannot sign in (the sign-in/restore gates sign the
  /// session out), is hidden from the team dashboard, and his
  /// salaries are excluded from every total. All of his data
  /// (orders, summaries, adjustments, rollups, login lookups) is
  /// KEPT, so unblocking restores him fully. Set/cleared only by a
  /// manager ([blockedBy] is the manager uid, [blockedAt] is epoch
  /// millis); never set by the driver himself.
  final bool blocked;

  /// Epoch millis when the block was set (0 when never blocked).
  final int blockedAt;

  /// UID of the manager who set the block ('' when never blocked).
  final String blockedBy;

  /// v27.35 payout preferences (driver sets his own; managers only
  /// read them for the Payouts list). [payoutMethod] is [none] when
  /// the driver has not set a method. [payoutNumber] is the transfer
  /// number (Egyptian mobile, normalized) and [payoutName] the
  /// wallet display name — both required for InstaPay / Vodafone
  /// Cash, both empty for Manual.
  final CloudPayoutMethod payoutMethod;
  final String payoutNumber;
  final String payoutName;

  bool get isManager => role == CloudRole.manager;

  /// Name shown in the team list: username, falling back to email.
  String get displayName => username.isEmpty ? email : username;

  Map<String, dynamic> toJson() => {
        'email': email,
        'username': username,
        'role': role.name,
        'phone': phone,
        'mustChangePassword': mustChangePassword,
        'blocked': blocked,
        'blockedAt': blockedAt,
        'blockedBy': blockedBy,
        'payoutMethod': payoutMethod.name,
        'payoutNumber': payoutNumber,
        'payoutName': payoutName,
      };

  factory CloudAccount.fromJson(String uid, Map<String, dynamic> json) {
    return CloudAccount(
      uid: uid,
      email: (json['email'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      role: cloudRoleFromString(json['role'] as String?),
      phone: (json['phone'] as String?) ?? '',
      mustChangePassword: (json['mustChangePassword'] as bool?) ?? false,
      blocked: (json['blocked'] as bool?) ?? false,
      blockedAt: (json['blockedAt'] as int?) ?? 0,
      blockedBy: (json['blockedBy'] as String?) ?? '',
      payoutMethod:
          cloudPayoutMethodFromString(json['payoutMethod'] as String?),
      payoutNumber: (json['payoutNumber'] as String?) ?? '',
      payoutName: (json['payoutName'] as String?) ?? '',
    );
  }
}

/// v27.35 payout methods (driver preference, stored on the profile).
/// `none` means the driver has not set a method yet — the manager
/// Payouts list still shows him, as "Not set", with his amount due.
enum CloudPayoutMethod {
  none,
  instapay,
  vodafoneCash,
  manual;

  /// Display label for the driver setting and the manager list.
  String get label => switch (this) {
        CloudPayoutMethod.none => 'Not set',
        CloudPayoutMethod.instapay => 'InstaPay',
        CloudPayoutMethod.vodafoneCash => 'Vodafone Cash',
        CloudPayoutMethod.manual => 'Manual',
      };
}

CloudPayoutMethod cloudPayoutMethodFromString(String? value) {
  return switch (value) {
    'instapay' => CloudPayoutMethod.instapay,
    'vodafoneCash' => CloudPayoutMethod.vodafoneCash,
    'manual' => CloudPayoutMethod.manual,
    _ => CloudPayoutMethod.none,
  };
}

/// v27.35 payout validation, shared by the Firebase backend, the
/// fake backend (tests) and the driver form (for inline errors).
/// Returns an error message, or null when the prefs are valid.
/// InstaPay and Vodafone Cash numbers are Egyptian mobiles (same
/// normalization/validation as login phones — InstaPay numbers are
/// phone numbers in this design). Manual needs no number or name;
/// `none` clears the prefs. The caller stores the NORMALIZED number
/// (see [normalizePayoutNumber]).
String? validatePayoutPrefs({
  required CloudPayoutMethod method,
  required String number,
  required String name,
}) {
  switch (method) {
    case CloudPayoutMethod.none:
    case CloudPayoutMethod.manual:
      return null;
    case CloudPayoutMethod.instapay:
    case CloudPayoutMethod.vodafoneCash:
      if (!isValidEgyptPhone(number)) {
        return 'Enter a valid Egyptian mobile number';
      }
      if (name.trim().isEmpty) {
        return 'Enter the wallet display name';
      }
      return null;
  }
}

/// Normalized form of a payout number (digits only, Egypt prefixes
/// stripped). Empty for Manual / unset (callers clear the stored
/// number then, so a stale transfer number never lingers on a
/// Manual row).
String normalizePayoutNumber(
  CloudPayoutMethod method,
  String number,
) {
  if (method != CloudPayoutMethod.instapay &&
      method != CloudPayoutMethod.vodafoneCash) {
    return '';
  }
  return normalizeEgyptPhone(number);
}

/// Result of starting a Google sign-up (v27.35, see
/// [CloudBackend.beginGoogleSignUp] in cloud_backend.dart).
///
/// Exactly one shape applies:
/// - [cancelled] — the user dismissed the Google picker; nothing
///   signed in, nothing to complete.
/// - [account] non-null — this Google identity already has an app
///   account; the caller signs in with it, no completion needed.
/// - otherwise — the Google Auth user has no profile yet; the caller
///   shows the username + phone completion form, then calls
///   completeGoogleSignUp. [uid], [email] and [displayName] carry
///   the Google identity for that form.
class GoogleSignUpStart {
  const GoogleSignUpStart._({
    this.account,
    this.uid = '',
    this.email = '',
    this.displayName = '',
    this.cancelled = false,
  });

  const GoogleSignUpStart.existing(CloudAccount account)
      : this._(account: account);

  const GoogleSignUpStart.needsCompletion({
    required String uid,
    required String email,
    required String displayName,
  }) : this._(uid: uid, email: email, displayName: displayName);

  const GoogleSignUpStart.cancelled() : this._(cancelled: true);

  final CloudAccount? account;
  final String uid;
  final String email;
  final String displayName;
  final bool cancelled;

  bool get needsCompletion => !cancelled && account == null;
}

/// One day's summary for the manager view.
///
/// KEY EFFICIENCY DESIGN: each user writes ONE summary doc per day, so
/// the manager screen reads ~30 small docs for a 30-person team instead
/// of scanning thousands of raw orders. Raw orders still sync per user
/// for their own detail views; summaries are the manager's read path.
class CloudDaySummary {
  const CloudDaySummary({
    required this.uid,
    required this.dateKey,
    required this.ordersCount,
    required this.totalKm,
    required this.salaryTotal,
    this.updatedAtMillis = 0,
    // Salary-breakdown components (v27.33 dashboard detail). Older
    // summary docs lack them and read as 0 — the total stays valid.
    this.orderPrice = 0,
    this.dailyFixedPay = 0,
    this.distanceBonus = 0,
    this.manualBonus = 0,
    this.flatBonus = 0,
    // Manager-edit stamp (v27.33 manager powers): set by the backend
    // when a manager edits ANOTHER driver's doc, so the driver can
    // see a change came from the manager. Empty = never manager-edited.
    this.editedByManagerUid = '',
    this.editedByManagerAtMillis = 0,
  });

  final String uid;

  /// yyyy-MM-dd.
  final String dateKey;
  final int ordersCount;
  final double totalKm;

  /// Computed with the app's existing salary formula (see
  /// [computeDaySalary]): orders × price + paid-day fixed pay +
  /// distance + manual + flat bonuses.
  final double salaryTotal;
  final int updatedAtMillis;

  /// Breakdown of [salaryTotal] (0 for pre-breakdown docs).
  final double orderPrice;
  final double dailyFixedPay;
  final double distanceBonus;
  final double manualBonus;
  final double flatBonus;

  /// Manager-edit stamp: UID of the manager who last edited this doc
  /// ('' when never manager-edited) + timestamp millis of that edit.
  /// Written by the backend on manager edits of another driver's doc.
  final String editedByManagerUid;
  final int editedByManagerAtMillis;

  /// True when a manager last edited this doc.
  bool get editedByManager => editedByManagerUid.isNotEmpty;

  /// Copy with a manager-edit stamp applied.
  CloudDaySummary stampedByManager(String managerUid, int atMillis) {
    return CloudDaySummary(
      uid: uid,
      dateKey: dateKey,
      ordersCount: ordersCount,
      totalKm: totalKm,
      salaryTotal: salaryTotal,
      updatedAtMillis: updatedAtMillis,
      orderPrice: orderPrice,
      dailyFixedPay: dailyFixedPay,
      distanceBonus: distanceBonus,
      manualBonus: manualBonus,
      flatBonus: flatBonus,
      editedByManagerUid: managerUid,
      editedByManagerAtMillis: atMillis,
    );
  }

  /// True when this doc carries a real breakdown (not just a total).
  bool get hasBreakdown =>
      orderPrice > 0 || dailyFixedPay > 0 || distanceBonus > 0 ||
      manualBonus > 0 || flatBonus > 0;

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'ordersCount': ordersCount,
        'totalKm': totalKm,
        'salaryTotal': salaryTotal,
        'updatedAtMillis': updatedAtMillis,
        'orderPrice': orderPrice,
        'dailyFixedPay': dailyFixedPay,
        'distanceBonus': distanceBonus,
        'manualBonus': manualBonus,
        'flatBonus': flatBonus,
        'editedByManagerUid': editedByManagerUid,
        'editedByManagerAtMillis': editedByManagerAtMillis,
      };

  factory CloudDaySummary.fromJson(
    String uid,
    Map<String, dynamic> json,
  ) {
    return CloudDaySummary(
      uid: uid,
      dateKey: (json['dateKey'] as String?) ?? '',
      ordersCount: (json['ordersCount'] as int?) ?? 0,
      totalKm: (json['totalKm'] as num?)?.toDouble() ?? 0,
      salaryTotal: (json['salaryTotal'] as num?)?.toDouble() ?? 0,
      updatedAtMillis: (json['updatedAtMillis'] as int?) ?? 0,
      orderPrice: (json['orderPrice'] as num?)?.toDouble() ?? 0,
      dailyFixedPay: (json['dailyFixedPay'] as num?)?.toDouble() ?? 0,
      distanceBonus: (json['distanceBonus'] as num?)?.toDouble() ?? 0,
      manualBonus: (json['manualBonus'] as num?)?.toDouble() ?? 0,
      flatBonus: (json['flatBonus'] as num?)?.toDouble() ?? 0,
      editedByManagerUid: (json['editedByManagerUid'] as String?) ?? '',
      editedByManagerAtMillis:
          (json['editedByManagerAtMillis'] as int?) ?? 0,
    );
  }
}

/// Build a summary from its components, computing [salaryTotal] with
/// [computeDaySalary] so the stored total can never drift from the
/// app's salary formula.
CloudDaySummary buildDaySummary({
  required String uid,
  required String dateKey,
  required int ordersCount,
  required double totalKm,
  required double orderPrice,
  required double dailyFixedPay,
  required double distanceBonus,
  required double manualBonus,
  required double flatBonus,
  int updatedAtMillis = 0,
}) {
  return CloudDaySummary(
    uid: uid,
    dateKey: dateKey,
    ordersCount: ordersCount,
    totalKm: totalKm,
    salaryTotal: computeDaySalary(
      ordersCount: ordersCount,
      orderPrice: orderPrice,
      dailyFixedPay: dailyFixedPay,
      distanceBonus: distanceBonus,
      manualBonus: manualBonus,
      flatBonus: flatBonus,
    ),
    updatedAtMillis: updatedAtMillis,
    orderPrice: orderPrice,
    dailyFixedPay: dailyFixedPay,
    distanceBonus: distanceBonus,
    manualBonus: manualBonus,
    flatBonus: flatBonus,
  );
}

/// One day's salary, mirroring [WeeklyReport.salaryTotal] for a single
/// day: counted orders × order price + (1 paid day × daily fixed pay
/// when the day has at least one counted order — a 0-order day earns
/// no fixed pay, exactly like the weekly formula's paidDaysCount) +
/// distance + manual + flat bonuses.
double computeDaySalary({
  required int ordersCount,
  required double orderPrice,
  required double dailyFixedPay,
  required double distanceBonus,
  required double manualBonus,
  required double flatBonus,
}) {
  final paidDay = ordersCount >= 1 ? 1 : 0;
  return ordersCount * orderPrice +
      paidDay * dailyFixedPay +
      distanceBonus +
      manualBonus +
      flatBonus;
}

/// Thrown when cloud features are used before a real Firebase project
/// is configured (no google-services.json / generated options yet).
class CloudNotConfigured implements Exception {
  const CloudNotConfigured();
  @override
  String toString() => 'CloudNotConfigured';
}

/// Thrown when the signed-in user lacks permission for an operation
/// (e.g. a driver requesting the team list, or anyone attempting to
/// change a role they may not change).
class CloudDenied implements Exception {
  const CloudDenied([this.message = 'denied']);
  final String message;
  @override
  String toString() => 'CloudDenied: $message';
}

/// v27.35 blacklist gate: thrown when a blocked account tries to
/// sign in (email/password, Google, Google sign-up) or restore a
/// session. [toString] returns the bare message (no `Exception:`
/// prefix) because the sign-in form shows it verbatim to the driver.
class CloudAccountBlocked implements Exception {
  const CloudAccountBlocked(
      [this.message = 'This account has been blocked.']);
  final String message;
  @override
  String toString() => message;
}

enum CloudAdjustmentType { bonus, deduction }

CloudAdjustmentType cloudAdjustmentTypeFromString(String? value) {
  return switch (value) {
    'deduction' => CloudAdjustmentType.deduction,
    _ => CloudAdjustmentType.bonus,
  };
}

/// A manager-issued per-driver adjustment (bonus or deduction/خصم).
///
/// Stored under the driver's user doc: users/{uid}/adjustments/{id}.
/// Fields:
///   type       — 'bonus' | 'deduction'
///   amount     — always POSITIVE; the sign comes from [type]
///   reason     — REQUIRED, non-empty: the driver always sees why
///   weekKey    — week-start dateKey (Sunday, yyyy-MM-dd) the
///                adjustment belongs to
///   createdBy  — manager UID who issued it (the manager stamp)
///   createdAtMillis — issuance timestamp (shown as the date)
class CloudAdjustment {
  const CloudAdjustment({
    required this.id,
    required this.uid,
    required this.type,
    required this.amount,
    required this.reason,
    required this.weekKey,
    required this.createdBy,
    required this.createdAtMillis,
  });

  final String id;
  final String uid;
  final CloudAdjustmentType type;
  final double amount;
  final String reason;
  final String weekKey;
  final String createdBy;
  final int createdAtMillis;

  bool get isBonus => type == CloudAdjustmentType.bonus;

  /// Signed contribution to a weekly total: +amount for a bonus,
  /// −amount for a deduction.
  double get signedAmount => isBonus ? amount : -amount;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'amount': amount,
        'reason': reason,
        'weekKey': weekKey,
        'createdBy': createdBy,
        'createdAtMillis': createdAtMillis,
      };

  factory CloudAdjustment.fromJson(
    String id,
    String uid,
    Map<String, dynamic> json,
  ) {
    return CloudAdjustment(
      id: id,
      uid: uid,
      type: cloudAdjustmentTypeFromString(json['type'] as String?),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      reason: (json['reason'] as String?) ?? '',
      weekKey: (json['weekKey'] as String?) ?? '',
      createdBy: (json['createdBy'] as String?) ?? '',
      createdAtMillis: (json['createdAtMillis'] as int?) ?? 0,
    );
  }
}

/// Permanent per-driver per-week salary rollup (v27.35 retention).
///
/// One doc per driver per week at users/{uid}/weekRollups/{weekKey}
/// (weekKey = Sunday week-start dateKey). This doc NEVER expires:
/// no TTL policy is ever enabled on the weekRollups collection, and
/// clients may never delete it (see firestore.rules).
///
/// The rollup folds manager adjustments into [salaryTotal], so the
/// week total stays correct after the day summaries, order records
/// AND adjustment docs for the week have TTL-expired. Components are
/// kept for the breakdown; [salaryBase] is the sum of the day totals
/// (the pre-adjustment base the old read-time composition used).
class CloudWeekRollup {
  const CloudWeekRollup({
    required this.uid,
    required this.weekKey,
    required this.ordersCount,
    required this.totalKm,
    required this.ordersAmount,
    required this.fixedPayAmount,
    required this.distanceBonus,
    required this.manualBonus,
    required this.flatBonus,
    required this.salaryBase,
    required this.adjustmentsTotal,
    required this.salaryTotal,
    required this.adjustmentCount,
    this.updatedAtMillis = 0,
  });

  final String uid;

  /// Sunday week-start dateKey, also the doc id.
  final String weekKey;
  final int ordersCount;
  final double totalKm;
  final double ordersAmount;
  final double fixedPayAmount;
  final double distanceBonus;
  final double manualBonus;
  final double flatBonus;
  final double salaryBase;
  final double adjustmentsTotal;
  final double salaryTotal;
  final int adjustmentCount;
  final int updatedAtMillis;

  Map<String, dynamic> toJson() => {
        'weekKey': weekKey,
        'ordersCount': ordersCount,
        'totalKm': totalKm,
        'ordersAmount': ordersAmount,
        'fixedPayAmount': fixedPayAmount,
        'distanceBonus': distanceBonus,
        'manualBonus': manualBonus,
        'flatBonus': flatBonus,
        'salaryBase': salaryBase,
        'adjustmentsTotal': adjustmentsTotal,
        'salaryTotal': salaryTotal,
        'adjustmentCount': adjustmentCount,
        'updatedAtMillis': updatedAtMillis,
      };

  factory CloudWeekRollup.fromJson(
    String uid,
    String weekKey,
    Map<String, dynamic> json,
  ) {
    return CloudWeekRollup(
      uid: uid,
      weekKey: weekKey,
      ordersCount: (json['ordersCount'] as num?)?.toInt() ?? 0,
      totalKm: (json['totalKm'] as num?)?.toDouble() ?? 0,
      ordersAmount: (json['ordersAmount'] as num?)?.toDouble() ?? 0,
      fixedPayAmount: (json['fixedPayAmount'] as num?)?.toDouble() ?? 0,
      distanceBonus: (json['distanceBonus'] as num?)?.toDouble() ?? 0,
      manualBonus: (json['manualBonus'] as num?)?.toDouble() ?? 0,
      flatBonus: (json['flatBonus'] as num?)?.toDouble() ?? 0,
      salaryBase: (json['salaryBase'] as num?)?.toDouble() ?? 0,
      adjustmentsTotal: (json['adjustmentsTotal'] as num?)?.toDouble() ?? 0,
      salaryTotal: (json['salaryTotal'] as num?)?.toDouble() ?? 0,
      adjustmentCount: (json['adjustmentCount'] as num?)?.toInt() ?? 0,
      updatedAtMillis: (json['updatedAtMillis'] as num?)?.toInt() ?? 0,
    );
  }
}
