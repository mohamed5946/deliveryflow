// v27.33 — Phase 1 of the Firebase multi-account + manager system.
//
// Cloud value types. These are plain data — no Firebase imports here,
// so the sync logic and tests never touch a real backend.

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

  bool get isManager => role == CloudRole.manager;

  /// Name shown in the team list: username, falling back to email.
  String get displayName => username.isEmpty ? email : username;

  Map<String, dynamic> toJson() => {
        'email': email,
        'username': username,
        'role': role.name,
        'phone': phone,
        'mustChangePassword': mustChangePassword,
      };

  factory CloudAccount.fromJson(String uid, Map<String, dynamic> json) {
    return CloudAccount(
      uid: uid,
      email: (json['email'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      role: cloudRoleFromString(json['role'] as String?),
      phone: (json['phone'] as String?) ?? '',
      mustChangePassword: (json['mustChangePassword'] as bool?) ?? false,
    );
  }
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
