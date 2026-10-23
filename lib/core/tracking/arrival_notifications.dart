import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

/// v27.8: the arrival-prompt plumbing shared by three isolates.
///
/// - The BACKGROUND TRACKING isolate posts the «هل وصلت؟» prompt via
///   [ArrivalPromptPoster] on its own dedicated max-importance channel.
/// - A «لا» tap is delivered by flutter_local_notifications to the
///   app's notification-response handlers (foreground handler in
///   NotificationService + [arrivalNotificationResponseBackground]),
///   which record it through [writeArrivalNoResponse] into
///   `arrival_response_<orderId>.json` next to the tracking progress
///   file.
/// - The tracking isolate polls that file during the 10-second
///   countdown ([readArrivalResponse]) — no Hive access outside the
///   main isolate, ever.
class ArrivalNotifications {
  static const String channelId = 'deliveryflow_arrivals';
  static const String channelName = 'Arrival detection';
  static const String channelDescription =
      'Automatic arrival confirmation while a delivery is tracked';

  /// Fixed ids in their own range — reminders use 1000–9999.
  static const int outgoingNotificationId = 42101;
  static const int returningNotificationId = 42102;

  static const String noActionId = 'arrival_no';

  static int notificationIdForLeg(String leg) =>
      leg == 'returning' ? returningNotificationId : outgoingNotificationId;

  static String payload({
    required String orderId,
    required String leg,
    required int promptId,
  }) =>
      'arrival|$orderId|$leg|$promptId';

  /// Parses a prompt payload; null when it is not an arrival payload.
  static ({String orderId, String leg, int promptId})? parsePayload(
      String? payload) {
    if (payload == null) return null;
    final parts = payload.split('|');
    if (parts.length != 4 || parts[0] != 'arrival') return null;
    final promptId = int.tryParse(parts[3]);
    if (promptId == null) return null;
    return (orderId: parts[1], leg: parts[2], promptId: promptId);
  }
}

Future<File> arrivalResponseFile(String orderId) async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/arrival_response_$orderId.json');
}

/// Records a «لا» tap for the prompt identified by [payload]. Called
/// from BOTH notification-response handlers; idempotent per prompt.
Future<void> writeArrivalNoResponse(String? payload) async {
  final parsed = ArrivalNotifications.parsePayload(payload);
  if (parsed == null) return;
  try {
    final file = await arrivalResponseFile(parsed.orderId);
    await file.writeAsString(json.encode({
      'action': 'no',
      'leg': parsed.leg,
      'promptId': parsed.promptId,
      'at': DateTime.now().millisecondsSinceEpoch,
    }));
  } catch (_) {
    // Best effort: if the response can't be recorded the countdown
    // simply confirms — the same outcome as no tap at all.
  }
}

/// Reads the recorded response for [orderId], or null when there is
/// none (or it is unreadable).
Future<Map<String, dynamic>?> readArrivalResponse(String orderId) async {
  try {
    final file = await arrivalResponseFile(orderId);
    if (!await file.exists()) return null;
    return json.decode(await file.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Future<void> clearArrivalResponse(String orderId) async {
  try {
    final file = await arrivalResponseFile(orderId);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

/// Background notification-response entry point (registered in
/// NotificationService.init). Runs in the plugin's background isolate
/// when a «لا» action is tapped while the app UI is not in the
/// foreground; the tracking isolate picks the response up from the
/// shared file during its countdown.
@pragma('vm:entry-point')
Future<void> arrivalNotificationResponseBackground(
    NotificationResponse response) async {
  if (response.actionId == ArrivalNotifications.noActionId) {
    await writeArrivalNoResponse(response.payload);
  }
}

/// Foreground notification-response handler (main isolate): the same
/// recording, for taps that arrive while the app is open.
Future<void> handleArrivalNotificationResponse(
    NotificationResponse response) async {
  if (response.actionId == ArrivalNotifications.noActionId) {
    await writeArrivalNoResponse(response.payload);
  }
}

/// Posts/cancels arrival prompts from inside the tracking isolate.
/// Mirrors the isolate's existing Arabic service-notification strings
/// (the isolate has no l10n context); the same copy lives in the arb
/// files as arrivalAtCustomerTitle / arrivalAtMartTitle /
/// arrivalAutoConfirmBody / arrivalNo for the main isolate.
class ArrivalPromptPoster {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      const channel = AndroidNotificationChannel(
        ArrivalNotifications.channelId,
        ArrivalNotifications.channelName,
        description: ArrivalNotifications.channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      _ready = true;
    } catch (_) {
      // Arrival prompts are additive — tracking must never die
      // because the prompt channel failed to come up.
      _ready = false;
    }
  }

  Future<void> showPrompt({
    required String orderId,
    required String leg,
    required int promptId,
  }) async {
    if (!_ready) return;
    try {
      const details = AndroidNotificationDetails(
        ArrivalNotifications.channelId,
        ArrivalNotifications.channelName,
        channelDescription: ArrivalNotifications.channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            ArrivalNotifications.noActionId,
            'لا',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      );
      await _plugin.show(
        ArrivalNotifications.notificationIdForLeg(leg),
        leg == 'returning' ? 'هل وصلت للمارت؟' : 'هل وصلت إلى العميل؟',
        'هيتم تأكيد الوصول تلقائيًا خلال ١٠ ثوانٍ لو ما دوستش «لا»',
        const NotificationDetails(android: details),
        payload: ArrivalNotifications.payload(
          orderId: orderId,
          leg: leg,
          promptId: promptId,
        ),
      );
    } catch (_) {}
  }

  Future<void> cancelLeg(String leg) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(ArrivalNotifications.notificationIdForLeg(leg));
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    await cancelLeg('outgoing');
    await cancelLeg('returning');
  }
}
