import 'dart:convert';

import '../date_time/week_calendar.dart';

/// v27.16: effective-date bonus periods.
///
/// THE BUG THIS FIXES: flat and distance bonuses used to resolve
/// against the CURRENT settings value, so setting 5 EGP today paid
/// 5 EGP on every past week too, and deleting it erased it from
/// weeks where it had genuinely been paid. Every bonus now has an
/// effective start date and an effective end date (deletion date):
/// an order takes the bonus value active on the order's own calendar
/// date (Africa/Cairo date — the device-local calendar date, since
/// every order record is already keyed by local dateKey).
///
/// Rules, one place, no exceptions:
/// - A period covers [startKey]..[endKey] inclusive; [endKey] null
///   means open-ended (still active).
/// - Setting a value on date D opens a period starting D. Changing
///   it on date E closes the open period the day before E (end =
///   previous calendar day — constructor arithmetic, never
///   Duration(days:) addition, per the WeekCalendar DST rule) and
///   opens a new period from E. Deleting on date F closes the open
///   period the day before F; from F onward the value is 0.
/// - If the open period already started on the change date itself,
///   it is mutated in place instead of closing+reopening, so no
///   zero-length or inverted period is ever stored.
/// - When several periods cover one date (migration can create a
///   week-scoped period overlapping the global one), the period with
///   the LATEST start wins — the most recent change governs.
/// - Dates are `yyyy-MM-dd` dateKeys, so plain string comparison is
///   chronological order. No DateTime parsing is needed to resolve.
///
/// DEFAULTS (v27.16 clarification): a fresh user has NO periods at
/// all — flat 0, distance off, manual 0. Nothing is calculated
/// unless the user himself explicitly sets/enables a bonus. The
/// period lists below are therefore empty by default; the tier
/// VALUES (12→5 / 15→10 / 20→17) are only editable presets that mean
/// nothing until a distance period exists.
///
/// Single responsibility: these classes know NOTHING about Hive,
/// settings, or the UI — they are pure date/value history plus its
/// resolvers, so they are unit-testable without a database.

/// One distance-bonus tier (v27.5, moved here in v27.16 so the
/// period model owns the tier type): a completed order whose
/// round-trip distance reaches [fromKm] earns [bonusEgp].
class DistanceBonusTier {
  final double fromKm;
  final double bonusEgp;

  const DistanceBonusTier({required this.fromKm, required this.bonusEgp});

  Map<String, dynamic> toJson() => {'km': fromKm, 'egp': bonusEgp};

  static DistanceBonusTier fromJson(Map<String, dynamic> json) =>
      DistanceBonusTier(
        fromKm: (json['km'] as num).toDouble(),
        bonusEgp: (json['egp'] as num).toDouble(),
      );
}

/// Pure distance-bonus resolution (v27.5): the bonus of the HIGHEST
/// tier whose threshold the round-trip distance reaches. Returns 0
/// below the first threshold, when the distance is missing or zero
/// (count-only entries and orders without a finalized distance earn
/// no distance bonus), and when the feature is off for the order's
/// date. Tier order in [tiers] does not matter.
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

/// One flat per-order bonus period: [amount] EGP on every counted
/// order whose date falls inside [startKey]..[endKey].
class FlatBonusPeriod {
  final String startKey;
  final String? endKey;
  final double amount;

  const FlatBonusPeriod({
    required this.startKey,
    required this.endKey,
    required this.amount,
  });

  bool covers(String dateKey) =>
      dateKey.compareTo(startKey) >= 0 &&
      (endKey == null || dateKey.compareTo(endKey!) <= 0);

  bool get isOpen => endKey == null;

  FlatBonusPeriod closedOn(String lastDayKey) =>
      FlatBonusPeriod(startKey: startKey, endKey: lastDayKey, amount: amount);

  Map<String, dynamic> toJson() =>
      {'s': startKey, 'e': endKey, 'a': amount};

  static FlatBonusPeriod fromJson(Map<String, dynamic> json) =>
      FlatBonusPeriod(
        startKey: json['s'] as String,
        endKey: json['e'] as String?,
        amount: (json['a'] as num).toDouble(),
      );
}

/// One distance-bonus period: while it covers an order's date, that
/// order's distance bonus resolves against [tiers] (empty tiers
/// still mean 0 — a period with no tiers pays nothing).
class DistanceBonusPeriod {
  final String startKey;
  final String? endKey;
  final List<DistanceBonusTier> tiers;

  const DistanceBonusPeriod({
    required this.startKey,
    required this.endKey,
    required this.tiers,
  });

  bool covers(String dateKey) =>
      dateKey.compareTo(startKey) >= 0 &&
      (endKey == null || dateKey.compareTo(endKey!) <= 0);

  bool get isOpen => endKey == null;

  DistanceBonusPeriod closedOn(String lastDayKey) => DistanceBonusPeriod(
        startKey: startKey,
        endKey: lastDayKey,
        tiers: tiers,
      );

  Map<String, dynamic> toJson() => {
        's': startKey,
        'e': endKey,
        't': [for (final t in tiers) t.toJson()],
      };

  static DistanceBonusPeriod fromJson(Map<String, dynamic> json) =>
      DistanceBonusPeriod(
        startKey: json['s'] as String,
        endKey: json['e'] as String?,
        tiers: [
          for (final t in (json['t'] as List? ?? []))
            DistanceBonusTier.fromJson(
                Map<String, dynamic>.from(t as Map)),
        ],
      );
}

/// Previous calendar day of a dateKey, via WeekCalendar constructor
/// arithmetic (DST-safe — never Duration(days:) addition).
String previousDayKey(String dateKey) =>
    WeekCalendar.dateKey(
        WeekCalendar.addDays(WeekCalendar.parseDateKey(dateKey), -1));

/// The flat amount active on [dateKey]: the latest-starting covering
/// period's amount, or 0 when no period covers the date (before the
/// first set, or after a deletion closed the last period).
double resolveFlatBonusForDate(List<FlatBonusPeriod> periods, String dateKey) {
  FlatBonusPeriod? best;
  for (final p in periods) {
    if (!p.covers(dateKey)) continue;
    if (best == null || p.startKey.compareTo(best.startKey) > 0) {
      best = p;
    }
  }
  return best?.amount ?? 0;
}

/// The distance period active on [dateKey] (latest-starting covering
/// period), or null when no distance bonus was active that day.
DistanceBonusPeriod? resolveDistancePeriodForDate(
    List<DistanceBonusPeriod> periods, String dateKey) {
  DistanceBonusPeriod? best;
  for (final p in periods) {
    if (!p.covers(dateKey)) continue;
    if (best == null || p.startKey.compareTo(best.startKey) > 0) {
      best = p;
    }
  }
  return best;
}

/// True when any distance period covers any day of the week starting
/// [weekStartKey] (Sunday). Used to decide whether the report
/// screen's per-week switch is even meaningful for that week.
bool hasDistancePeriodInWeekFor(
    List<DistanceBonusPeriod> periods, String weekStartKey) {
  final start = WeekCalendar.parseDateKey(weekStartKey);
  for (var i = 0; i < 7; i++) {
    final day = WeekCalendar.dateKey(
        WeekCalendar.addDays(start, i));
    if (resolveDistancePeriodForDate(periods, day) != null) return true;
  }
  return false;
}

/// JSON encoding for storage inside UserSettings (a single Hive
/// String field per list keeps the Hive adapter a plain field
/// addition — no new Hive typeIds, no adapter migration risk).
String encodeFlatPeriods(List<FlatBonusPeriod> periods) =>
    jsonEncode([for (final p in periods) p.toJson()]);

List<FlatBonusPeriod> decodeFlatPeriods(String raw) {
  if (raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return [
      for (final p in decoded)
        FlatBonusPeriod.fromJson(Map<String, dynamic>.from(p as Map)),
    ];
  } catch (_) {
    return [];
  }
}

String encodeDistancePeriods(List<DistanceBonusPeriod> periods) =>
    jsonEncode([for (final p in periods) p.toJson()]);

List<DistanceBonusPeriod> decodeDistancePeriods(String raw) {
  if (raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return [
      for (final p in decoded)
        DistanceBonusPeriod.fromJson(
            Map<String, dynamic>.from(p as Map)),
    ];
  } catch (_) {
    return [];
  }
}
