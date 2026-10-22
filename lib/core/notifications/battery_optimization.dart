import 'package:flutter/services.dart';

/// Android battery-optimization exemption state (v27).
///
/// Aggressive OEM battery managers (Infinix XOS and friends) defer or
/// kill scheduled alarms for non-exempt apps, so reminders arrive late
/// or never even with exact-alarm permission granted. Exempting the app
/// is the reliable fix; these calls go through a tiny native channel in
/// MainActivity (no extra plugin dependency).
///
/// Both calls fail safe: when the state can't be determined the app is
/// treated as exempt, so the settings UI never nags on error.
class BatteryOptimization {
  BatteryOptimization._();

  static const MethodChannel _channel =
      MethodChannel('com.valor.deliveryflow/battery');

  /// True when the app is exempt from battery optimization.
  static Future<bool> isIgnoring() async {
    try {
      return await _channel.invokeMethod<bool>('isIgnoring') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens the system dialog asking the user to exempt the app
  /// (falls back to the battery-optimization settings list natively).
  static Future<void> requestIgnore() async {
    try {
      await _channel.invokeMethod<void>('requestIgnore');
    } catch (_) {}
  }
}
