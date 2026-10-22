import 'dart:io';

import 'package:deliveryflow/core/logging/app_log_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// v27.2: the diagnostics log service. Writes are fire-and-forget by
/// design (logging must never block the app), so tests poll the box
/// until the async Hive writes land instead of awaiting [log].
void main() {
  late Directory tmp;
  late AppLogService svc;

  Future<void> waitFor(bool Function() cond, {int seconds = 15}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (!cond() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('df_log_test_');
    svc = AppLogService();
    await svc.init(hivePath: tmp.path);
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('append + read back: fields round-trip, newest first', () async {
    svc.info(AppLogCategory.system, 'first');
    svc.warn(AppLogCategory.notifications, 'second', detail: 'some detail');
    svc.error(AppLogCategory.tracking, 'third',
        error: StateError('boom'));
    await waitFor(() => svc.length == 3);
    expect(svc.length, 3);

    final entries = svc.entries();
    expect(entries.map((e) => e.message), ['third', 'second', 'first']);
    expect(entries[0].category, AppLogCategory.tracking);
    expect(entries[0].level, AppLogLevel.error);
    // The thrown object lands in detail as "Type: message".
    expect(entries[0].detail, contains('StateError'));
    expect(entries[0].detail, contains('boom'));
    expect(entries[1].level, AppLogLevel.warn);
    expect(entries[1].detail, 'some detail');
    expect(entries[2].detail, isNull);
  });

  test('explicit detail AND thrown error are both kept', () async {
    svc.error(AppLogCategory.share, 'parse failed',
        error: StateError('bad input'), detail: 'received: xyz');
    await waitFor(() => svc.length == 1);
    final detail = svc.entries().single.detail!;
    expect(detail, contains('received: xyz'));
    expect(detail, contains('StateError'));
  });

  test('category filter returns only that category', () async {
    svc.info(AppLogCategory.orders, 'order one');
    svc.info(AppLogCategory.notifications, 'notif one');
    svc.info(AppLogCategory.orders, 'order two');
    await waitFor(() => svc.length == 3);

    final orders = svc.entries(category: AppLogCategory.orders);
    expect(orders.map((e) => e.message), ['order two', 'order one']);
    expect(svc.entries(category: AppLogCategory.share), isEmpty);
  });

  test('cap: oldest entries are pruned past maxEntries', () async {
    const extra = 25;
    final total = AppLogService.maxEntries + extra;
    for (var i = 0; i < total; i++) {
      svc.info(AppLogCategory.system, 'entry $i');
    }
    await waitFor(() => svc.length == AppLogService.maxEntries,
        seconds: 60);
    expect(svc.length, AppLogService.maxEntries);

    final entries = svc.entries();
    expect(entries.first.message, 'entry ${total - 1}');
    expect(entries.last.message, 'entry $extra');
    expect(entries.any((e) => e.message == 'entry 0'), isFalse);
  });

  test('clear empties the log', () async {
    svc.info(AppLogCategory.system, 'to be cleared');
    await waitFor(() => svc.length == 1);
    await svc.clear();
    expect(svc.length, 0);
    expect(svc.entries(), isEmpty);
  });

  test('corrupt stored values are skipped, never crash reads', () async {
    svc.info(AppLogCategory.system, 'good entry');
    await waitFor(() => svc.length == 1);
    final raw = Hive.box<String>(AppLogService.boxName);
    await raw.put(999998, 'this is not json');
    await raw.put(999999, '{"unexpected": "shape"}');
    await raw.put(999997, '42');

    final entries = svc.entries();
    expect(entries.map((e) => e.message), ['good entry']);
    expect(svc.exportText(), contains('good entry'));
  });

  test('uninitialized service is a safe no-op', () async {
    final cold = AppLogService();
    cold.info(AppLogCategory.system, 'goes nowhere');
    cold.error(AppLogCategory.notifications, 'also nowhere',
        error: StateError('x'));
    expect(cold.isReady, isFalse);
    expect(cold.length, 0);
    expect(cold.entries(), isEmpty);
    expect(cold.exportText(), contains('0 entries'));
    await cold.clear(); // must not throw
  });

  test('entries survive a reopen (persisted on disk)', () async {
    svc.info(AppLogCategory.system, 'persisted');
    await waitFor(() => svc.length == 1);
    await Hive.close();

    final reopened = AppLogService();
    await reopened.init(hivePath: tmp.path);
    expect(reopened.entries().map((e) => e.message), ['persisted']);
  });

  group('AppLogEntry', () {
    test('tryDecode rejects garbage and wrong shapes', () {
      expect(AppLogEntry.tryDecode('not json'), isNull);
      expect(AppLogEntry.tryDecode('42'), isNull);
      expect(AppLogEntry.tryDecode('{"c":"orders"}'), isNull);
      expect(AppLogEntry.tryDecode('{"t":1}'), isNull);
    });

    test('tryDecode tolerates unknown category/level names', () {
      final e = AppLogEntry.tryDecode(
          '{"t":5,"c":"future","l":"weird","m":"hi"}');
      expect(e, isNotNull);
      expect(e!.category, AppLogCategory.system);
      expect(e.level, AppLogLevel.info);
      expect(e.message, 'hi');
    });

    test('toTextLine carries stamp, category, level, message, detail',
        () {
      final e = AppLogEntry(
        timestampMillis:
            DateTime(2026, 10, 22, 10, 45, 3).millisecondsSinceEpoch,
        category: AppLogCategory.notifications,
        level: AppLogLevel.error,
        message: 'schedule FAILED id=9998',
        detail: 'PlatformException: nope',
      );
      final line = e.toTextLine();
      expect(line, contains('2026-10-22 10:45:03'));
      expect(line, contains('[notifications]'));
      expect(line, contains('[ERROR]'));
      expect(line, contains('schedule FAILED id=9998'));
      expect(line, contains('PlatformException: nope'));
    });
  });

  test('formatLogError prefixes the runtime type', () {
    expect(formatLogError(StateError('x')), startsWith('StateError:'));
    expect(formatLogError('plain'), 'String: plain');
  });
}
