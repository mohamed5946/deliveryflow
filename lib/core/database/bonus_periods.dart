import 'dart:convert';

import '../date_time/week_calendar.dart';

/// v27.17: instant-based bonus periods (supersedes v27.16 date-based
/// periods).
///
/// MOHAMED'S RULE (2026-10-26): «البونص ده لو عملت أوردر دلوقتي
/// يتحسب وجيت شيلته بعد الأوردر ميتحسبش للي بعده، حتي لو في نفس
/// اليوم» — if he makes an order NOW while the bonus is on, that
/// order keeps the bonus even if he deletes the bonus later the
/// SAME day, and the next order after the deletion gets 0. The rule
/// is per-ORDER MOMENT, not per calendar day.
///
/// WHY v27.16 WAS WRONG FOR THIS CASE: v27.16 resolved a bonus by
/// the order's calendar date, and a deletion closed the period the
/// day BEFORE the deletion date — so the whole deletion day got 0.
/// An order made in the morning before an afternoon deletion would
/// incorrectly lose its bonus. v27.16 did NOT implement this rule.
///
/// Rules, one place, no exceptions:
/// - A period covers [startMillis]..[endMillis) — start inclusive,
///   end EXCLUSIVE, both epoch milliseconds (UTC instants, so
///   comparisons are plain integer comparisons and DST can never
///   skew them: the fall-back day's repeated hour is two distinct
///   instants, ordered normally). [endMillis] null means
///   open-ended (still active).
/// - Setting a value at instant T opens a period starting T: orders
///   with creation instant >= T get it, orders < T get 0 — even on
///   the same calendar day. Deleting/closing at instant D closes
///   the open period with end = D: orders < D keep it, orders
///   >= D get 0 — even minutes later, same day. Changing the
///   amount at instant C closes the old period at C and opens a
///   new one from C: orders < C keep the old amount, orders >= C
///   get the new amount. The boundary instant itself always takes
///   the NEW value (a change and an order in the same millisecond
///   is resolved in favour of the change — the user acted first).
/// - An order's moment is its ORIGINAL CREATION instant
///   (OrderEntry.createdAtMillis, Hive field 25), NEVER its
///   timestampMillis: timestampMillis is overwritten when the
///   delivery completes and is editable from the edit sheet, so it
///   is a finalization/edit time, not the moment the order was
///   made. Entries stored before v27.17 have no createdAtMillis
///   (0); they fall back to timestampMillis (see
///   OrderEntry.bonusInstantMillis) — documented, bounded skew:
///   at most the delivery's own duration for tracked orders.
/// - If an open period already started at exactly the change
///   instant, it is mutated in place instead of closing+reopening,
///   so no zero-length or inverted period is ever stored. When
///   several periods cover one instant (migration can create a
///   week-scoped period overlapping the global one), the period
///   with the LATEST start wins — the most recent change governs.
/// - When a change closes periods, ALL open periods are closed
///   (v27.16 closed only the first found). Otherwise a leftover
///   open period could keep paying after a deletion — exactly the
///   bug this version fixes.
///
/// MIGRATION (v27.16 -> v27.17, honest conversion, no invented
/// precision): v27.16 stored dateKeys. A legacy period is decoded
/// as [start-of-day(startKey), start-of-day(day-after(endKey)))
/// in device-local time (Africa/Cairo on his phone) — i.e. a
/// period that v27.16 recorded as ending the day before deletion
/// date Y becomes an instant period ending at start-of-day Y, and
/// an open period starting on date X becomes start-of-day X.
/// Old periods therefore keep EXACTLY the behaviour v27.16 already
/// recorded for them (whole days in, whole days out); only periods
/// created from v27.17 onward are instant-precise. Start-of-day is
/// unambiguous even on the DST fall-back day (00:00 occurs once),
/// and day stepping uses WeekCalendar constructor arithmetic,
/// never Duration(days:) addition (v27.11 lesson).
///
/// DEFAULTS (unchanged from v27.16): a fresh user has NO periods
/// at all — flat 0, distance off, manual 0. Nothing is calculated
/// unless the user himself explicitly sets/enables a bonus. The
/// tier VALUES (12→5 / 15→10 / 20→17) are only editable presets
/// that mean nothing until a distance period exists.
///
/// Single responsibility: these classes know NOTHING about Hive,
/// settings, or the UI — they are pure instant/value history plus
/// its resolvers, so they are unit-testable without a database.

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
/// moment. Tier order in [tiers] does not matter.
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

/// Device-local start-of-day instant (epoch millis) for a dateKey.
/// The dateKey's calendar fields go through the DateTime
/// constructor, so this is DST-safe: 00:00 exists exactly once
/// even on the fall-back day, and no Duration arithmetic is used.
int startOfDayMillis(String dateKey) {
  final d = WeekCalendar.parseDateKey(dateKey);
  return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}

/// Next calendar day of a dateKey, via WeekCalendar constructor
/// arithmetic (DST-safe — never Duration(days:) addition).
String nextDayKey(String dateKey) => WeekCalendar.dateKey(
    WeekCalendar.addDays(WeekCalendar.parseDateKey(dateKey), 1));

/// One flat per-order bonus period: [amount] EGP on every counted
/// order whose creation instant falls inside
/// [startMillis]..[endMillis) (end null = still open).
class FlatBonusPeriod {
  final int startMillis;
  final int? endMillis;
  final double amount;

  const FlatBonusPeriod({
    required this.startMillis,
    required this.endMillis,
    required this.amount,
  });

  bool covers(int instantMillis) =>
      instantMillis >= startMillis &&
      (endMillis == null || instantMillis < endMillis!);

  bool get isOpen => endMillis == null;

  FlatBonusPeriod closedAt(int end) =>
      FlatBonusPeriod(startMillis: startMillis, endMillis: end, amount: amount);

  Map<String, dynamic> toJson() =>
      {'s': startMillis, 'e': endMillis, 'a': amount};

  /// Decodes BOTH formats: v27.17 instant periods (`s`/`e` are
  /// ints) and legacy v27.16 date periods (`s`/`e` are dateKey
  /// strings, converted honestly — see the file header: start of
  /// the start day through start of the day after the end day).
  static FlatBonusPeriod fromJson(Map<String, dynamic> json) {
    final s = json['s'];
    final e = json['e'];
    if (s is String) {
      return FlatBonusPeriod(
        startMillis: startOfDayMillis(s),
        endMillis: e is String ? startOfDayMillis(nextDayKey(e)) : null,
        amount: (json['a'] as num).toDouble(),
      );
    }
    return FlatBonusPeriod(
      startMillis: (s as num).toInt(),
      endMillis: (e as num?)?.toInt(),
      amount: (json['a'] as num).toDouble(),
    );
  }
}

/// One distance-bonus period: while it covers an order's creation
/// instant, that order's distance bonus resolves against [tiers]
/// (empty tiers still mean 0 — a period with no tiers pays
/// nothing).
class DistanceBonusPeriod {
  final int startMillis;
  final int? endMillis;
  final List<DistanceBonusTier> tiers;

  const DistanceBonusPeriod({
    required this.startMillis,
    required this.endMillis,
    required this.tiers,
  });

  bool covers(int instantMillis) =>
      instantMillis >= startMillis &&
      (endMillis == null || instantMillis < endMillis!);

  bool get isOpen => endMillis == null;

  DistanceBonusPeriod closedAt(int end) => DistanceBonusPeriod(
        startMillis: startMillis,
        endMillis: end,
        tiers: tiers,
      );

  Map<String, dynamic> toJson() => {
        's': startMillis,
        'e': endMillis,
        't': [for (final t in tiers) t.toJson()],
      };

  /// Decodes both the v27.17 instant format and the legacy v27.16
  /// date format (same honest conversion as FlatBonusPeriod).
  static DistanceBonusPeriod fromJson(Map<String, dynamic> json) {
    final s = json['s'];
    final e = json['e'];
    final tiers = [
      for (final t in (json['t'] as List? ?? []))
        DistanceBonusTier.fromJson(Map<String, dynamic>.from(t as Map)),
    ];
    if (s is String) {
      return DistanceBonusPeriod(
        startMillis: startOfDayMillis(s),
        endMillis: e is String ? startOfDayMillis(nextDayKey(e)) : null,
        tiers: tiers,
      );
    }
    return DistanceBonusPeriod(
      startMillis: (s as num).toInt(),
      endMillis: (e as num?)?.toInt(),
      tiers: tiers,
    );
  }
}

/// The flat amount active at [instantMillis]: the latest-starting
/// covering period's amount, or 0 when no period covers the instant
/// (before the first set, or after a deletion closed the last
/// period).
double resolveFlatBonusAt(List<FlatBonusPeriod> periods, int instantMillis) {
  FlatBonusPeriod? best;
  for (final p in periods) {
    if (!p.covers(instantMillis)) continue;
    if (best == null || p.startMillis >= best.startMillis) {
      best = p;
    }
  }
  return best?.amount ?? 0;
}

/// The distance period active at [instantMillis] (latest-starting
/// covering period), or null when no distance bonus was active at
/// that moment.
DistanceBonusPeriod? resolveDistancePeriodAt(
    List<DistanceBonusPeriod> periods, int instantMillis) {
  DistanceBonusPeriod? best;
  for (final p in periods) {
    if (!p.covers(instantMillis)) continue;
    if (best == null || p.startMillis >= best.startMillis) {
      best = p;
    }
  }
  return best;
}

/// True when any distance period overlaps any instant of the week
/// starting [weekStartKey] (Sunday, device-local start-of-day, to
/// the next Sunday's start-of-day — constructor arithmetic, so the
/// DST fall-back week's 25-hour Sunday..Saturday span is exact).
/// Used to decide whether the report screen's per-week switch is
/// even meaningful for that week.
bool hasDistancePeriodInWeekFor(
    List<DistanceBonusPeriod> periods, String weekStartKey) {
  final weekStart = startOfDayMillis(weekStartKey);
  final weekEnd = startOfDayMillis(nextDayKey(
      WeekCalendar.dateKey(WeekCalendar.addDays(
          WeekCalendar.parseDateKey(weekStartKey), 6))));
  for (final p in periods) {
    if (p.startMillis < weekEnd &&
        (p.endMillis == null || p.endMillis! > weekStart)) {
      return true;
    }
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
