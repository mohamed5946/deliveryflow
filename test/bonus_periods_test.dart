import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:deliveryflow/features/weekly_reports/past_weeks_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';

/// v27.16: effective-date bonus periods.
///
/// The reported bug: setting a bonus paid it on THIS week AND all
/// past weeks (and deleting it erased it everywhere). The rule now:
/// a bonus is calculated ONLY on orders whose own calendar date falls
/// inside a period the user himself opened — setting opens a period
/// from that date, changing closes the old one the day before and
/// opens a new one, deleting closes the open period the day before
/// (so the deletion date itself already gets 0). Orders before the
/// first set get 0, orders inside a period keep their amount forever,
/// orders after a deletion get 0. A fresh user has NO periods at all
/// (flat 0, distance off, manual 0) until he explicitly sets one.
///
/// Weeks used below (Sundays): 2026-10-18 and 2026-10-25.
void main() {
  late Directory tmp;
  late DatabaseService db;

  Future<void> completeOrder(String dateKey,
      {double kmOut = 3, double kmBack = 2, double? manual}) async {
    final e = await db.addOrderEntry(
      dateKey: dateKey,
      timestampMillis: DateTime.now().millisecondsSinceEpoch,
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
      expect(s.flatBonusForDate('2026-10-25'), 0);
      expect(s.distancePeriodForDate('2026-10-25'), isNull);
      expect(s.distanceBonusEnabledForDate('2026-10-25'), isFalse);
      // The freshly initialized database carries the same defaults.
      expect(db.settings.flatOrderBonusEgp, 0);
      expect(db.settings.distanceBonusEnabled, isFalse);
      expect(db.settings.flatBonusPeriods, isEmpty);
      expect(db.settings.distanceBonusPeriods, isEmpty);
      expect(db.settings.bonusPeriodsMigrated, isTrue);
    });

    test('report + PDF pay no bonus at all before any explicit set',
        () async {
      await completeOrder('2026-10-25', kmOut: 8, kmBack: 7);
      await completeOrder('2026-10-26', kmOut: 3, kmBack: 2);
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

  group('flat bonus periods', () {
    test('set on day D: 0 before D, amount from D onward', () async {
      await completeOrder('2026-10-25'); // Sunday, before D
      await completeOrder('2026-10-26'); // Monday = D
      await completeOrder('2026-10-27'); // Tuesday, after D
      await applySettings(
          (s) => s.applyFlatBonus(5, '2026-10-26'));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.days[0].flatBonus, 0); // Sun Oct 25
      expect(r.days[1].flatBonus, 5); // Mon Oct 26
      expect(r.days[2].flatBonus, 5); // Tue Oct 27
      expect(r.totalFlatBonus, 10);
      // Past week (Oct 18 week) has no orders here, but the resolver
      // itself must also pay 0 before D:
      expect(db.settings.flatBonusForDate('2026-10-19'), 0);
      expect(db.settings.flatBonusForDate('2026-10-26'), 5);
    });

    test('change on day E: old amount before E, new amount from E',
        () async {
      await completeOrder('2026-10-25');
      await completeOrder('2026-10-26');
      await completeOrder('2026-10-27');
      await completeOrder('2026-10-28');
      await applySettings(
          (s) => s.applyFlatBonus(5, '2026-10-26'));
      await applySettings(
          (s) => s.applyFlatBonus(8, '2026-10-28'));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.days[0].flatBonus, 0); // before first set
      expect(r.days[1].flatBonus, 5); // Oct 26, old amount
      expect(r.days[2].flatBonus, 5); // Oct 27, old amount
      expect(r.days[3].flatBonus, 8); // Oct 28, new amount
      expect(r.totalFlatBonus, 18);
    });

    test('delete on day F: amount through F-1, 0 from F onward',
        () async {
      await completeOrder('2026-10-26');
      await completeOrder('2026-10-29');
      await completeOrder('2026-10-30');
      await completeOrder('2026-10-31');
      await applySettings(
          (s) => s.applyFlatBonus(5, '2026-10-26'));
      await applySettings((s) => s.applyFlatBonus(0, '2026-10-30'));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.days[1].flatBonus, 5); // Oct 26: inside old period
      expect(r.days[4].flatBonus, 5); // Oct 29: last day (F-1)
      expect(r.days[5].flatBonus, 0); // Oct 30 = F: deleted
      expect(r.days[6].flatBonus, 0); // Oct 31: after deletion
      expect(r.totalFlatBonus, 10);
      // The legacy current-value field reads 0 (deleted) while the
      // old period still pays its days — display vs. salary differ
      // by design, and salary uses the periods.
      expect(db.settings.flatOrderBonusEgp, 0);
    });

    test('set then change on the SAME day mutates in place', () async {
      await completeOrder('2026-10-26');
      await applySettings(
          (s) => s.applyFlatBonus(5, '2026-10-26'));
      await applySettings(
          (s) => s.applyFlatBonus(8, '2026-10-26'));
      expect(db.settings.flatBonusPeriods.length, 1);
      expect(db.settings.flatBonusForDate('2026-10-26'), 8);
      expect(db.settings.flatBonusForDate('2026-10-25'), 0);
    });

    test('the reported example: week before the set pays 0', () async {
      await completeOrder('2026-10-19'); // week Oct 18–24
      await completeOrder('2026-10-26'); // week Oct 25–31
      await applySettings(
          (s) => s.applyFlatBonus(5, '2026-10-26'));
      final oldWeek = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-19'));
      final newWeek = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-26'));
      expect(oldWeek.totalFlatBonus, 0);
      expect(newWeek.totalFlatBonus, 5);
    });
  });

  group('distance bonus periods', () {
    test('enable on day D: 0 before D, tiers from D onward', () async {
      await completeOrder('2026-10-25', kmOut: 8, kmBack: 7); // 15km
      await completeOrder('2026-10-26', kmOut: 8, kmBack: 7);
      await completeOrder('2026-10-27', kmOut: 3, kmBack: 2); // 5km
      await applySettings(
          (s) => s.applyDistanceToggle(true, '2026-10-26'));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.days[0].distanceBonus, 0); // before enable
      expect(r.days[1].distanceBonus, 10); // 15km -> tier 2
      expect(r.days[2].distanceBonus, 0); // below first tier
      expect(r.totalDistanceBonus, 10);
    });

    test('disable on day F: tiers through F-1, 0 from F onward',
        () async {
      await completeOrder('2026-10-26', kmOut: 8, kmBack: 7);
      await completeOrder('2026-10-29', kmOut: 8, kmBack: 7);
      await completeOrder('2026-10-30', kmOut: 8, kmBack: 7);
      await applySettings(
          (s) => s.applyDistanceToggle(true, '2026-10-26'));
      await applySettings(
          (s) => s.applyDistanceToggle(false, '2026-10-30'));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.days[1].distanceBonus, 10);
      expect(r.days[4].distanceBonus, 10); // Oct 29 = F-1 keeps it
      expect(r.days[5].distanceBonus, 0); // Oct 30 = F
      expect(r.totalDistanceBonus, 20);
    });

    test('tier edit on day E: old tiers before E, new tiers from E',
        () async {
      await completeOrder('2026-10-26', kmOut: 8, kmBack: 7); // 15km
      await completeOrder('2026-10-28', kmOut: 8, kmBack: 7);
      await applySettings(
          (s) => s.applyDistanceToggle(true, '2026-10-26'));
      // New tiers: 12km -> 7 (was 5), 15km -> 12 (was 10), 20km -> 20.
      await applySettings((s) => s.applyDistanceTiers([
            const DistanceBonusTier(fromKm: 12, bonusEgp: 7),
            const DistanceBonusTier(fromKm: 15, bonusEgp: 12),
            const DistanceBonusTier(fromKm: 20, bonusEgp: 20),
          ], '2026-10-28'));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.days[1].distanceBonus, 10); // old tiers
      expect(r.days[3].distanceBonus, 12); // new tiers
    });

    test('tier edit while OFF creates no period and pays nothing',
        () async {
      await completeOrder('2026-10-26', kmOut: 8, kmBack: 7);
      await applySettings((s) => s.applyDistanceTiers([
            const DistanceBonusTier(fromKm: 12, bonusEgp: 7),
            const DistanceBonusTier(fromKm: 15, bonusEgp: 12),
            const DistanceBonusTier(fromKm: 20, bonusEgp: 20),
          ], '2026-10-26'));
      expect(db.settings.distanceBonusPeriods, isEmpty);
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.totalDistanceBonus, 0);
    });

    test('period starting mid-week pays only from its start day',
        () async {
      await completeOrder('2026-10-25', kmOut: 8, kmBack: 7);
      await completeOrder('2026-10-26', kmOut: 8, kmBack: 7);
      await completeOrder('2026-10-28', kmOut: 8, kmBack: 7);
      await applySettings(
          (s) => s.applyDistanceToggle(true, '2026-10-28'));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      expect(r.days[0].distanceBonus, 0);
      expect(r.days[1].distanceBonus, 0);
      expect(r.days[3].distanceBonus, 10);
    });
  });

  group('per-week overrides vs periods (reconciliation)', () {
    test('override ON outside a period pays nothing; inside it works',
        () async {
      await completeOrder('2026-10-19', kmOut: 8, kmBack: 7);
      await completeOrder('2026-10-26', kmOut: 8, kmBack: 7);
      // Period covers last week only; current week gets an ON
      // override anyway — it must NOT resurrect the bonus there.
      await applySettings((s) {
        s.distanceBonusPeriods = [
          DistanceBonusPeriod(
              startKey: '2026-10-18',
              endKey: '2026-10-24',
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

    test('override OFF inside a period zeroes only that week', () async {
      await completeOrder('2026-10-19', kmOut: 8, kmBack: 7);
      await completeOrder('2026-10-26', kmOut: 8, kmBack: 7);
      await applySettings(
          (s) => s.applyDistanceToggle(true, '2026-10-18'));
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
      await completeOrder('2026-10-26', kmOut: 8, kmBack: 7);
      await completeOrder('2026-11-02', kmOut: 8, kmBack: 7);
      await applySettings(
          (s) => s.applyDistanceToggle(true, '2026-10-25'));
      await applySettings(
          (s) => s.applyDistanceToggle(false, '2026-11-01'));
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
      await completeOrder('2026-10-26', manual: 25);
      await completeOrder('2026-10-26');
      await completeOrder('2026-10-27');
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
      await completeOrder('2026-10-26', manual: 25);
      await completeOrder('2026-10-26', manual: 10);
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
    test('all three surfaces agree on order-date-effective bonuses',
        () async {
      // Flat 5 from Oct 26, distance from Oct 26, manual on one order.
      await completeOrder('2026-10-25', kmOut: 8, kmBack: 7); // pre-set
      await completeOrder('2026-10-26', kmOut: 8, kmBack: 7,
          manual: 25);
      await completeOrder('2026-10-27', kmOut: 3, kmBack: 2);
      await applySettings(
          (s) => s.applyFlatBonus(5, '2026-10-26'));
      await applySettings(
          (s) => s.applyDistanceToggle(true, '2026-10-26'));
      final r = db.buildWeeklyReport(
          WeekCalendar.parseDateKey('2026-10-25'));
      // Report card salary (also what the Home card shows — same
      // WeeklyReport.salaryTotal): 3×10 orders + 3×100 paid days
      // + 10 distance (Oct 26 only; Oct 25 pre-set, Oct 27 below
      // tier) + 25 manual + 10 flat (Oct 26+27 × 5).
      expect(r.totalDistanceBonus, 10);
      expect(r.totalManualBonus, 25);
      expect(r.totalFlatBonus, 10);
      expect(r.salaryTotal(orderPrice: 10, dailyFixedPay: 100), 375);
      // PDF builder reuses the same report: identical week total,
      // and day rows sum to the same salary.
      final pdf = PastWeeksReportBuilder(db).build(
          locale: 'en', orderPrice: 10, dailyFixedPay: 100);
      expect(pdf.weeks.single.totalEarnings, 375);
      final daySum = pdf.weeks.single.days
          .fold(0.0, (sum, d) => sum + d.earnings);
      expect(daySum, 375);
    });
  });

  group('migration of pre-existing single values', () {
    test('active values become periods from the migration date only',
        () {
      // Simulate a pre-v27.16 stored settings object: flat 5 set at
      // some unknown earlier date, distance ON, and a per-week ON
      // override for the Oct 18 week — none with a stored start.
      final s = UserSettings()
        ..flatOrderBonusEgp = 5
        ..distanceBonusEnabled = true
        ..distanceBonusWeekOverrides = {'2026-10-18': true};
      expect(s.bonusPeriodsMigrated, isFalse);
      s.migrateLegacyBonusPeriods('2026-10-26');
      expect(s.bonusPeriodsMigrated, isTrue);
      // No retroactive date is invented: before Oct 26 both pay 0.
      expect(s.flatBonusForDate('2026-10-19'), 0);
      expect(s.distancePeriodForDate('2026-10-19'), isNotNull);
      // The Oct 18 week's ON override is preserved by its own
      // week-scoped period (it was user-set, so it is NOT reset).
      expect(s.distanceBonusEnabledForDate('2026-10-19'), isTrue);
      // From the migration date onward the active values keep paying.
      expect(s.flatBonusForDate('2026-10-26'), 5);
      expect(s.distancePeriodForDate('2026-10-26'), isNotNull);
      // Idempotent: a second run adds no duplicate periods.
      s.migrateLegacyBonusPeriods('2026-10-27');
      expect(s.flatBonusPeriods.length, 1);
      // Periods survive the JSON round-trip (backup/restore path).
      final clone = UserSettings.fromJson(s.toJson());
      expect(clone.flatBonusForDate('2026-10-26'), 5);
      expect(clone.flatBonusForDate('2026-10-19'), 0);
      expect(clone.bonusPeriodsMigrated, isTrue);
    });

    test('off/zero pre-existing values create no period', () {
      final s = UserSettings(); // flat 0, distance off
      s.migrateLegacyBonusPeriods('2026-10-26');
      expect(s.flatBonusPeriods, isEmpty);
      expect(s.distanceBonusPeriods, isEmpty);
      expect(s.flatBonusForDate('2026-10-26'), 0);
    });
  });

  group('period date arithmetic', () {
    test('previousDayKey is DST- and boundary-safe', () {
      // Egypt's DST fall-back week (Oct 29, 2026) and year/month
      // boundaries — constructor arithmetic, never 24h durations.
      expect(previousDayKey('2026-10-30'), '2026-10-29');
      expect(previousDayKey('2026-03-01'), '2026-02-28');
      expect(previousDayKey('2027-01-01'), '2026-12-31');
      expect(previousDayKey('2026-10-26'), '2026-10-25');
    });
  });
}
