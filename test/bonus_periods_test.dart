import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:deliveryflow/features/weekly_reports/past_weeks_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';

/// v27.17: instant-based bonus periods (supersedes the v27.16
/// date-based tests).
///
/// Mohamed's rule: the bonus is decided by each order's own
/// CREATION instant, not its calendar date. An order made at 10:00
/// while the bonus is on keeps it even if the bonus is deleted at
/// 11:00 — and an order made at 12:00 the same day gets 0.
/// Setting at T pays orders created >= T (0 before T, same day
/// included); deleting at D pays orders created < D (0 from D);
/// changing the amount at C splits orders at C.
///
/// The creation instant is OrderEntry.createdAtMillis (Hive field
/// 25), set once at insertion — never timestampMillis, which the
/// tracking completion overwrites and the edit sheet changes.
/// Tests pass explicit creation instants via addOrderEntry's
/// createdAtMillis (test-only override; production always uses
/// "now").
///
/// Weeks used below (Sundays): 2026-10-18 and 2026-10-25.
int at(int y, int m, int d, [int h = 12, int min = 0]) =>
    DateTime(y, m, d, h, min).millisecondsSinceEpoch;

void main() {
  late Directory tmp;
  late DatabaseService db;

  Future<void> completeOrder(String dateKey,
      {int? createdAt,
      double kmOut = 3,
      double kmBack = 2,
      double? manual}) async {
    final e = await db.addOrderEntry(
      dateKey: dateKey,
      timestampMillis: createdAt ?? DateTime.now().millisecondsSinceEpoch,
      createdAtMillis: createdAt,
      kmOut: kmOut,
      kmBack: kmBack,
    );
    await db.updateOrderEntry(
        dateKey: dateKey,
        entryId: e.id,
        status: 3,
        manualBonusEgp: manual);
  }

  Future<void> applySettings(
      void Function(UserSettings s) change) async {
    final s = db.settings;
    change(s);
    await db.saveSettings(s);
  }

  setUp(() async {
    await initializeDateFormatting('en');
    tmp = await Directory.systemTemp.createTemp('df_bonus_periods_');
    db = DatabaseService();
    await db.init(hivePath: tmp.path);
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  group('fresh user: zero bonus everywhere until explicitly set', () {
    test('defaults are all zero/off with no periods', () {
      final s = UserSettings();
      expect(s.flatOrderBonusEgp, 0);
      expect(s.distanceBonusEnabled, isFalse);
      expect(s.flatBonusPeriods, isEmpty);
      expect(s.distanceBonusPeriods, isEmpty);
      expect(s.flatBonusAt(at(2026, 10, 25, 10)), 0);
      expect(s.distancePeriodAt(at(2026, 10, 25, 10)), isNull);
      expect(s.distanceBonusEnabledForOrder(
          at(2026, 10, 25, 10), '2026-10-25'), isFalse);
      // The freshly initialized database carries the same defaults.
      expect(db.settings.flatOrderBonusEgp, 0);
      expect(db.settings.distanceBonusEnabled, isFalse);
      expect(db.settings.flatBonusPeriods, isEmpty);
      expect(db.settings.distanceBonusPeriods, isEmpty);
      expect(db.settings.bonusPeriodsMigrated, isTrue);
    });

    test('report + PDF pay no bonus at all before any explicit set',
        () async {
      await completeOrder('2026-10-25', createdAt: at(2026, 10, 25, 9),
          kmOut: 8, kmBack: 7);
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 9),
          kmOut: 3, kmBack: 2);
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.totalOrders, 2);
      expect(r.totalFlatBonus, 0);
      expect(r.totalDistanceBonus, 0);
      expect(r.totalManualBonus, 0);
      expect(r.distanceBonusEnabled, isFalse);
      // 2 orders × 10 + 2 paid days × 100, nothing else.
      expect(r.salaryTotal(orderPrice: 10, dailyFixedPay: 100), 220);
      final pdf = PastWeeksReportBuilder(db).build(
          locale: 'en', orderPrice: 10, dailyFixedPay: 100);
      expect(pdf.weeks.single.totalEarnings, 220);
      expect(pdf.weeks.single.flatBonusTotal, 0);
    });
  });

  group('flat bonus periods (instant rule)', () {
    test('set at T: 0 before T, amount from T — same day splits',
        () async {
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 9));
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 10));
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 11));
      await applySettings(
          (s) => s.applyFlatBonus(5, at(2026, 10, 26, 10)));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      // All three orders share one day row: 0 + 5 + 5.
      expect(r.days[1].flatBonus, 10);
      expect(r.totalFlatBonus, 10);
      // The resolver itself: before T pays 0, at/after T pays 5.
      expect(db.settings.flatBonusAt(at(2026, 10, 26, 9, 59)), 0);
      expect(db.settings.flatBonusAt(at(2026, 10, 26, 10)), 5);
      // A previous week's order also pays 0.
      expect(db.settings.flatBonusAt(at(2026, 10, 19, 12)), 0);
    });

    test('change at C: old amount before C, new amount from C, '
        'same day', () async {
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 9));
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 11));
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 13));
      await applySettings(
          (s) => s.applyFlatBonus(5, at(2026, 10, 26, 8)));
      await applySettings(
          (s) => s.applyFlatBonus(8, at(2026, 10, 26, 12)));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.days[1].flatBonus, 5 + 5 + 8);
      expect(r.totalFlatBonus, 18);
    });

    test('MOHAMED CASE: delete at D keeps the morning order, '
        'zeroes the afternoon order, same day', () async {
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 10));
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 12));
      await applySettings(
          (s) => s.applyFlatBonus(5, at(2026, 10, 26, 9)));
      await applySettings(
          (s) => s.applyFlatBonus(0, at(2026, 10, 26, 11)));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      // v27.16 paid 0 for BOTH (whole deletion day lost). v27.17:
      // the 10:00 order keeps 5, the 12:00 order gets 0.
      expect(r.days[1].flatBonus, 5);
      expect(r.totalFlatBonus, 5);
      // The legacy current-value field reads 0 (deleted) while the
      // morning order still pays — display vs. salary differ by
      // design, and salary uses the periods.
      expect(db.settings.flatOrderBonusEgp, 0);
    });

    test('set then change at the SAME instant mutates in place',
        () async {
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 9));
      final t = at(2026, 10, 26, 8);
      await applySettings((s) => s.applyFlatBonus(5, t));
      await applySettings((s) => s.applyFlatBonus(8, t));
      expect(db.settings.flatBonusPeriods.length, 1);
      expect(db.settings.flatBonusAt(at(2026, 10, 26, 9)), 8);
      expect(db.settings.flatBonusAt(at(2026, 10, 25, 9)), 0);
    });

    test('the reported example: week before the set pays 0',
        () async {
      await completeOrder('2026-10-19', createdAt: at(2026, 10, 19, 10));
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 10));
      await applySettings(
          (s) => s.applyFlatBonus(5, at(2026, 10, 26, 9)));
      final oldWeek = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-19'));
      final newWeek = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-26'));
      expect(oldWeek.totalFlatBonus, 0);
      expect(newWeek.totalFlatBonus, 5);
    });

    test('creation instant, not completion/edit time, decides', () async {
      // Order created at 10:00 (bonus on), completed at 15:00
      // (after a deletion at 11:00) and later edited: its bonus
      // moment stays 10:00, so it keeps the bonus.
      final e = await db.addOrderEntry(
        dateKey: '2026-10-26',
        timestampMillis: at(2026, 10, 26, 10),
        createdAtMillis: at(2026, 10, 26, 10),
        kmOut: 3,
        kmBack: 2,
      );
      await applySettings(
          (s) => s.applyFlatBonus(5, at(2026, 10, 26, 9)));
      await applySettings(
          (s) => s.applyFlatBonus(0, at(2026, 10, 26, 11)));
      // Completion overwrites timestampMillis (tracking behaviour)
      // and an edit changes it again — neither moves createdAt.
      await db.updateOrderEntry(
          dateKey: '2026-10-26',
          entryId: e.id,
          status: 3,
          timestampMillis: at(2026, 10, 26, 15));
      await db.updateOrderEntry(
          dateKey: '2026-10-26',
          entryId: e.id,
          timestampMillis: at(2026, 10, 26, 16));
      final stored = db.orderEntries('2026-10-26').single;
      expect(stored.createdAtMillis, at(2026, 10, 26, 10));
      expect(stored.timestampMillis, at(2026, 10, 26, 16));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.totalFlatBonus, 5);
    });
  });

  group('distance bonus periods (instant rule)', () {
    test('enable at T: 0 before T, tiers from T — same day splits',
        () async {
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 9),
          kmOut: 8, kmBack: 7); // 15km
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 11),
          kmOut: 8, kmBack: 7);
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 12),
          kmOut: 3, kmBack: 2); // 5km
      await applySettings(
          (s) => s.applyDistanceToggle(true, at(2026, 10, 26, 10)));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.days[1].distanceBonus, 10); // only the 11:00 order
      expect(r.totalDistanceBonus, 10);
    });

    test('disable at D: tiers before D, 0 from D — same day splits',
        () async {
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 10),
          kmOut: 8, kmBack: 7);
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 12),
          kmOut: 8, kmBack: 7);
      await applySettings(
          (s) => s.applyDistanceToggle(true, at(2026, 10, 26, 9)));
      await applySettings(
          (s) => s.applyDistanceToggle(false, at(2026, 10, 26, 11)));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.days[1].distanceBonus, 10);
      expect(r.totalDistanceBonus, 10);
    });

    test('tier edit at C: old tiers before C, new tiers from C',
        () async {
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 10),
          kmOut: 8, kmBack: 7); // 15km
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 12),
          kmOut: 8, kmBack: 7);
      await applySettings(
          (s) => s.applyDistanceToggle(true, at(2026, 10, 26, 9)));
      // New tiers: 12km -> 7 (was 5), 15km -> 12 (was 10), 20km -> 20.
      await applySettings((s) => s.applyDistanceTiers([
            const DistanceBonusTier(fromKm: 12, bonusEgp: 7),
            const DistanceBonusTier(fromKm: 15, bonusEgp: 12),
            const DistanceBonusTier(fromKm: 20, bonusEgp: 20),
          ], at(2026, 10, 26, 11)));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.days[1].distanceBonus, 10 + 12);
    });

    test('tier edit while OFF creates no period and pays nothing',
        () async {
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 10),
          kmOut: 8, kmBack: 7);
      await applySettings((s) => s.applyDistanceTiers([
            const DistanceBonusTier(fromKm: 12, bonusEgp: 7),
            const DistanceBonusTier(fromKm: 15, bonusEgp: 12),
            const DistanceBonusTier(fromKm: 20, bonusEgp: 20),
          ], at(2026, 10, 26, 9)));
      expect(db.settings.distanceBonusPeriods, isEmpty);
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.totalDistanceBonus, 0);
    });
  });

  group('per-week overrides vs periods (reconciliation)', () {
    test('override ON outside a period pays nothing; inside it works',
        () async {
      await completeOrder('2026-10-19', createdAt: at(2026, 10, 19, 10),
          kmOut: 8, kmBack: 7);
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 10),
          kmOut: 8, kmBack: 7);
      // Period covers last week only (instant window); current
      // week gets an ON override anyway — it must NOT resurrect
      // the bonus there.
      await applySettings((s) {
        s.distanceBonusPeriods = [
          DistanceBonusPeriod(
              startMillis: startOfDayMillis('2026-10-18'),
              endMillis: startOfDayMillis('2026-10-25'),
              tiers: s.distanceBonusTiers),
        ];
        s.distanceBonusWeekOverrides = {'2026-10-25': true};
      });
      final oldWeek = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-19'));
      final newWeek = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-26'));
      expect(oldWeek.totalDistanceBonus, 10);
      expect(newWeek.totalDistanceBonus, 0);
      expect(newWeek.distanceBonusEnabled, isFalse);
    });

    test('override OFF inside a period zeroes only that week',
        () async {
      await completeOrder('2026-10-19', createdAt: at(2026, 10, 19, 10),
          kmOut: 8, kmBack: 7);
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 10),
          kmOut: 8, kmBack: 7);
      await applySettings(
          (s) => s.applyDistanceToggle(true, at(2026, 10, 18, 9)));
      await applySettings((s) {
        s.distanceBonusWeekOverrides = {'2026-10-25': false};
      });
      expect(
          db
              .buildWeeklyReport(WeekCalendar.parseDateKey('2026-10-19'))
              .totalDistanceBonus,
          10);
      expect(
          db
              .buildWeeklyReport(WeekCalendar.parseDateKey('2026-10-26'))
              .totalDistanceBonus,
          0);
      // Clearing the override restores the period default.
      await applySettings((s) {
        s.distanceBonusWeekOverrides = {};
      });
      expect(
          db
              .buildWeeklyReport(WeekCalendar.parseDateKey('2026-10-26'))
              .totalDistanceBonus,
          10);
    });

    test('override ON does not extend a closed period into a new week',
        () async {
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 10),
          kmOut: 8, kmBack: 7);
      await completeOrder('2026-11-02', createdAt: at(2026, 11, 2, 10),
          kmOut: 8, kmBack: 7);
      await applySettings(
          (s) => s.applyDistanceToggle(true, at(2026, 10, 25, 9)));
      await applySettings(
          (s) => s.applyDistanceToggle(false, at(2026, 11, 1, 9)));
      await applySettings((s) {
        s.distanceBonusWeekOverrides = {'2026-11-01': true};
      });
      expect(
          db
              .buildWeeklyReport(WeekCalendar.parseDateKey('2026-10-26'))
              .totalDistanceBonus,
          10);
      expect(
          db
              .buildWeeklyReport(WeekCalendar.parseDateKey('2026-11-02'))
              .totalDistanceBonus,
          0);
    });
  });

  group('manual bonus isolation (no model change needed)', () {
    test('one order’s bonus never appears on any other order/day',
        () async {
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 10),
          manual: 25);
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 11));
      await completeOrder('2026-10-27', createdAt: at(2026, 10, 27, 10));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.days[1].manualBonus, 25);
      expect(r.days[2].manualBonus, 0);
      expect(r.totalManualBonus, 25);
      // The second order on the same day carries no bonus.
      final entries = db.orderEntries('2026-10-26');
      expect(entries.map((e) => e.manualBonusEgp), [25, 0]);
    });

    test('deleting from one order removes only that order’s bonus',
        () async {
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 10),
          manual: 25);
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 11),
          manual: 10);
      final firstId = db.orderEntries('2026-10-26').first.id;
      await db.updateOrderEntry(
          dateKey: '2026-10-26', entryId: firstId, manualBonusEgp: 0);
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.totalManualBonus, 10);
      expect(db.orderEntries('2026-10-26').map((e) => e.manualBonusEgp),
          [0, 10]);
    });
  });

  group('salary agreement: Home / Report / PDF use one logic', () {
    test('all three surfaces agree on instant-effective bonuses',
        () async {
      // Mixed same-day scenario: flat 5 set 09:00, distance on
      // 09:00, flat deleted 11:00, distance off 11:00.
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 8),
          kmOut: 8, kmBack: 7); // before everything: nothing
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 10),
          kmOut: 8, kmBack: 7, manual: 25); // inside both: 5 + 10
      await completeOrder('2026-10-26', createdAt: at(2026, 10, 26, 12),
          kmOut: 8, kmBack: 7); // after both deletions: nothing
      await applySettings(
          (s) => s.applyFlatBonus(5, at(2026, 10, 26, 9)));
      await applySettings(
          (s) => s.applyDistanceToggle(true, at(2026, 10, 26, 9)));
      await applySettings(
          (s) => s.applyFlatBonus(0, at(2026, 10, 26, 11)));
      await applySettings(
          (s) => s.applyDistanceToggle(false, at(2026, 10, 26, 11)));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      // Report card salary (also what the Home card shows — same
      // WeeklyReport.salaryTotal): 3×10 orders + 1×100 paid day
      // + 10 distance (10:00 order only) + 25 manual + 5 flat
      // (10:00 order only).
      expect(r.totalDistanceBonus, 10);
      expect(r.totalManualBonus, 25);
      expect(r.totalFlatBonus, 5);
      expect(r.salaryTotal(orderPrice: 10, dailyFixedPay: 100), 170);
      // PDF builder reuses the same report: identical week total,
      // and day rows sum to the same salary.
      final pdf = PastWeeksReportBuilder(db).build(
          locale: 'en', orderPrice: 10, dailyFixedPay: 100);
      expect(pdf.weeks.single.totalEarnings, 170);
      final daySum = pdf.weeks.single.days
          .fold(0.0, (sum, d) => sum + d.earnings);
      expect(daySum, 170);
    });
  });

  group('migration of pre-existing single values', () {
    test('active values become periods from the migration instant only',
        () {
      // Simulate a pre-v27.16 stored settings object: flat 5 set at
      // some unknown earlier time, distance ON, and a per-week ON
      // override for the Oct 18 week — none with a stored start.
      final s = UserSettings()
        ..flatOrderBonusEgp = 5
        ..distanceBonusEnabled = true
        ..distanceBonusWeekOverrides = {'2026-10-18': true};
      expect(s.bonusPeriodsMigrated, isFalse);
      s.migrateLegacyBonusPeriods(at(2026, 10, 26, 9));
      expect(s.bonusPeriodsMigrated, isTrue);
      // No retroactive instant is invented: before Oct 26 09:00
      // flat pays 0.
      expect(s.flatBonusAt(at(2026, 10, 19, 12)), 0);
      expect(s.distancePeriodAt(at(2026, 10, 19, 12)), isNotNull);
      // The Oct 18 week's ON override is preserved by its own
      // week-scoped period (it was user-set, so it is NOT reset).
      expect(s.distanceBonusEnabledForOrder(
          at(2026, 10, 19, 12), '2026-10-19'), isTrue);
      // From the migration instant onward the active values pay.
      expect(s.flatBonusAt(at(2026, 10, 26, 9)), 5);
      expect(s.distancePeriodAt(at(2026, 10, 26, 9)), isNotNull);
      // Idempotent: a second run adds no duplicate periods.
      s.migrateLegacyBonusPeriods(at(2026, 10, 27, 9));
      expect(s.flatBonusPeriods.length, 1);
      // Periods survive the JSON round-trip (backup/restore path).
      final clone = UserSettings.fromJson(s.toJson());
      expect(clone.flatBonusAt(at(2026, 10, 26, 9)), 5);
      expect(clone.flatBonusAt(at(2026, 10, 19, 12)), 0);
      expect(clone.bonusPeriodsMigrated, isTrue);
    });

    test('off/zero pre-existing values create no period', () {
      final s = UserSettings(); // flat 0, distance off
      s.migrateLegacyBonusPeriods(at(2026, 10, 26, 9));
      expect(s.flatBonusPeriods, isEmpty);
      expect(s.distanceBonusPeriods, isEmpty);
      expect(s.flatBonusAt(at(2026, 10, 26, 9)), 0);
    });
  });

  group('v27.16 date periods convert honestly to instants', () {
    test('legacy date JSON keeps exactly its recorded whole days',
        () {
      // A v27.16 user stored these raw strings (flat 5 covering
      // Oct 26..28, distance open from Oct 26). The decoders must
      // NOT invent intraday precision: flat covers start-of-day
      // Oct 26 through start-of-day Oct 29 (exclusive), i.e. the
      // period v27.16 recorded as ending the day before a
      // deletion on Oct 29 becomes end = start-of-day Oct 29.
      final s = UserSettings()
        ..flatBonusPeriodsJson =
            '[{"s":"2026-10-26","e":"2026-10-28","a":5}]'
        ..distanceBonusPeriodsJson =
            '[{"s":"2026-10-26","e":null,"t":[{"km":12,"egp":5},'
                '{"km":15,"egp":10},{"km":20,"egp":17}]}]';
      expect(s.flatBonusAt(at(2026, 10, 25, 23, 59)), 0);
      expect(s.flatBonusAt(at(2026, 10, 26, 0, 0)), 5);
      expect(s.flatBonusAt(at(2026, 10, 28, 23, 59)), 5);
      expect(s.flatBonusAt(at(2026, 10, 29, 0, 0)), 0);
      expect(s.flatBonusAt(at(2026, 10, 29, 12)), 0);
      expect(s.distancePeriodAt(at(2026, 10, 26, 0, 0)), isNotNull);
      expect(s.distancePeriodAt(at(2026, 10, 25, 12)), isNull);
      // After a v27.17 change, the stored JSON is the new instant
      // format (ints, not date strings) and the converted old
      // period still pays exactly its recorded days.
      s.applyFlatBonus(7, at(2026, 10, 30, 12));
      expect(s.flatBonusPeriodsJson.contains('"2026-10-26"'), isFalse);
      expect(s.flatBonusAt(at(2026, 10, 28, 12)), 5);
      expect(s.flatBonusAt(at(2026, 10, 29, 12)), 0);
      expect(s.flatBonusAt(at(2026, 10, 30, 12)), 7);
    });

    test('legacy open period starting on a date starts at its '
        'start-of-day, not earlier', () {
      final s = UserSettings()
        ..flatBonusPeriodsJson = '[{"s":"2026-10-26","e":null,"a":5}]';
      expect(s.flatBonusAt(at(2026, 10, 25, 12)), 0);
      expect(s.flatBonusAt(at(2026, 10, 26, 0, 1)), 5);
    });
  });

  group('instant arithmetic across the DST fall-back day', () {
    test('start-of-day ordering and span survive Oct 29-30', () {
      // Egypt's DST fall-back (Thu 2026-10-29 24:00 EEST, clocks
      // back an hour): Oct 29 itself is the 25-hour day under
      // Africa/Cairo and 24 hours elsewhere. The test asserts
      // only TZ-independent truths: strict ordering, and spans
      // of at least 24h — so it passes under both TZs.
      final d29 = startOfDayMillis('2026-10-29');
      final d30 = startOfDayMillis('2026-10-30');
      final d31 = startOfDayMillis('2026-10-31');
      expect(d29, lessThan(d30));
      expect(d30, lessThan(d31));
      expect(d31 - d30, greaterThanOrEqualTo(24 * 3600 * 1000));
      expect(d30 - d29, greaterThanOrEqualTo(24 * 3600 * 1000));
    });

    test('legacy date period on the fall-back day keeps whole days',
        () async {
      final s = UserSettings()
        ..flatBonusPeriodsJson = '[{"s":"2026-10-30","e":"2026-10-30","a":5}]';
      expect(s.flatBonusAt(at(2026, 10, 30, 0, 30)), 5);
      expect(s.flatBonusAt(at(2026, 10, 30, 23, 30)), 5);
      expect(s.flatBonusAt(at(2026, 10, 31, 0, 0)), 0);
      expect(s.flatBonusAt(at(2026, 10, 29, 23, 30)), 0);
    });

    test('instant boundary in the fall-back week splits by millis',
        () async {
      await completeOrder('2026-10-30', createdAt: at(2026, 10, 30, 0, 30));
      await completeOrder('2026-10-30', createdAt: at(2026, 10, 30, 1, 30));
      await applySettings(
          (s) => s.applyFlatBonus(5, at(2026, 10, 30, 0)));
      await applySettings(
          (s) => s.applyFlatBonus(0, at(2026, 10, 30, 1)));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      // Plain millis comparison orders instants across the
      // transition week, so only the 00:30 order pays.
      expect(r.days[5].flatBonus, 5);
      expect(r.totalFlatBonus, 5);
    });
  });
}
