import 'dart:io';

import 'package:deliveryflow/core/database/database_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// v27.5: distance bonus per order (بونص المسافة) — pure tier
/// resolution, settings storage, and the weekly-report integration
/// with per-week overrides.
void main() {
  group('distanceBonusFor (pure tiers)', () {
    // The Gawab defaults: 12→5, 15→10, 20→17 EGP.
    final tiers = UserSettings().distanceBonusTiers;

    test('boundaries resolve to the highest reached tier', () {
      expect(distanceBonusFor(11.9, tiers), 0);
      expect(distanceBonusFor(12, tiers), 5);
      expect(distanceBonusFor(14.99, tiers), 5);
      expect(distanceBonusFor(15, tiers), 10);
      expect(distanceBonusFor(19.99, tiers), 10);
      expect(distanceBonusFor(20, tiers), 17);
      expect(distanceBonusFor(35, tiers), 17);
    });

    test('missing/zero distance and disabled earn nothing', () {
      expect(distanceBonusFor(null, tiers), 0);
      expect(distanceBonusFor(0, tiers), 0);
      expect(distanceBonusFor(25, tiers, enabled: false), 0);
      expect(distanceBonusFor(25, const []), 0);
    });

    test('tier order does not matter; custom tiers are honored', () {
      final custom = [
        const DistanceBonusTier(fromKm: 20, bonusEgp: 17),
        const DistanceBonusTier(fromKm: 12, bonusEgp: 5),
        const DistanceBonusTier(fromKm: 15, bonusEgp: 10),
      ];
      expect(distanceBonusFor(16, custom), 10);
      expect(distanceBonusFor(21, custom), 17);
    });
  });

  group('settings storage', () {
    late Directory tmp;
    late DatabaseService db;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('df_distbonus_');
      db = DatabaseService();
      await db.init(hivePath: tmp.path);
    });

    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('defaults are the Gawab tiers, feature on, no overrides', () {
      final s = db.settings;
      expect(s.distanceBonusEnabled, isTrue);
      expect(s.distanceBonusTiers.map((t) => t.fromKm), [12, 15, 20]);
      expect(s.distanceBonusTiers.map((t) => t.bonusEgp), [5, 10, 17]);
      expect(s.distanceBonusWeekOverrides, isEmpty);
      expect(s.distanceBonusEnabledForWeek('2026-10-18'), isTrue);
    });

    test('custom tiers + overrides survive a settings round-trip', () async {
      final s = db.settings
        ..distanceBonusEnabled = false
        ..distanceBonusTier1Km = 10
        ..distanceBonusTier1Egp = 4
        ..distanceBonusTier2Km = 18
        ..distanceBonusTier2Egp = 12
        ..distanceBonusTier3Km = 25
        ..distanceBonusTier3Egp = 20
        ..distanceBonusWeekOverrides = {'2026-10-18': true};
      await db.saveSettings(s);

      final back = db.settings;
      expect(back.distanceBonusEnabled, isFalse);
      expect(back.distanceBonusTiers.map((t) => t.fromKm), [10, 18, 25]);
      expect(back.distanceBonusTiers.map((t) => t.bonusEgp), [4, 12, 20]);
      // Override beats the global default for its week only.
      expect(back.distanceBonusEnabledForWeek('2026-10-18'), isTrue);
      expect(back.distanceBonusEnabledForWeek('2026-10-25'), isFalse);

      // The JSON clone path (settings notifier + backup) keeps them too.
      final clone = UserSettings.fromJson(back.toJson());
      expect(clone.distanceBonusTier2Egp, 12);
      expect(clone.distanceBonusWeekOverrides, {'2026-10-18': true});
    });
  });

  group('weekly report integration', () {
    late Directory tmp;
    late DatabaseService db;
    late String sunKey;
    late String currentWeekKey;
    late String lastSunKey;
    late String lastWeekKey;

    Future<void> completeOrder(
      String dateKey, {
      required double kmOut,
      required double kmBack,
    }) async {
      final e = await db.addOrderEntry(
        dateKey: dateKey,
        timestampMillis: DateTime.now().millisecondsSinceEpoch,
        kmOut: kmOut,
        kmBack: kmBack,
      );
      await db.updateOrderEntry(dateKey: dateKey, entryId: e.id, status: 3);
    }

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('df_distbonus_rep_');
      db = DatabaseService();
      await db.init(hivePath: tmp.path);

      final thisSunday = WeekCalendar.weekStart(DateTime.now());
      currentWeekKey = WeekCalendar.dateKey(thisSunday);
      sunKey = currentWeekKey;
      final lastSunday = WeekCalendar.addDays(thisSunday, -7);
      lastWeekKey = WeekCalendar.dateKey(lastSunday);
      lastSunKey = lastWeekKey;

      // Current week, Sunday: a 15 km order (+10) and a 21 km order
      // (+17); a pending 30 km entry (not counted, no bonus); one
      // count-only order (counted, no km, no bonus).
      await completeOrder(sunKey, kmOut: 8, kmBack: 7);
      await completeOrder(sunKey, kmOut: 11, kmBack: 10);
      await db.addOrderEntry(
        dateKey: sunKey,
        timestampMillis: DateTime.now().millisecondsSinceEpoch,
        kmOut: 15,
        kmBack: 15,
      );
      await db.addCountOnlyEntries(dateKey: sunKey, count: 1);

      // Last week, Sunday: one 15 km order (+10).
      await completeOrder(lastSunKey, kmOut: 8, kmBack: 7);
    });

    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('week totals fold per-order bonuses into the salary', () {
      final r = db.buildWeeklyReport(DateTime.now());
      expect(r.totalOrders, 3);
      expect(r.totalDistanceBonus, 27);
      expect(r.distanceBonusEnabled, isTrue);
      final sunday = r.days[0];
      expect(sunday.distanceBonus, 27);
      // 3 orders × 10 + 1 paid day × 100 + 27 distance bonus.
      expect(r.salaryTotal(orderPrice: 10, dailyFixedPay: 100), 157);
    });

    test('per-week override off zeroes only that week', () async {
      await db.saveSettings(UserSettings()
        ..distanceBonusWeekOverrides = {currentWeekKey: false});

      final off = db.buildWeeklyReport(DateTime.now());
      expect(off.distanceBonusEnabled, isFalse);
      expect(off.totalDistanceBonus, 0);
      expect(off.salaryTotal(orderPrice: 10, dailyFixedPay: 100), 130);

      // The identical neighbouring week still counts its bonus.
      final other =
          db.buildWeeklyReport(WeekCalendar.parseDateKey(lastWeekKey));
      expect(other.distanceBonusEnabled, isTrue);
      expect(other.totalDistanceBonus, 10);
    });

    test('override on beats a global off, for that week only', () async {
      await db.saveSettings(UserSettings()
        ..distanceBonusEnabled = false
        ..distanceBonusWeekOverrides = {lastWeekKey: true});

      final on =
          db.buildWeeklyReport(WeekCalendar.parseDateKey(lastWeekKey));
      expect(on.distanceBonusEnabled, isTrue);
      expect(on.totalDistanceBonus, 10);

      final off = db.buildWeeklyReport(DateTime.now());
      expect(off.distanceBonusEnabled, isFalse);
      expect(off.totalDistanceBonus, 0);
    });
  });
}
