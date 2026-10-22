import 'package:deliveryflow/core/notifications/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// v27.1: the schedule-mode selection and the exact -> inexact retry
/// decision behind the scheduled-notification fallback. The platform
/// call itself needs a device; what is pinned here is the logic that
/// decides — a revoked/misreported exact-alarm permission must
/// degrade to inexact instead of silently losing the reminder.
void main() {
  group('notification channel (v27.3 priority migration)', () {
    // Reminders live on the fresh high-importance channel; the legacy
    // id stays named so the launch cleanup can delete it.
    test('user-facing channel is the _v2 high-importance one', () {
      expect(NotificationService.channelId, 'deliveryflow_reminders_v2');
      expect(
          NotificationService.legacyChannelId, 'deliveryflow_reminders');
    });
  });

  group('androidScheduleModeFor', () {
    test('exact permitted -> exactAllowWhileIdle', () {
      expect(androidScheduleModeFor(true),
          AndroidScheduleMode.exactAllowWhileIdle);
    });

    test('exact not permitted -> inexactAllowWhileIdle', () {
      expect(androidScheduleModeFor(false),
          AndroidScheduleMode.inexactAllowWhileIdle);
    });
  });

  group('shouldRetryInexact', () {
    test('exact attempt + PlatformException -> retry inexact once', () {
      expect(
        shouldRetryInexact(
          usedExact: true,
          error: PlatformException(code: 'exact_alarms_not_permitted'),
        ),
        isTrue,
      );
    });

    test('inexact attempt failing -> no retry (would loop)', () {
      expect(
        shouldRetryInexact(
          usedExact: false,
          error: PlatformException(code: 'exact_alarms_not_permitted'),
        ),
        isFalse,
      );
    });

    test('non-platform errors are not retried', () {
      expect(
        shouldRetryInexact(usedExact: true, error: StateError('boom')),
        isFalse,
      );
      expect(
        shouldRetryInexact(
            usedExact: true, error: ArgumentError('bad id')),
        isFalse,
      );
    });
  });
}
