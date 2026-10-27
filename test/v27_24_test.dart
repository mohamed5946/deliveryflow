import 'dart:io';

import 'package:deliveryflow/core/app_lock/app_lock_service.dart';
import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/theme/bin_eating_delete_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClient implements AppLockAuthClient {
  _FakeClient({required this.supported, this.authResult = true});

  final bool supported;
  final bool authResult;
  int authCalls = 0;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> authenticate({required String localizedReason}) async {
    authCalls++;
    return authResult;
  }
}

void main() {
  group('v27.24 app lock: state machine', () {
    test('defaults: OFF means unlocked, ON means locked at cold start', () {
      expect(AppLockState(enabled: false).locked, isFalse);
      expect(AppLockState(enabled: true).locked, isTrue);
    });

    test('background re-arms, foreground re-locks, auth unlocks session',
        () {
      final s = AppLockState(enabled: true);
      s.onAuthSuccess();
      expect(s.locked, isFalse);
      s.onBackground();
      expect(s.locked, isTrue);
      s.onAuthSuccess();
      expect(s.locked, isFalse);
      s.onForeground();
      expect(s.locked, isTrue);
    });

    test('enabling from inside the app does not lock the current session',
        () {
      final s = AppLockState(enabled: false);
      s.setEnabled(true);
      expect(s.locked, isFalse);
      s.onBackground();
      expect(s.locked, isTrue);
    });

    test('disabling always unlocks', () {
      final s = AppLockState(enabled: true);
      s.setEnabled(false);
      expect(s.locked, isFalse);
    });
  });

  group('v27.24 app lock: settings persistence', () {
    test('default is OFF and survives a JSON round-trip', () {
      expect(UserSettings().appLockEnabled, isFalse);
      final s = UserSettings()..appLockEnabled = true;
      final back = UserSettings.fromJson(s.toJson());
      expect(back.appLockEnabled, isTrue);
      expect(UserSettings.fromJson(const {}).appLockEnabled, isFalse);
    });

    test('adapter appends field 50 without touching earlier indices', () {
      final src = File('lib/core/database/models.dart').readAsStringSync();
      expect(src, contains('@HiveField(50)'));
      expect(src, contains('appLockEnabled'));
      expect(src, contains('..writeByte(51)')); // 51 fields, 0..50
      expect(src, contains('fields[50] as bool?) ?? false'));
      // Earlier indices untouched.
      expect(src, contains('@HiveField(29)'));
      expect(src, contains('fields[29] as bool?) ?? false'));
    });
  });

  group('v27.24 app lock: service with mocked capability', () {
    test('canUseLock mirrors the OS capability, auth forwards the call',
        () async {
      final off = AppLockService(_FakeClient(supported: false));
      expect(await off.canUseLock(), isFalse);
      final fake = _FakeClient(supported: true, authResult: true);
      final on = AppLockService(fake);
      expect(await on.canUseLock(), isTrue);
      expect(await on.authenticate(localizedReason: 'test'), isTrue);
      expect(fake.authCalls, 1);
      final denied = AppLockService(_FakeClient(supported: true, authResult: false));
      expect(await denied.authenticate(localizedReason: 'test'), isFalse);
    });
  });

  group('v27.24 app lock: wiring', () {
    test('gate sits above every route and suppresses itself before gates',
        () {
      final app = File('lib/app/app.dart').readAsStringSync();
      expect(app, contains('AppLockGate(child:'));
      final gate = File('lib/core/app_lock/app_lock_gate.dart').readAsStringSync();
      expect(gate, contains('settings.registered'));
      expect(gate, contains('settings.onboardingDone'));
      expect(gate, contains('AppLifecycleState.paused'));
      expect(gate, isNot(contains('onChanged: (v) =>')));
      // No way to disable from inside the lock screen.
      expect(gate, isNot(contains('appLockEnabled = false')));
      // No blur in the lock overlay (opaque screen, cheap by design).
      expect(gate, isNot(contains('BackdropFilter')));
    });

    test('profile toggle probes capability and disables when unavailable',
        () {
      final profile =
          File('lib/features/profile/profile_screen.dart').readAsStringSync();
      expect(profile, contains('l10n.appLock'));
      expect(profile, contains('enabled: _appLockAvailable != false'));
      expect(profile, contains('l10n.appLockUnavailable'));
      expect(profile, contains('canUseLock()'));
    });

    test('manifest declares the biometric permission', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, contains('USE_BIOMETRIC'));
    });

    test('localized keys exist in both languages', () {
      for (final path in [
        'lib/l10n/app_ar.arb',
        'lib/l10n/app_en.arb',
      ]) {
        final arb = File(path).readAsStringSync();
        for (final key in [
          'appLock',
          'appLockDesc',
          'appLockUnavailable',
          'appLockUnlockTitle',
          'appLockRetry',
        ]) {
          expect(arb, contains('"$key"'), reason: '$path missing $key');
        }
      }
    });
  });

  group('v27.24 bin-eats-label delete button', () {
    Future<void> pumpButton(WidgetTester tester, void Function() onConfirmed,
        {String label = 'Delete'}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BinEatingDeleteButton(
                label: label,
                onConfirmed: onConfirmed,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('label -> letters eaten -> circle -> onConfirmed once',
        (tester) async {
      var confirmed = 0;
      await pumpButton(tester, () => confirmed++);
      expect(find.text('D'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsWidgets);

      await tester.tap(find.byType(BinEatingDeleteButton));
      // Letter gap for 6 letters: 700~/6 = 116 -> clamped to 90ms.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 90));
        expect(confirmed, 0, reason: 'nothing deleted mid-animation');
      }
      // Shrink (300ms) then onConfirmed.
      await tester.pump(const Duration(milliseconds: 400));
      expect(confirmed, 1);
      // Circle state: the button shrinks to a 48-wide circle.
      final size = tester.getSize(find.byType(AnimatedContainer).first);
      expect(size.width, 48);
    });

    testWidgets('taps during the animation are ignored', (tester) async {
      var confirmed = 0;
      await pumpButton(tester, () => confirmed++);
      await tester.tap(find.byType(BinEatingDeleteButton));
      await tester.pump(const Duration(milliseconds: 90));
      await tester.tap(find.byType(BinEatingDeleteButton));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 90));
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(confirmed, 1);
    });

    test('confirmation dialogs use the animated button, Break does not',
        () {
      for (final path in [
        'lib/features/daily_orders/order_entry_screen.dart',
        'lib/features/history/day_orders_screen.dart',
        'lib/features/history/history_screen.dart',
        'lib/features/profile/profile_screen.dart',
        'lib/features/profile/diagnostics_log_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src, contains('BinEatingDeleteButton'),
            reason: '$path should use the animated delete button');
      }
      final hours =
          File('lib/features/dashboard/day_hours_section.dart').readAsStringSync();
      expect(hours, contains('_confirmDelete'));
      // Break still uses the plain Yes/No dialog.
      expect(hours, contains('onToggleBreak(start)'));
      expect(hours, contains('_confirm(context, isBreak)'));
      // The animated button itself uses no blur.
      final widget =
          File('lib/theme/bin_eating_delete_button.dart').readAsStringSync();
      expect(widget, isNot(contains('BackdropFilter')));
    });
  });
}
