import 'package:hive/hive.dart';

/// Schema version for migrations. Bump when a model changes shape.
const int kSchemaVersion = 11;

// ---------------------------------------------------------------------------
// UserSettings (typeId 0)
// ---------------------------------------------------------------------------

@HiveType(typeId: 0)
class UserSettings extends HiveObject {
  @HiveField(0)
  String displayName;
  @HiveField(1)
  String languageCode; // 'ar' | 'en'
  @HiveField(2)
  int themeMode; // 0=system, 1=light, 2=dark
  @HiveField(3)
  int dailyReminderHour;
  @HiveField(4)
  int dailyReminderMinute;
  @HiveField(5)
  bool dailyReminderEnabled;
  @HiveField(6)
  int scheduleReminderHour;
  @HiveField(7)
  int scheduleReminderMinute;
  @HiveField(8)
  bool scheduleReminderEnabled;
  @HiveField(9)
  int reportReminderHour;
  @HiveField(10)
  int reportReminderMinute;
  @HiveField(11)
  bool reportReminderEnabled;
  @HiveField(12)
  int followUpReminderHour;
  @HiveField(13)
  int followUpReminderMinute;
  @HiveField(14)
  bool followUpReminderEnabled;
  @HiveField(15)
  int? weeklyOrderGoal;
  @HiveField(16)
  double? weeklyWorkHoursGoal;
  @HiveField(17)
  int defaultBreakDurationMinutes;
  @HiveField(18)
  bool notificationsEnabled;
  @HiveField(19)
  bool onboardingDone;
  @HiveField(20)
  int themePreset; // index into AppThemePreset.all
  @HiveField(21)
  double? orderPrice; // EGP per order (salary calc)
  @HiveField(22)
  double? dailyFixedPay; // EGP per attended day (salary calc)
  @HiveField(23)
  String photoPath; // absolute path of the saved profile photo ('', if none)
  @HiveField(24)
  List<String> readNotificationIds; // completed-order notification ids marked read
  @HiveField(25)
  List<String> dismissedNotificationIds; // swiped-away notification ids
  @HiveField(26)
  bool registered; // first-launch registration-code gate accepted
  @HiveField(27)
  int autoNavMode; // 0=in-app navigation, 1=Google Maps middleman (default since v27)
  @HiveField(28)
  bool shiftEndReminderEnabled; // v26: remind at shift end to log orders
  @HiveField(29)
  bool developerModeUnlocked; // v27.4: diagnostics tools gate (asked once)
  // --- Distance bonus (v27.5) ---
  @HiveField(30)
  bool distanceBonusEnabled; // global default; a week may override it
  @HiveField(31)
  double distanceBonusTier1Km;
  @HiveField(32)
  double distanceBonusTier1Egp;
  @HiveField(33)
  double distanceBonusTier2Km;
  @HiveField(34)
  double distanceBonusTier2Egp;
  @HiveField(35)
  double distanceBonusTier3Km;
  @HiveField(36)
  double distanceBonusTier3Egp;
  @HiveField(37)
  Map<String, bool>
      distanceBonusWeekOverrides; // weekStartKey -> on/off for that week only
  // --- Flat per-order bonus (v27.6) ---
  @HiveField(38)
  double flatOrderBonusEgp; // EGP added to EVERY counted order (0 = off)

  /// The editable tiers in display order (tier 1, 2, 3). The pure
  /// resolver is order-agnostic, so edited thresholds never need
  /// re-sorting here.
  List<DistanceBonusTier> get distanceBonusTiers => [
        DistanceBonusTier(
            fromKm: distanceBonusTier1Km, bonusEgp: distanceBonusTier1Egp),
        DistanceBonusTier(
            fromKm: distanceBonusTier2Km, bonusEgp: distanceBonusTier2Egp),
        DistanceBonusTier(
            fromKm: distanceBonusTier3Km, bonusEgp: distanceBonusTier3Egp),
      ];

  /// Effective distance-bonus flag for a week: the week's own override
  /// when one is stored, else the global default.
  bool distanceBonusEnabledForWeek(String weekStartKey) =>
      distanceBonusWeekOverrides[weekStartKey] ?? distanceBonusEnabled;

  UserSettings({
    this.displayName = '',
    this.languageCode = 'ar',
    this.themeMode = 0,
    this.dailyReminderHour = 21,
    this.dailyReminderMinute = 0,
    this.dailyReminderEnabled = true,
    this.scheduleReminderHour = 10,
    this.scheduleReminderMinute = 0,
    this.scheduleReminderEnabled = true,
    this.reportReminderHour = 20,
    this.reportReminderMinute = 0,
    this.reportReminderEnabled = true,
    this.followUpReminderHour = 22,
    this.followUpReminderMinute = 30,
    this.followUpReminderEnabled = false,
    this.weeklyOrderGoal,
    this.weeklyWorkHoursGoal,
    this.defaultBreakDurationMinutes = 30,
    this.notificationsEnabled = true,
    this.onboardingDone = false,
    this.themePreset = 0,
    this.orderPrice,
    this.dailyFixedPay,
    this.photoPath = '',
    List<String>? readNotificationIds,
    List<String>? dismissedNotificationIds,
    this.registered = false,
    this.autoNavMode = 1,
    this.shiftEndReminderEnabled = false,
    this.developerModeUnlocked = false,
    this.distanceBonusEnabled = true,
    this.distanceBonusTier1Km = 12,
    this.distanceBonusTier1Egp = 5,
    this.distanceBonusTier2Km = 15,
    this.distanceBonusTier2Egp = 10,
    this.distanceBonusTier3Km = 20,
    this.distanceBonusTier3Egp = 17,
    Map<String, bool>? distanceBonusWeekOverrides,
    this.flatOrderBonusEgp = 0,
  })  : readNotificationIds = readNotificationIds ?? [],
        dismissedNotificationIds = dismissedNotificationIds ?? [],
        distanceBonusWeekOverrides = distanceBonusWeekOverrides ?? {};

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'languageCode': languageCode,
        'themeMode': themeMode,
        'dailyReminderHour': dailyReminderHour,
        'dailyReminderMinute': dailyReminderMinute,
        'dailyReminderEnabled': dailyReminderEnabled,
        'scheduleReminderHour': scheduleReminderHour,
        'scheduleReminderMinute': scheduleReminderMinute,
        'scheduleReminderEnabled': scheduleReminderEnabled,
        'reportReminderHour': reportReminderHour,
        'reportReminderMinute': reportReminderMinute,
        'reportReminderEnabled': reportReminderEnabled,
        'followUpReminderHour': followUpReminderHour,
        'followUpReminderMinute': followUpReminderMinute,
        'followUpReminderEnabled': followUpReminderEnabled,
        'weeklyOrderGoal': weeklyOrderGoal,
        'weeklyWorkHoursGoal': weeklyWorkHoursGoal,
        'defaultBreakDurationMinutes': defaultBreakDurationMinutes,
        'notificationsEnabled': notificationsEnabled,
        'onboardingDone': onboardingDone,
        'themePreset': themePreset,
        'orderPrice': orderPrice,
        'dailyFixedPay': dailyFixedPay,
        'photoPath': photoPath,
        'readNotificationIds': readNotificationIds,
        'dismissedNotificationIds': dismissedNotificationIds,
        'registered': registered,
        'autoNavMode': autoNavMode,
        'shiftEndReminderEnabled': shiftEndReminderEnabled,
        'developerModeUnlocked': developerModeUnlocked,
        'distanceBonusEnabled': distanceBonusEnabled,
        'distanceBonusTier1Km': distanceBonusTier1Km,
        'distanceBonusTier1Egp': distanceBonusTier1Egp,
        'distanceBonusTier2Km': distanceBonusTier2Km,
        'distanceBonusTier2Egp': distanceBonusTier2Egp,
        'distanceBonusTier3Km': distanceBonusTier3Km,
        'distanceBonusTier3Egp': distanceBonusTier3Egp,
        'distanceBonusWeekOverrides': distanceBonusWeekOverrides,
        'flatOrderBonusEgp': flatOrderBonusEgp,
        'schemaVersion': kSchemaVersion,
      };

  static UserSettings fromJson(Map<String, dynamic> json) => UserSettings(
        displayName: (json['displayName'] as String?) ?? '',
        languageCode: (json['languageCode'] as String?) ?? 'ar',
        themeMode: (json['themeMode'] as num?)?.toInt() ?? 0,
        dailyReminderHour: (json['dailyReminderHour'] as num?)?.toInt() ?? 21,
        dailyReminderMinute:
            (json['dailyReminderMinute'] as num?)?.toInt() ?? 0,
        dailyReminderEnabled: (json['dailyReminderEnabled'] as bool?) ?? true,
        scheduleReminderHour:
            (json['scheduleReminderHour'] as num?)?.toInt() ?? 10,
        scheduleReminderMinute:
            (json['scheduleReminderMinute'] as num?)?.toInt() ?? 0,
        scheduleReminderEnabled:
            (json['scheduleReminderEnabled'] as bool?) ?? true,
        reportReminderHour: (json['reportReminderHour'] as num?)?.toInt() ?? 20,
        reportReminderMinute:
            (json['reportReminderMinute'] as num?)?.toInt() ?? 0,
        reportReminderEnabled: (json['reportReminderEnabled'] as bool?) ?? true,
        followUpReminderHour:
            (json['followUpReminderHour'] as num?)?.toInt() ?? 22,
        followUpReminderMinute:
            (json['followUpReminderMinute'] as num?)?.toInt() ?? 30,
        followUpReminderEnabled:
            (json['followUpReminderEnabled'] as bool?) ?? false,
        weeklyOrderGoal: (json['weeklyOrderGoal'] as num?)?.toInt(),
        weeklyWorkHoursGoal: (json['weeklyWorkHoursGoal'] as num?)?.toDouble(),
        defaultBreakDurationMinutes:
            (json['defaultBreakDurationMinutes'] as num?)?.toInt() ?? 30,
        notificationsEnabled: (json['notificationsEnabled'] as bool?) ?? true,
        onboardingDone: (json['onboardingDone'] as bool?) ?? false,
        themePreset: (json['themePreset'] as num?)?.toInt() ?? 0,
        orderPrice: (json['orderPrice'] as num?)?.toDouble(),
        dailyFixedPay: (json['dailyFixedPay'] as num?)?.toDouble(),
        photoPath: (json['photoPath'] as String?) ?? '',
        readNotificationIds:
            (json['readNotificationIds'] as List?)?.cast<String>() ?? [],
        dismissedNotificationIds:
            (json['dismissedNotificationIds'] as List?)?.cast<String>() ?? [],
        registered: (json['registered'] as bool?) ?? false,
        autoNavMode: (json['autoNavMode'] as num?)?.toInt() ?? 1,
        shiftEndReminderEnabled:
            (json['shiftEndReminderEnabled'] as bool?) ?? false,
        developerModeUnlocked:
            (json['developerModeUnlocked'] as bool?) ?? false,
        distanceBonusEnabled:
            (json['distanceBonusEnabled'] as bool?) ?? true,
        distanceBonusTier1Km:
            (json['distanceBonusTier1Km'] as num?)?.toDouble() ?? 12,
        distanceBonusTier1Egp:
            (json['distanceBonusTier1Egp'] as num?)?.toDouble() ?? 5,
        distanceBonusTier2Km:
            (json['distanceBonusTier2Km'] as num?)?.toDouble() ?? 15,
        distanceBonusTier2Egp:
            (json['distanceBonusTier2Egp'] as num?)?.toDouble() ?? 10,
        distanceBonusTier3Km:
            (json['distanceBonusTier3Km'] as num?)?.toDouble() ?? 20,
        distanceBonusTier3Egp:
            (json['distanceBonusTier3Egp'] as num?)?.toDouble() ?? 17,
        distanceBonusWeekOverrides:
            (json['distanceBonusWeekOverrides'] as Map?)
                    ?.map((k, v) => MapEntry(k.toString(), v as bool)) ??
                {},
        flatOrderBonusEgp:
            (json['flatOrderBonusEgp'] as num?)?.toDouble() ?? 0,
      );
}

class UserSettingsAdapter extends TypeAdapter<UserSettings> {
  @override
  final int typeId = 0;

  @override
  UserSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserSettings(
      displayName: (fields[0] as String?) ?? '',
      languageCode: (fields[1] as String?) ?? 'ar',
      themeMode: (fields[2] as int?) ?? 0,
      dailyReminderHour: (fields[3] as int?) ?? 21,
      dailyReminderMinute: (fields[4] as int?) ?? 0,
      dailyReminderEnabled: (fields[5] as bool?) ?? true,
      scheduleReminderHour: (fields[6] as int?) ?? 10,
      scheduleReminderMinute: (fields[7] as int?) ?? 0,
      scheduleReminderEnabled: (fields[8] as bool?) ?? true,
      reportReminderHour: (fields[9] as int?) ?? 20,
      reportReminderMinute: (fields[10] as int?) ?? 0,
      reportReminderEnabled: (fields[11] as bool?) ?? true,
      followUpReminderHour: (fields[12] as int?) ?? 22,
      followUpReminderMinute: (fields[13] as int?) ?? 30,
      followUpReminderEnabled: (fields[14] as bool?) ?? false,
      weeklyOrderGoal: fields[15] as int?,
      weeklyWorkHoursGoal: (fields[16] as num?)?.toDouble(),
      defaultBreakDurationMinutes: (fields[17] as int?) ?? 30,
      notificationsEnabled: (fields[18] as bool?) ?? true,
      onboardingDone: (fields[19] as bool?) ?? false,
      themePreset: (fields[20] as int?) ?? 0,
      orderPrice: (fields[21] as num?)?.toDouble(),
      dailyFixedPay: (fields[22] as num?)?.toDouble(),
      photoPath: (fields[23] as String?) ?? '',
      readNotificationIds: (fields[24] as List?)?.cast<String>() ?? [],
      dismissedNotificationIds:
          (fields[25] as List?)?.cast<String>() ?? [],
      registered: (fields[26] as bool?) ?? false,
      autoNavMode: (fields[27] as int?) ?? 1,
      shiftEndReminderEnabled: (fields[28] as bool?) ?? false,
      developerModeUnlocked: (fields[29] as bool?) ?? false,
      distanceBonusEnabled: (fields[30] as bool?) ?? true,
      distanceBonusTier1Km: (fields[31] as num?)?.toDouble() ?? 12,
      distanceBonusTier1Egp: (fields[32] as num?)?.toDouble() ?? 5,
      distanceBonusTier2Km: (fields[33] as num?)?.toDouble() ?? 15,
      distanceBonusTier2Egp: (fields[34] as num?)?.toDouble() ?? 10,
      distanceBonusTier3Km: (fields[35] as num?)?.toDouble() ?? 20,
      distanceBonusTier3Egp: (fields[36] as num?)?.toDouble() ?? 17,
      distanceBonusWeekOverrides:
          (fields[37] as Map?)?.cast<String, bool>() ?? {},
      flatOrderBonusEgp: (fields[38] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, UserSettings obj) {
    writer
      ..writeByte(39)
      ..writeByte(0)
      ..write(obj.displayName)
      ..writeByte(1)
      ..write(obj.languageCode)
      ..writeByte(2)
      ..write(obj.themeMode)
      ..writeByte(3)
      ..write(obj.dailyReminderHour)
      ..writeByte(4)
      ..write(obj.dailyReminderMinute)
      ..writeByte(5)
      ..write(obj.dailyReminderEnabled)
      ..writeByte(6)
      ..write(obj.scheduleReminderHour)
      ..writeByte(7)
      ..write(obj.scheduleReminderMinute)
      ..writeByte(8)
      ..write(obj.scheduleReminderEnabled)
      ..writeByte(9)
      ..write(obj.reportReminderHour)
      ..writeByte(10)
      ..write(obj.reportReminderMinute)
      ..writeByte(11)
      ..write(obj.reportReminderEnabled)
      ..writeByte(12)
      ..write(obj.followUpReminderHour)
      ..writeByte(13)
      ..write(obj.followUpReminderMinute)
      ..writeByte(14)
      ..write(obj.followUpReminderEnabled)
      ..writeByte(15)
      ..write(obj.weeklyOrderGoal)
      ..writeByte(16)
      ..write(obj.weeklyWorkHoursGoal)
      ..writeByte(17)
      ..write(obj.defaultBreakDurationMinutes)
      ..writeByte(18)
      ..write(obj.notificationsEnabled)
      ..writeByte(19)
      ..write(obj.onboardingDone)
      ..writeByte(20)
      ..write(obj.themePreset)
      ..writeByte(21)
      ..write(obj.orderPrice)
      ..writeByte(22)
      ..write(obj.dailyFixedPay)
      ..writeByte(23)
      ..write(obj.photoPath)
      ..writeByte(24)
      ..write(obj.readNotificationIds)
      ..writeByte(25)
      ..write(obj.dismissedNotificationIds)
      ..writeByte(26)
      ..write(obj.registered)
      ..writeByte(27)
      ..write(obj.autoNavMode)
      ..writeByte(28)
      ..write(obj.shiftEndReminderEnabled)
      ..writeByte(29)
      ..write(obj.developerModeUnlocked)
      ..writeByte(30)
      ..write(obj.distanceBonusEnabled)
      ..writeByte(31)
      ..write(obj.distanceBonusTier1Km)
      ..writeByte(32)
      ..write(obj.distanceBonusTier1Egp)
      ..writeByte(33)
      ..write(obj.distanceBonusTier2Km)
      ..writeByte(34)
      ..write(obj.distanceBonusTier2Egp)
      ..writeByte(35)
      ..write(obj.distanceBonusTier3Km)
      ..writeByte(36)
      ..write(obj.distanceBonusTier3Egp)
      ..writeByte(37)
      ..write(obj.distanceBonusWeekOverrides)
      ..writeByte(38)
      ..write(obj.flatOrderBonusEgp);
  }
}

// ---------------------------------------------------------------------------
// DailySchedule (typeId 1)
// ---------------------------------------------------------------------------

@HiveType(typeId: 1)
class DailySchedule extends HiveObject {
  @HiveField(0)
  String dateKey; // yyyy-MM-dd
  @HiveField(1)
  bool isWorkingDay;
  @HiveField(2)
  int startMinutes; // minutes since midnight
  @HiveField(3)
  int endMinutes; // minutes since midnight (<= start => overnight)
  @HiveField(4)
  int breakDurationMinutes;
  @HiveField(5)
  String notes;

  DailySchedule({
    required this.dateKey,
    this.isWorkingDay = true,
    this.startMinutes = 9 * 60,
    this.endMinutes = 17 * 60,
    this.breakDurationMinutes = 30,
    this.notes = '',
  });

  /// Net planned minutes for this day (0 when it is a day off).
  int get netPlannedMinutes {
    if (!isWorkingDay) return 0;
    var end = endMinutes;
    if (end <= startMinutes) end += 24 * 60;
    final gross = end - startMinutes;
    return gross - breakDurationMinutes.clamp(0, gross);
  }
}

class DailyScheduleAdapter extends TypeAdapter<DailySchedule> {
  @override
  final int typeId = 1;

  @override
  DailySchedule read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DailySchedule(
      dateKey: fields[0] as String,
      isWorkingDay: (fields[1] as bool?) ?? true,
      startMinutes: (fields[2] as int?) ?? 9 * 60,
      endMinutes: (fields[3] as int?) ?? 17 * 60,
      breakDurationMinutes: (fields[4] as int?) ?? 30,
      notes: (fields[5] as String?) ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, DailySchedule obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.dateKey)
      ..writeByte(1)
      ..write(obj.isWorkingDay)
      ..writeByte(2)
      ..write(obj.startMinutes)
      ..writeByte(3)
      ..write(obj.endMinutes)
      ..writeByte(4)
      ..write(obj.breakDurationMinutes)
      ..writeByte(5)
      ..write(obj.notes);
  }
}

// ---------------------------------------------------------------------------
// WorkSchedule (typeId 2)
// ---------------------------------------------------------------------------

@HiveType(typeId: 2)
class WorkSchedule extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String weekStartKey; // Sunday yyyy-MM-dd
  @HiveField(2)
  String weekEndKey; // Saturday yyyy-MM-dd
  @HiveField(3)
  List<DailySchedule> dailySchedules;
  @HiveField(4)
  int createdAtMillis;
  @HiveField(5)
  int updatedAtMillis;

  WorkSchedule({
    required this.id,
    required this.weekStartKey,
    required this.weekEndKey,
    required this.dailySchedules,
    required this.createdAtMillis,
    required this.updatedAtMillis,
  });

  double get totalPlannedHours =>
      dailySchedules.fold<int>(0, (s, d) => s + d.netPlannedMinutes) / 60.0;
}

class WorkScheduleAdapter extends TypeAdapter<WorkSchedule> {
  @override
  final int typeId = 2;

  @override
  WorkSchedule read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WorkSchedule(
      id: fields[0] as String,
      weekStartKey: fields[1] as String,
      weekEndKey: fields[2] as String,
      dailySchedules:
          (fields[3] as List?)?.cast<DailySchedule>() ?? <DailySchedule>[],
      createdAtMillis: (fields[4] as int?) ?? 0,
      updatedAtMillis: (fields[5] as int?) ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, WorkSchedule obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.weekStartKey)
      ..writeByte(2)
      ..write(obj.weekEndKey)
      ..writeByte(3)
      ..write(obj.dailySchedules)
      ..writeByte(4)
      ..write(obj.createdAtMillis)
      ..writeByte(5)
      ..write(obj.updatedAtMillis);
  }
}

// ---------------------------------------------------------------------------
// DailyOrderRecord (typeId 3)
// ---------------------------------------------------------------------------

@HiveType(typeId: 3)
class DailyOrderRecord extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String dateKey; // yyyy-MM-dd (unique)
  @HiveField(2)
  int completedOrders; // >= 0 ; zero is a valid recorded value
  @HiveField(3)
  String notes;
  @HiveField(4)
  bool isConfirmed;
  @HiveField(5)
  int createdAtMillis;
  @HiveField(6)
  int updatedAtMillis;
  @HiveField(7)
  List<OrderEntry> entries; // per-order details (may be empty)

  DailyOrderRecord({
    required this.id,
    required this.dateKey,
    required this.completedOrders,
    this.notes = '',
    this.isConfirmed = true,
    required this.createdAtMillis,
    required this.updatedAtMillis,
    List<OrderEntry>? entries,
  })  : entries = entries ?? [],
        assert(completedOrders >= 0, 'completedOrders cannot be negative');

  /// Total km driven going (out) across detailed entries.
  /// Prefers GPS-tracked values when available.
  double get totalKmOut =>
      entries.fold<double>(0, (s, e) => s + e.effectiveKmOut);

  /// Total km driven returning (back) across detailed entries.
  /// Prefers GPS-tracked values when available.
  double get totalKmBack =>
      entries.fold<double>(0, (s, e) => s + e.effectiveKmBack);

  /// Total km (out + back) across detailed entries.
  double get totalKm => totalKmOut + totalKmBack;
}

class DailyOrderRecordAdapter extends TypeAdapter<DailyOrderRecord> {
  @override
  final int typeId = 3;

  @override
  DailyOrderRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DailyOrderRecord(
      id: fields[0] as String,
      dateKey: fields[1] as String,
      completedOrders: (fields[2] as int?) ?? 0,
      notes: (fields[3] as String?) ?? '',
      isConfirmed: (fields[4] as bool?) ?? true,
      createdAtMillis: (fields[5] as int?) ?? 0,
      updatedAtMillis: (fields[6] as int?) ?? 0,
      entries: (fields[7] as List?)?.cast<OrderEntry>() ?? <OrderEntry>[],
    );
  }

  @override
  void write(BinaryWriter writer, DailyOrderRecord obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.dateKey)
      ..writeByte(2)
      ..write(obj.completedOrders)
      ..writeByte(3)
      ..write(obj.notes)
      ..writeByte(4)
      ..write(obj.isConfirmed)
      ..writeByte(5)
      ..write(obj.createdAtMillis)
      ..writeByte(6)
      ..write(obj.updatedAtMillis)
      ..writeByte(7)
      ..write(obj.entries);
  }
}

// ---------------------------------------------------------------------------
// OrderEntry (typeId 6): one delivery order with its driven distance.
// ---------------------------------------------------------------------------

/// A single delivery order entry: when it happened and how many kilometers
/// were driven going (out) and returning (back).
@HiveType(typeId: 6)
class OrderEntry extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String dateKey; // work-day yyyy-MM-dd this entry belongs to
  @HiveField(2)
  int timestampMillis; // when the order was completed
  @HiveField(3)
  double kmOut; // km driven going (>= 0)
  @HiveField(4)
  double kmBack; // km driven returning (>= 0)
  @HiveField(5)
  String notes;
  // --- GPS-tracked delivery lifecycle (v4) ---
  @HiveField(6)
  int status; // 0=pending, 1=toCustomer, 2=toMart, 3=completed
  @HiveField(7)
  int? pickupTimeMillis; // "بدأ التوصيل" pressed
  @HiveField(8)
  int? deliveredTimeMillis; // "وصلت للعميل" pressed
  @HiveField(9)
  int? martArrivedTimeMillis; // "وصلت للمارت" pressed
  @HiveField(10)
  double gpsKmOut; // GPS-calculated outgoing km
  @HiveField(11)
  double gpsKmBack; // GPS-calculated return km
  @HiveField(12)
  int outgoingDurationSec; // outgoing trip duration
  @HiveField(13)
  int returnDurationSec; // return trip duration
  // --- GPS route polylines (v5): downsampled breadcrumb trail ---
  @HiveField(14)
  List<double> routeOutLat;
  @HiveField(15)
  List<double> routeOutLng;
  @HiveField(16)
  List<double> routeBackLat;
  @HiveField(17)
  List<double> routeBackLng;
  // --- Snapped road geometry (v6): actual street path from OSRM ---
  @HiveField(18)
  List<double> roadOutLat;
  @HiveField(19)
  List<double> roadOutLng;
  @HiveField(20)
  List<double> roadBackLat;
  @HiveField(21)
  List<double> roadBackLng;
  // --- Optional phone number (v11) ---
  @HiveField(22)
  String phone;
  // --- Count-only bulk entry (v27.1) ---
  @HiveField(23)
  bool countOnly;
  // --- Manual per-order bonus (v27.5) ---
  @HiveField(24)
  double manualBonusEgp; // plain EGP bonus on this order; 0 = none

  OrderEntry({
    required this.id,
    required this.dateKey,
    required this.timestampMillis,
    this.kmOut = 0,
    this.kmBack = 0,
    this.notes = '',
    this.status = 0,
    this.pickupTimeMillis,
    this.deliveredTimeMillis,
    this.martArrivedTimeMillis,
    this.gpsKmOut = 0,
    this.gpsKmBack = 0,
    this.outgoingDurationSec = 0,
    this.returnDurationSec = 0,
    this.routeOutLat = const [],
    this.routeOutLng = const [],
    this.routeBackLat = const [],
    this.routeBackLng = const [],
    this.roadOutLat = const [],
    this.roadOutLng = const [],
    this.roadBackLat = const [],
    this.roadBackLng = const [],
    this.phone = '',
    this.countOnly = false,
    this.manualBonusEgp = 0,
  })  : assert(kmOut >= 0, 'kmOut cannot be negative'),
        assert(kmBack >= 0, 'kmBack cannot be negative');

  double get kmTotal => kmOut + kmBack;

  /// Effective outgoing km: GPS value when tracked, else manual.
  double get effectiveKmOut => gpsKmOut > 0 ? gpsKmOut : kmOut;
  double get effectiveKmBack => gpsKmBack > 0 ? gpsKmBack : kmBack;
  double get effectiveKmTotal => effectiveKmOut + effectiveKmBack;

  /// True when this leg's distance came from manual entry (GPS produced
  /// nothing). Used for the "يدوي" badge so reports distinguish GPS vs
  /// manual distances.
  bool get isManualOut => gpsKmOut == 0 && kmOut > 0;
  bool get isManualBack => gpsKmBack == 0 && kmBack > 0;
  bool get hasManualKm => isManualOut || isManualBack;

  bool get isPending => status == 0;
  bool get isToCustomer => status == 1;
  bool get isToMart => status == 2;
  bool get isCompleted => status == 3;
  bool get isTracking => status == 1 || status == 2;

  /// Number of recorded route points (outgoing + return).
  int get routePointCount =>
      routeOutLat.length + routeBackLat.length;

  bool get hasRoute =>
      routeOutLat.isNotEmpty || routeBackLat.isNotEmpty;

  /// Prefers the OSRM-snapped road path; falls back to raw GPS trail.
  List<double> get displayOutLat =>
      roadOutLat.isNotEmpty ? roadOutLat : routeOutLat;
  List<double> get displayOutLng =>
      roadOutLng.isNotEmpty ? roadOutLng : routeOutLng;
  List<double> get displayBackLat =>
      roadBackLat.isNotEmpty ? roadBackLat : routeBackLat;
  List<double> get displayBackLng =>
      roadBackLng.isNotEmpty ? roadBackLng : routeBackLng;

  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(timestampMillis);

  Map<String, dynamic> toJson() => {
        'id': id,
        'dateKey': dateKey,
        'timestampMillis': timestampMillis,
        'kmOut': kmOut,
        'kmBack': kmBack,
        'notes': notes,
        'status': status,
        'pickupTimeMillis': pickupTimeMillis,
        'deliveredTimeMillis': deliveredTimeMillis,
        'martArrivedTimeMillis': martArrivedTimeMillis,
        'gpsKmOut': gpsKmOut,
        'gpsKmBack': gpsKmBack,
        'outgoingDurationSec': outgoingDurationSec,
        'returnDurationSec': returnDurationSec,
        'routeOutLat': routeOutLat,
        'routeOutLng': routeOutLng,
        'routeBackLat': routeBackLat,
        'routeBackLng': routeBackLng,
        'roadOutLat': roadOutLat,
        'roadOutLng': roadOutLng,
        'roadBackLat': roadBackLat,
        'roadBackLng': roadBackLng,
        'phone': phone,
        'countOnly': countOnly,
        'manualBonusEgp': manualBonusEgp,
      };

  static OrderEntry fromJson(Map<String, dynamic> json) => OrderEntry(
        id: json['id'] as String,
        dateKey: json['dateKey'] as String,
        timestampMillis: (json['timestampMillis'] as num).toInt(),
        kmOut: (json['kmOut'] as num?)?.toDouble() ?? 0,
        kmBack: (json['kmBack'] as num?)?.toDouble() ?? 0,
        notes: (json['notes'] as String?) ?? '',
        status: (json['status'] as num?)?.toInt() ?? 0,
        pickupTimeMillis: (json['pickupTimeMillis'] as num?)?.toInt(),
        deliveredTimeMillis: (json['deliveredTimeMillis'] as num?)?.toInt(),
        martArrivedTimeMillis: (json['martArrivedTimeMillis'] as num?)?.toInt(),
        gpsKmOut: (json['gpsKmOut'] as num?)?.toDouble() ?? 0,
        gpsKmBack: (json['gpsKmBack'] as num?)?.toDouble() ?? 0,
        outgoingDurationSec: (json['outgoingDurationSec'] as num?)?.toInt() ?? 0,
        returnDurationSec: (json['returnDurationSec'] as num?)?.toInt() ?? 0,
        routeOutLat: (json['routeOutLat'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            const [],
        routeOutLng: (json['routeOutLng'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            const [],
        routeBackLat: (json['routeBackLat'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            const [],
        routeBackLng: (json['routeBackLng'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            const [],
        roadOutLat: (json['roadOutLat'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            const [],
        roadOutLng: (json['roadOutLng'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            const [],
        roadBackLat: (json['roadBackLat'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            const [],
        roadBackLng: (json['roadBackLng'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            const [],
        phone: (json['phone'] as String?) ?? '',
        countOnly: (json['countOnly'] as bool?) ?? false,
        manualBonusEgp: (json['manualBonusEgp'] as num?)?.toDouble() ?? 0,
      );
}

class OrderEntryAdapter extends TypeAdapter<OrderEntry> {
  @override
  final int typeId = 6;

  @override
  OrderEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OrderEntry(
      id: fields[0] as String,
      dateKey: fields[1] as String,
      timestampMillis: (fields[2] as int?) ?? 0,
      kmOut: (fields[3] as num?)?.toDouble() ?? 0,
      kmBack: (fields[4] as num?)?.toDouble() ?? 0,
      notes: (fields[5] as String?) ?? '',
      status: (fields[6] as int?) ?? 0,
      pickupTimeMillis: fields[7] as int?,
      deliveredTimeMillis: fields[8] as int?,
      martArrivedTimeMillis: fields[9] as int?,
      gpsKmOut: (fields[10] as num?)?.toDouble() ?? 0,
      gpsKmBack: (fields[11] as num?)?.toDouble() ?? 0,
      outgoingDurationSec: (fields[12] as int?) ?? 0,
      returnDurationSec: (fields[13] as int?) ?? 0,
      routeOutLat: (fields[14] as List?)?.cast<double>() ?? const [],
      routeOutLng: (fields[15] as List?)?.cast<double>() ?? const [],
      routeBackLat: (fields[16] as List?)?.cast<double>() ?? const [],
      routeBackLng: (fields[17] as List?)?.cast<double>() ?? const [],
      roadOutLat: (fields[18] as List?)?.cast<double>() ?? const [],
      roadOutLng: (fields[19] as List?)?.cast<double>() ?? const [],
      roadBackLat: (fields[20] as List?)?.cast<double>() ?? const [],
      roadBackLng: (fields[21] as List?)?.cast<double>() ?? const [],
      phone: (fields[22] as String?) ?? '',
      countOnly: (fields[23] as bool?) ?? false,
      manualBonusEgp: (fields[24] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, OrderEntry obj) {
    writer
      ..writeByte(25)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.dateKey)
      ..writeByte(2)
      ..write(obj.timestampMillis)
      ..writeByte(3)
      ..write(obj.kmOut)
      ..writeByte(4)
      ..write(obj.kmBack)
      ..writeByte(5)
      ..write(obj.notes)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.pickupTimeMillis)
      ..writeByte(8)
      ..write(obj.deliveredTimeMillis)
      ..writeByte(9)
      ..write(obj.martArrivedTimeMillis)
      ..writeByte(10)
      ..write(obj.gpsKmOut)
      ..writeByte(11)
      ..write(obj.gpsKmBack)
      ..writeByte(12)
      ..write(obj.outgoingDurationSec)
      ..writeByte(13)
      ..write(obj.returnDurationSec)
      ..writeByte(14)
      ..write(obj.routeOutLat)
      ..writeByte(15)
      ..write(obj.routeOutLng)
      ..writeByte(16)
      ..write(obj.routeBackLat)
      ..writeByte(17)
      ..write(obj.routeBackLng)
      ..writeByte(18)
      ..write(obj.roadOutLat)
      ..writeByte(19)
      ..write(obj.roadOutLng)
      ..writeByte(20)
      ..write(obj.roadBackLat)
      ..writeByte(21)
      ..write(obj.roadBackLng)
      ..writeByte(22)
      ..write(obj.phone)
      ..writeByte(23)
      ..write(obj.countOnly)
      ..writeByte(24)
      ..write(obj.manualBonusEgp);
  }
}

// ---------------------------------------------------------------------------
// BreakInterval (typeId 4) + WorkSession (typeId 5)
// ---------------------------------------------------------------------------

@HiveType(typeId: 4)
class BreakInterval extends HiveObject {
  @HiveField(0)
  int startMillis;
  @HiveField(1)
  int? endMillis; // null => break still in progress

  BreakInterval({required this.startMillis, this.endMillis});

  int get durationMillis =>
      (endMillis ?? DateTime.now().millisecondsSinceEpoch) - startMillis;
}

class BreakIntervalAdapter extends TypeAdapter<BreakInterval> {
  @override
  final int typeId = 4;

  @override
  BreakInterval read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BreakInterval(
      startMillis: fields[0] as int,
      endMillis: fields[1] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, BreakInterval obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.startMillis)
      ..writeByte(1)
      ..write(obj.endMillis);
  }
}

@HiveType(typeId: 5)
class WorkSession extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String dateKey; // calendar date the session belongs to
  @HiveField(2)
  int startMillis;
  @HiveField(3)
  int? endMillis; // null => session still active
  @HiveField(4)
  List<BreakInterval> breaks;
  @HiveField(5)
  String notes;
  @HiveField(6)
  int status; // 0=active, 1=onBreak, 2=finished
  // Manual-entry support:
  @HiveField(7)
  int? manualStartMinutes; // minutes since midnight
  @HiveField(8)
  int? manualEndMinutes;
  @HiveField(9)
  int manualBreakMinutes;
  @HiveField(10)
  bool isManual;

  WorkSession({
    required this.id,
    required this.dateKey,
    required this.startMillis,
    this.endMillis,
    List<BreakInterval>? breaks,
    this.notes = '',
    this.status = 0,
    this.manualStartMinutes,
    this.manualEndMinutes,
    this.manualBreakMinutes = 0,
    this.isManual = false,
  }) : breaks = breaks ?? [];

  bool get isActive => status == 0 || status == 1;
  bool get isOnBreak => status == 1;

  int get breakMillis =>
      breaks.fold<int>(0, (s, b) => s + b.durationMillis);

  /// Net working milliseconds for timer sessions.
  int get netMillis {
    final end = endMillis ?? DateTime.now().millisecondsSinceEpoch;
    return (end - startMillis) - breakMillis;
  }

  /// Net working minutes (timer or manual).
  int get netMinutes {
    if (isManual) {
      final s = manualStartMinutes ?? 0;
      var e = manualEndMinutes ?? 0;
      if (e <= s) e += 24 * 60;
      final gross = e - s;
      return gross - manualBreakMinutes.clamp(0, gross);
    }
    return (netMillis / 60000).round().clamp(0, 1 << 30);
  }
}

class WorkSessionAdapter extends TypeAdapter<WorkSession> {
  @override
  final int typeId = 5;

  @override
  WorkSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WorkSession(
      id: fields[0] as String,
      dateKey: fields[1] as String,
      startMillis: fields[2] as int,
      endMillis: fields[3] as int?,
      breaks: (fields[4] as List?)?.cast<BreakInterval>() ?? [],
      notes: (fields[5] as String?) ?? '',
      status: (fields[6] as int?) ?? 0,
      manualStartMinutes: fields[7] as int?,
      manualEndMinutes: fields[8] as int?,
      manualBreakMinutes: (fields[9] as int?) ?? 0,
      isManual: (fields[10] as bool?) ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, WorkSession obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.dateKey)
      ..writeByte(2)
      ..write(obj.startMillis)
      ..writeByte(3)
      ..write(obj.endMillis)
      ..writeByte(4)
      ..write(obj.breaks)
      ..writeByte(5)
      ..write(obj.notes)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.manualStartMinutes)
      ..writeByte(8)
      ..write(obj.manualEndMinutes)
      ..writeByte(9)
      ..write(obj.manualBreakMinutes)
      ..writeByte(10)
      ..write(obj.isManual);
  }
}

// ---------------------------------------------------------------------------
// WeeklyReport (derived, not stored)
// ---------------------------------------------------------------------------

/// v26 auto work-hours rule (derived only — stored data is never rewritten):
/// when a day has NO recorded session minutes but at least one logged order
/// and a planned working schedule, the day's net planned minutes count as
/// worked. A recorded session always wins; a day off or a day with zero /
/// unrecorded orders earns no automatic credit.
int effectiveWorkMinutes({
  required int recordedMinutes,
  required int? orders,
  required DailySchedule? schedule,
}) {
  if (recordedMinutes > 0) return recordedMinutes;
  if (schedule == null || !schedule.isWorkingDay) return 0;
  if (orders == null || orders < 1) return 0;
  return schedule.netPlannedMinutes;
}

/// v27 migration helper: a record's counted total under the
/// count-on-start rule. Before v27 every created entry incremented the
/// stored total immediately, so the total's non-entry part (bulk-count
/// base) is `storedTotal - entries.length`; under the new rule only
/// entries whose delivery started (status >= 1) count.
int recomputedCountedOrders(DailyOrderRecord record) {
  final bulkBase = record.completedOrders - record.entries.length;
  final started = record.entries.where((e) => e.status >= 1).length;
  return (bulkBase < 0 ? 0 : bulkBase) + started;
}

/// v27.1 migration helper: builds the count-only entries that replace a
/// record's legacy "undetailed" remainder — orders present in the
/// stored total but backed by no counted entry (before v27.1 a bulk log
/// stored ONLY the number, so such days showed 0/0 in the report's
/// entry-based day summary). The remainder is
/// `completedOrders - entries(status >= 1)`, clamped at 0. The built
/// entries are born completed (status 3) at the record day's local
/// noon, so their place in the day's list is stable and the stored
/// total never changes — each new entry is already inside it.
List<OrderEntry> countOnlyEntriesForLegacyRemainder(
    DailyOrderRecord record) {
  final counted = record.entries.where((e) => e.status >= 1).length;
  final remainder = record.completedOrders - counted;
  if (remainder <= 0) return const [];
  final parts = record.dateKey.split('-');
  final noon = DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
    12,
  );
  return [
    for (var i = 0; i < remainder; i++)
      OrderEntry(
        id: 'oe_mig_${record.dateKey}_$i',
        dateKey: record.dateKey,
        timestampMillis: noon.millisecondsSinceEpoch,
        status: 3,
        countOnly: true,
      ),
  ];
}

/// Derived tallies for the weekly report's day-summary card (v27.1).
/// [completed] and [total] additionally include the day's undetailed
/// remainder (counted orders with no counted entry — e.g. a legacy
/// bulk log not yet converted by the schema-11 migration), so a
/// bulk-only day never renders as 0/0.
({int completed, int inProgress, int pending, int total}) daySummaryTallies(
    DailyOrderRecord? record) {
  final entries = record?.entries ?? const <OrderEntry>[];
  final counted = entries.where((e) => e.status >= 1).length;
  var undetailed = (record?.completedOrders ?? 0) - counted;
  if (undetailed < 0) undetailed = 0;
  return (
    completed: entries.where((e) => e.status == 3).length + undetailed,
    inProgress:
        entries.where((e) => e.status == 1 || e.status == 2).length,
    pending: entries.where((e) => e.status == 0).length,
    total: entries.length + undetailed,
  );
}

/// Derived day status for report rows (v27) — computed live from the
/// day's data, never stored, so it flips automatically when orders are
/// added or deleted:
///
/// - At least one counted order -> a work day, whatever the schedule
///   says (even a scheduled day off that got worked).
/// - No counted orders, today or in the past -> a day off.
/// - No counted orders, in the future -> a day off only when the
///   schedule says so; a scheduled future work day gets no label yet.
enum DayStatus { workDay, dayOff, none }

DayStatus dayStatusFor({
  required int? orders,
  required bool isWorkingDay,
  required DateTime date,
  required DateTime today,
}) {
  if (orders != null && orders >= 1) return DayStatus.workDay;
  final d = DateTime(date.year, date.month, date.day);
  final t = DateTime(today.year, today.month, today.day);
  if (!d.isAfter(t)) return DayStatus.dayOff;
  return isWorkingDay ? DayStatus.none : DayStatus.dayOff;
}

/// Status chip for a day row on the weekly SCHEDULE screen (v27.3).
enum ScheduleDayChip { completed, inProgress, dayOff, notStarted }

/// Which chip the schedule screen shows for a day. Builds on
/// [dayStatusFor] (the report's single source of truth) with one
/// schedule-specific adjustment: today is not over yet, so a
/// scheduled WORKING day with no counted orders so far is still
/// "not started" — it only earns the day-off chip when the plan
/// itself marks the day off. A past day that ended with no counted
/// orders, and a plan-marked off day on any date, show day off.
ScheduleDayChip scheduleDayChipFor({
  required int countedOrders,
  required bool isWorkingDay,
  required bool workStartedToday,
  required DateTime date,
  required DateTime today,
}) {
  final status = dayStatusFor(
    orders: countedOrders,
    isWorkingDay: isWorkingDay,
    date: date,
    today: today,
  );
  if (status == DayStatus.workDay) return ScheduleDayChip.completed;
  final d = DateTime(date.year, date.month, date.day);
  final t = DateTime(today.year, today.month, today.day);
  final isToday = d == t;
  if (isToday && workStartedToday) return ScheduleDayChip.inProgress;
  if (status == DayStatus.dayOff && !(isToday && isWorkingDay)) {
    return ScheduleDayChip.dayOff;
  }
  return ScheduleDayChip.notStarted;
}

/// One distance-bonus tier (v27.5): a completed order whose round-trip
/// distance reaches [fromKm] earns [bonusEgp] on top of its order pay.
class DistanceBonusTier {
  final double fromKm;
  final double bonusEgp;

  const DistanceBonusTier({required this.fromKm, required this.bonusEgp});
}

/// Pure distance-bonus resolution (v27.5): the bonus of the HIGHEST
/// tier whose threshold the round-trip distance reaches. Returns 0
/// below the first threshold, when the distance is missing or zero
/// (count-only entries and orders without a finalized distance earn
/// no distance bonus), and when the feature is off for the week being
/// computed. Tier order in [tiers] does not matter.
double distanceBonusFor(
  double? roundTripKm,
  List<DistanceBonusTier> tiers, {
  bool enabled = true,
}) {
  if (!enabled) return 0;
  final km = roundTripKm ?? 0;
  if (km <= 0) return 0;
  var best = 0.0;
  var bestFrom = double.negativeInfinity;
  for (final t in tiers) {
    if (km >= t.fromKm && t.fromKm >= bestFrom) {
      bestFrom = t.fromKm;
      best = t.bonusEgp;
    }
  }
  return best;
}

class DayBreakdown {
  final String dateKey;
  final int? orders; // null => unrecorded
  final int workMinutes; // effective minutes (recorded, else v26 auto-hours)
  final double plannedHours;
  final bool isWorkingDay;
  final double kmOut; // detailed entries only
  final double kmBack; // detailed entries only

  /// v27.5: Σ distance bonuses of the day's completed orders (0 when
  /// the feature is off for the day's week).
  final double distanceBonus;

  /// v27.5: Σ manual per-order bonuses of the day's counted orders —
  /// independent of the distance-bonus toggles.
  final double manualBonus;

  /// v27.6: Σ flat per-order bonuses of the day — counted orders ×
  /// the settings' flat amount (0 when the flat bonus is off).
  final double flatBonus;

  const DayBreakdown({
    required this.dateKey,
    required this.orders,
    required this.workMinutes,
    required this.plannedHours,
    required this.isWorkingDay,
    this.kmOut = 0,
    this.kmBack = 0,
    this.distanceBonus = 0,
    this.manualBonus = 0,
    this.flatBonus = 0,
  });

  double get kmTotal => kmOut + kmBack;
}

class WeeklyReport {
  final String weekStartKey;
  final String weekEndKey;
  final int totalOrders;
  final double totalRecordedHours;
  final double totalPlannedHours;
  final List<DayBreakdown> days;
  final double? averageOrdersPerWorkingDay;
  final double? averageHoursPerWorkingDay;
  final double? ordersPerWorkingHour;
  final String? bestDayKey;
  final List<String> missingRecordDates;
  final int recordedDaysCount;

  /// v27: days that earn the salary's daily fixed pay — days with at
  /// least one counted order (completedOrders >= 1). A record holding
  /// 0 orders, or a session-only day, does NOT earn the daily fixed pay.
  final int paidDaysCount;
  final double totalKmOut;
  final double totalKmBack;

  /// v27.5: Σ distance bonuses across the week (already resolved
  /// against the week's effective on/off flag — 0 when off).
  final double totalDistanceBonus;

  /// v27.5: Σ manual per-order bonuses across the week.
  final double totalManualBonus;

  /// v27.5: the week's EFFECTIVE distance-bonus flag (per-week
  /// override ?? global default), resolved when the report was built,
  /// so displays never disagree with the totals.
  final bool distanceBonusEnabled;

  /// v27.6: the flat bonus paid per counted order (EGP), resolved
  /// from the settings when the report was built (0 = off).
  final double flatOrderBonusEgp;

  const WeeklyReport({
    required this.weekStartKey,
    required this.weekEndKey,
    required this.totalOrders,
    required this.totalRecordedHours,
    required this.totalPlannedHours,
    required this.days,
    required this.averageOrdersPerWorkingDay,
    required this.averageHoursPerWorkingDay,
    required this.ordersPerWorkingHour,
    required this.bestDayKey,
    required this.missingRecordDates,
    required this.recordedDaysCount,
    this.paidDaysCount = 0,
    this.totalKmOut = 0,
    this.totalKmBack = 0,
    this.totalDistanceBonus = 0,
    this.totalManualBonus = 0,
    this.distanceBonusEnabled = true,
    this.flatOrderBonusEgp = 0,
  });

  double get totalKm => totalKmOut + totalKmBack;

  /// v27.6: Σ flat per-order bonuses — every counted order (detailed
  /// completed AND count-only) earns the flat amount.
  double get totalFlatBonus => totalOrders * flatOrderBonusEgp;

  /// THE salary formula (v27.5, extended v27.6) — the single
  /// computation every earnings surface uses (weekly report card,
  /// Home card, PDF export): counted orders × order price + paid
  /// days × daily fixed pay + distance bonuses + manual bonuses +
  /// flat per-order bonuses.
  double salaryTotal({
    required double orderPrice,
    required double dailyFixedPay,
  }) =>
      totalOrders * orderPrice +
      paidDaysCount * dailyFixedPay +
      totalDistanceBonus +
      totalManualBonus +
      totalFlatBonus;
}
