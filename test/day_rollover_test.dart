import 'package:deliveryflow/core/date_time/day_rollover.dart';
import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// v26: pure date/time helpers behind the midnight rollover and the
/// shift-end reminder scheduling.
void main() {
  group('nextMidnight', () {
    test('from late evening lands on the coming midnight', () {
      expect(nextMidnight(DateTime(2026, 10, 22, 23, 50)),
          DateTime(2026, 10, 23));
    });

    test('from exactly midnight lands on the NEXT midnight', () {
      expect(nextMidnight(DateTime(2026, 10, 22)), DateTime(2026, 10, 23));
    });

    test('crosses a month boundary', () {
      expect(nextMidnight(DateTime(2026, 1, 31, 10, 15)),
          DateTime(2026, 2, 1));
    });
  });

  group('dayChanged', () {
    test('same calendar day is not a change', () {
      expect(
          dayChanged(DateTime(2026, 10, 22, 0, 5), DateTime(2026, 10, 22, 23, 55)),
          isFalse);
    });

    test('across midnight is a change', () {
      expect(
          dayChanged(DateTime(2026, 10, 22, 23, 50), DateTime(2026, 10, 23, 0, 5)),
          isTrue);
    });
  });

  group('shiftEndReminderTimes', () {
    final day = DateTime(2026, 10, 22); // Thursday

    test('normal day shift: one reminder at the shift end', () {
      final times = shiftEndReminderTimes(
          day: day, startMinutes: 9 * 60, endMinutes: 17 * 60);
      expect(times.length, 1);
      expect(times.single.when, DateTime(2026, 10, 22, 17));
      expect(times.single.preMidnight, isFalse);
    });

    test('normal evening shift: one reminder at the shift end', () {
      final times = shiftEndReminderTimes(
          day: day, startMinutes: 12 * 60, endMinutes: 20 * 60);
      expect(times.length, 1);
      expect(times.single.when, DateTime(2026, 10, 22, 20));
    });

    test('overnight shift 17:00 -> 04:00: 23:55 plus next-day end', () {
      final times = shiftEndReminderTimes(
          day: day, startMinutes: 17 * 60, endMinutes: 4 * 60);
      expect(times.length, 2);
      expect(times[0].when, DateTime(2026, 10, 22, 23, 55));
      expect(times[0].preMidnight, isTrue);
      expect(times[1].when, DateTime(2026, 10, 23, 4));
      expect(times[1].preMidnight, isFalse);
    });

    test('overnight shift 22:00 -> 06:00: 23:55 plus next-day end', () {
      final times = shiftEndReminderTimes(
          day: day, startMinutes: 22 * 60, endMinutes: 6 * 60);
      expect(times.length, 2);
      expect(times[0].when, DateTime(2026, 10, 22, 23, 55));
      expect(times[1].when, DateTime(2026, 10, 23, 6));
    });

    test('end == start is treated as overnight', () {
      final times = shiftEndReminderTimes(
          day: day, startMinutes: 8 * 60, endMinutes: 8 * 60);
      expect(times.length, 2);
      expect(times[0].when, DateTime(2026, 10, 22, 23, 55));
      expect(times[1].when, DateTime(2026, 10, 23, 8));
    });
  });
}
