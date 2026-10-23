import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the AndroidManifest declarations the app silently depends on.
///
/// v27: the flutter_local_notifications receivers must stay declared or
/// scheduled reminders can never fire while the process is dead.
///
/// v27.8: MainActivity must stay `singleTask` with NO taskAffinity
/// override. Field bug: with singleTop + an empty taskAffinity, a share
/// from Amazon Flex could spawn a SECOND MainActivity instance inside
/// Flex's task while the standalone instance was already running — two
/// Flutter engines / Dart isolates over the same Hive files, each with
/// its own in-memory state (one showed 4 orders for today, the other
/// only 2). singleTask makes Android deliver share/launcher intents to
/// the one existing instance via onNewIntent instead.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync()
      // Collapse whitespace so attribute checks survive reformatting.
      .replaceAll(RegExp(r'\s+'), ' ');

  /// The opening tag of the activity named [name], e.g. `<activity
  /// android:name=".MainActivity" ... >`.
  String activityTag(String name) {
    final nameIdx = manifest.indexOf('android:name="$name"');
    expect(nameIdx, greaterThanOrEqualTo(0),
        reason: 'activity $name not found in AndroidManifest.xml');
    final start = manifest.lastIndexOf('<activity', nameIdx);
    final end = manifest.indexOf('>', nameIdx);
    return manifest.substring(start, end + 1);
  }

  group('MainActivity task configuration (v27.8)', () {
    test('launchMode is singleTask so only one instance can exist', () {
      expect(activityTag('.MainActivity'),
          contains('android:launchMode="singleTask"'));
    });

    test('no taskAffinity override — the activity must not be pulled '
        'into the caller\'s task', () {
      expect(activityTag('.MainActivity'), isNot(contains('taskAffinity')));
    });
  });

  group('notification receivers (v27)', () {
    test('scheduled-notification receivers stay declared', () {
      expect(
          manifest,
          contains(
              'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver'));
      expect(
          manifest,
          contains(
              'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver'));
    });
  });
}
