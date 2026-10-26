import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/date_time/hour_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

/// v27.19 TRUE DELETE: Delete and Break are different stored
/// changes. Delete removes the hour from the day completely —
/// edge deletions shrink the range, middle deletions are recorded
/// in deletedHourStarts and skipped in every derivation, and a
/// deleted hour comes back only through Assign. Break still just
/// marks the hour orange (breakHourStarts) and restores on
/// swipe-right. Protected blocks are gated in the widget (they
/// cannot be swiped open at all); the pure protection set is
/// covered here to prove a deleted hour can never be protected
/// and a protected hour is never deleted by these helpers.
void main() {
  DailySchedule day({
    int start = 8 * 60,
    int end = 12 * 60,
    List<int>? breaks,
    List<int>? deleted,
    bool working = true,
  }) =>
      DailySchedule(
        dateKey: '2026-10-25',
        isWorkingDay: working,
        startMinutes: start,
        endMinutes: end,
        breakDurationMinutes: 0,
        breakHourStarts: breaks,
        deletedHourStarts: deleted,
      );

  group('delete middle hour', () {
    test('removes it from the day list; neighbours keep exact times',
        () {
      final d = deleteHour(day(), 600); // 10:00 of 8-12
      expect(hourBlockStarts(d), [480, 540, 660]);
      expect(d.startMinutes, 8 * 60);
      expect(d.endMinutes, 12 * 60);
      expect(d.deletedHourStarts, [600]);
      // It is NOT stored as a break hour.
      expect(d.breakHourStarts, isEmpty);
    });

    test('deleted hour counts in no summary or net total', () {
      final d = deleteHour(day(), 600);
      final summary = summarizeBlocks(
        day: d,
        dayDate: DateTime(2026, 10, 25),
        now: DateTime(2026, 10, 25, 7, 0),
      );
      // 3 visible blocks, all upcoming at 07:00; the deleted hour
      // is neither worked nor remaining.
      expect(summary, (worked: 0, remaining: 3));
      expect(blockNetMinutes(d), 180);
      expect(d.netPlannedMinutes, 180);
    });

    test('multiple middle deletions accumulate as gaps', () {
      final d = deleteHour(deleteHour(day(), 600), 540);
      expect(hourBlockStarts(d), [480, 660]);
      expect(d.deletedHourStarts, [540, 600]);
      expect(blockNetMinutes(d), 120);
    });

    test('deleting a non-block hour is a no-op', () {
      final d = day();
      expect(identical(deleteHour(d, 720), d), isTrue);
      final withGap = deleteHour(d, 600);
      expect(identical(deleteHour(withGap, 600), withGap), isTrue);
    });
  });

  group('delete edge hour shrinks the range', () {
    test('first hour: start moves past it, no deleted record', () {
      final d = deleteHour(day(), 480);
      expect(hourBlockStarts(d), [540, 600, 660]);
      expect(d.startMinutes, 9 * 60);
      expect(d.endMinutes, 12 * 60);
      expect(d.deletedHourStarts, isEmpty);
      expect(blockNetMinutes(d), 180);
    });

    test('last hour: end moves back to it, no deleted record', () {
      final d = deleteHour(day(), 660);
      expect(hourBlockStarts(d), [480, 540, 600]);
      expect(d.startMinutes, 8 * 60);
      expect(d.endMinutes, 11 * 60);
      expect(d.deletedHourStarts, isEmpty);
      expect(blockNetMinutes(d), 180);
    });

    test('repeated edge deletions keep shrinking', () {
      final d = deleteHour(deleteHour(day(), 480), 540);
      expect(hourBlockStarts(d), [600, 660]);
      expect(d.startMinutes, 10 * 60);
    });

    test('edge deletion after a middle gap keeps the gap', () {
      final d = deleteHour(deleteHour(day(), 600), 480);
      expect(hourBlockStarts(d), [540, 660]);
      expect(d.startMinutes, 9 * 60);
      expect(d.deletedHourStarts, [600]);
    });

    test('overnight edges shrink through the midnight convention', () {
      final night = day(start: 22 * 60, end: 2 * 60);
      final firstGone = deleteHour(night, 1320);
      expect(hourBlockStarts(firstGone), [1380, 1440, 1500]);
      expect(firstGone.startMinutes, 23 * 60);
      final lastGone = deleteHour(night, 1500);
      expect(hourBlockStarts(lastGone), [1320, 1380, 1440]);
      expect(lastGone.endMinutes, 1 * 60);
    });
  });

  group('delete the last remaining block', () {
    test('becomes a day off, not a phantom range', () {
      final d = deleteHour(day(start: 8 * 60, end: 9 * 60), 480);
      expect(d.isWorkingDay, isFalse);
      expect(hourBlockStarts(d), isEmpty);
      expect(blockNetMinutes(d), 0);
      expect(d.netPlannedMinutes, 0);
      // Assign on the day off recreates a one-hour shift.
      final back = assignHour(d, 8, '2026-10-25');
      expect(back.isWorkingDay, isTrue);
      expect(hourBlockStarts(back), [480]);
    });
  });

  group('delete a break hour removes it (never restores it)', () {
    test('middle break block: gone, break mark gone, not work', () {
      final broken = toggleBreakHour(day(), 600);
      expect(breakBlockStarts(broken), {600});
      final d = deleteHour(broken, 600);
      expect(hourBlockStarts(d), [480, 540, 660]);
      expect(d.breakHourStarts, isEmpty);
      expect(d.deletedHourStarts, [600]);
    });

    test('edge break block: range shrinks, break mark pruned', () {
      final broken = toggleBreakHour(day(), 480);
      final d = deleteHour(broken, 480);
      expect(hourBlockStarts(d), [540, 600, 660]);
      expect(d.startMinutes, 9 * 60);
      expect(d.breakHourStarts, isEmpty);
      expect(d.deletedHourStarts, isEmpty);
    });
  });

  group('break is unchanged: still an orange block, still restorable',
      () {
    test('work -> break -> restore round-trips', () {
      final broken = toggleBreakHour(day(), 600);
      expect(hourBlockStarts(broken), [480, 540, 600, 660]);
      expect(breakBlockStarts(broken), {600});
      expect(blockNetMinutes(broken), 180);
      final restored = toggleBreakHour(broken, 600);
      expect(breakBlockStarts(restored), isEmpty);
      expect(hourBlockStarts(restored), [480, 540, 600, 660]);
      expect(restored.deletedHourStarts, isEmpty);
    });
  });

  group('deleted hours and Assign', () {
    test('deleted middle hour is offered and re-adding clears it', () {
      final d = deleteHour(day(), 600);
      expect(availableHoursForAssign(d), contains(10));
      // Work and break hours stay excluded.
      expect(availableHoursForAssign(d), isNot(contains(8)));
      final back = assignHour(d, 10, '2026-10-25');
      expect(hourBlockStarts(back), [480, 540, 600, 660]);
      expect(back.deletedHourStarts, isEmpty);
      expect(back.startMinutes, 8 * 60);
      expect(back.endMinutes, 12 * 60);
    });

    test('deleted edge hour is offered (it is outside the range)', () {
      final d = deleteHour(day(), 480);
      expect(availableHoursForAssign(d), contains(8));
      final back = assignHour(d, 8, '2026-10-25');
      expect(hourBlockStarts(back), [480, 540, 600, 660]);
      expect(back.startMinutes, 8 * 60);
    });

    test('extending past a deleted gap does not resurrect it as break',
        () {
      final d = deleteHour(day(), 600);
      // Extend the end to 14:00: 12:00 and 13:00 become breaks,
      // but the deleted 10:00 stays deleted.
      final extended = assignHour(d, 13, '2026-10-25');
      expect(extended.endMinutes, 14 * 60);
      expect(extended.deletedHourStarts, [600]);
      // 12:00 is the intermediate break; 13:00 is the picked WORK
      // hour, not a break. The deleted 10:00 stays deleted.
      expect(breakBlockStarts(extended), {720});
      expect(hourBlockStarts(extended), [480, 540, 660, 720, 780]);
    });

    test('break hours stay excluded from Assign, as before', () {
      final d = toggleBreakHour(day(), 600);
      expect(availableHoursForAssign(d), isNot(contains(10)));
    });
  });

  group('summaries: deleted excluded, break included as break', () {
    test('worked/remaining exclude deleted, break counts as neither',
        () {
      // 8-12, 10:00 deleted, 11:00 break, now 13:30 on a past day
      // would count all work as worked — use today at 09:30:
      // 8:00 worked, 9:00 current (remaining), 11:00 break.
      final d = deleteHour(toggleBreakHour(day(), 660), 600);
      final summary = summarizeBlocks(
        day: d,
        dayDate: DateTime(2026, 10, 25),
        now: DateTime(2026, 10, 25, 9, 30),
      );
      expect(summary, (worked: 1, remaining: 1));
      expect(blockNetMinutes(d), 120);
    });
  });

  group('protection vs deletion', () {
    test('a deleted hour is never in the protected set', () {
      final d = deleteHour(day(), 600);
      final entries = [
        OrderEntry(
          id: 'a',
          dateKey: '2026-10-25',
          timestampMillis:
              DateTime(2026, 10, 25, 10, 15).millisecondsSinceEpoch,
        ),
      ];
      expect(protectedBlockStarts(day: d, entries: entries), isEmpty);
    });

    test('a protected hour is still protected after other deletions',
        () {
      final d = deleteHour(day(), 540);
      final entries = [
        OrderEntry(
          id: 'a',
          dateKey: '2026-10-25',
          timestampMillis:
              DateTime(2026, 10, 25, 8, 15).millisecondsSinceEpoch,
        ),
      ];
      expect(protectedBlockStarts(day: d, entries: entries), {480});
    });
  });

  group('stale deleted marks', () {
    test('deleted entries outside the span are ignored everywhere',
        () {
      final d = day(deleted: [600, 9999]);
      expect(deletedBlockStarts(d), {600});
      expect(hourBlockStarts(d), [480, 540, 660]);
      expect(d.netPlannedMinutes, 180);
    });
  });
}
