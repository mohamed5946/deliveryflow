import 'package:deliveryflow/core/date_time/week_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WeekCalendar.weekStart', () {
    test('Sunday maps to itself', () {
      // 2026-10-11 is a Sunday
      final sunday = DateTime(2026, 10, 11);
      expect(sunday.weekday, DateTime.sunday);
      expect(WeekCalendar.weekStart(sunday), DateTime(2026, 10, 11));
    });

    test('Saturday maps back to the same Sunday', () {
      final saturday = DateTime(2026, 10, 17);
      expect(WeekCalendar.weekStart(saturday), DateTime(2026, 10, 11));
    });

    test('mid-week Wednesday maps to Sunday', () {
      final wed = DateTime(2026, 10, 14);
      expect(WeekCalendar.weekStart(wed), DateTime(2026, 10, 11));
    });

    test('week spanning month boundary', () {
      // 2026-11-01 is a Sunday; 2026-10-31 is the Saturday before
      final sat = DateTime(2026, 10, 31);
      expect(WeekCalendar.weekStart(sat), DateTime(2026, 10, 25));
      final sun = DateTime(2026, 11, 1);
      expect(WeekCalendar.weekStart(sun), DateTime(2026, 11, 1));
    });

    test('week spanning year boundary', () {
      // 2027-01-01 is a Friday; week starts Sunday 2026-12-27
      final fri = DateTime(2027, 1, 1);
      expect(WeekCalendar.weekStart(fri), DateTime(2026, 12, 27));
    });

    test('leap day belongs to the right week', () {
      // 2024-02-29 is a Thursday; week starts Sunday 2024-02-25
      final leap = DateTime(2024, 2, 29);
      expect(WeekCalendar.weekStart(leap), DateTime(2024, 2, 25));
      expect(WeekCalendar.weekDays(leap), contains(DateTime(2024, 2, 29)));
    });
  });

  group('weekDays / weekEnd / nextWeekStart', () {
    test('weekDays returns 7 days Sunday..Saturday', () {
      final days = WeekCalendar.weekDays(DateTime(2026, 10, 14));
      expect(days.length, 7);
      expect(days.first.weekday, DateTime.sunday);
      expect(days.last.weekday, DateTime.saturday);
      expect(days.first, DateTime(2026, 10, 11));
      expect(days.last, DateTime(2026, 10, 17));
    });

    test('weekEnd is the Saturday of the same week', () {
      expect(WeekCalendar.weekEnd(DateTime(2026, 10, 14)),
          DateTime(2026, 10, 17));
    });

    test('nextWeekStart is 7 days later', () {
      expect(WeekCalendar.nextWeekStart(DateTime(2026, 10, 14)),
          DateTime(2026, 10, 18));
    });

    test('Saturday to Sunday transition: next week starts tomorrow', () {
      final sat = DateTime(2026, 10, 17); // Saturday
      expect(WeekCalendar.nextWeekStart(sat), DateTime(2026, 10, 18));
      expect(WeekCalendar.nextWeekStart(sat).weekday, DateTime.sunday);
    });
  });

  group('isSameDay / isSameWeek / dateKey', () {
    test('same calendar day with different times', () {
      expect(
          WeekCalendar.isSameDay(
              DateTime(2026, 10, 14, 8), DateTime(2026, 10, 14, 23, 59)),
          isTrue);
      expect(
          WeekCalendar.isSameDay(
              DateTime(2026, 10, 14), DateTime(2026, 10, 15)),
          isFalse);
    });

    test('isSameWeek across Sunday boundary', () {
      expect(
          WeekCalendar.isSameWeek(
              DateTime(2026, 10, 11), DateTime(2026, 10, 17)),
          isTrue);
      expect(
          WeekCalendar.isSameWeek(
              DateTime(2026, 10, 17), DateTime(2026, 10, 18)),
          isFalse);
    });

    test('dateKey round-trips', () {
      const key = '2024-02-29';
      expect(WeekCalendar.dateKey(WeekCalendar.parseDateKey(key)), key);
      expect(WeekCalendar.dateKey(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('netShiftMinutes', () {
    test('regular day shift', () {
      expect(WeekCalendar.netShiftMinutes(9 * 60, 17 * 60, 30), 450);
    });

    test('overnight shift (end <= start rolls to next day)', () {
      // 22:00 -> 06:00 with 30m break = 7.5h = 450 min
      expect(WeekCalendar.netShiftMinutes(22 * 60, 6 * 60, 30), 450);
    });

    test('break longer than shift is clamped, never negative', () {
      expect(WeekCalendar.netShiftMinutes(9 * 60, 10 * 60, 999), 0);
    });

    test('zero break', () {
      expect(WeekCalendar.netShiftMinutes(8 * 60, 12 * 60, 0), 240);
    });
  });

  group('daysBetween / addDays', () {
    test('daysBetween across DST-safe calendar arithmetic', () {
      expect(
          WeekCalendar.daysBetween(
              DateTime(2026, 10, 11), DateTime(2026, 10, 17)),
          6);
      expect(
          WeekCalendar.daysBetween(
              DateTime(2026, 10, 17), DateTime(2026, 10, 11)),
          -6);
    });

    test('addDays crosses month boundary', () {
      expect(WeekCalendar.addDays(DateTime(2026, 1, 31), 1),
          DateTime(2026, 2, 1));
    });
  });
}
