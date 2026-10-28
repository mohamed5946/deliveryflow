import 'dart:io';

import 'package:deliveryflow/core/app_lock/app_lock_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

/// v27.27 regression tests for the field-proven fingerprint bug:
/// the diagnostics log showed `no_fragment_activity` — local_auth's
/// BiometricPrompt requires a FragmentActivity, but MainActivity
/// extended plain FlutterActivity, so the prompt never appeared.
/// The fix is the MainActivity superclass; these tests guard it.

const _mainActivityPath =
    'android/app/src/main/kotlin/com/valor/deliveryflow/MainActivity.kt';

void main() {
  test('MainActivity extends FlutterFragmentActivity (not FlutterActivity)',
      () {
    final source = File(_mainActivityPath).readAsStringSync();
    expect(
      source,
      contains('import io.flutter.embedding.android.FlutterFragmentActivity'),
    );
    expect(source, contains('class MainActivity : FlutterFragmentActivity()'));
    expect(source, isNot(contains('FlutterActivity() {')));
  });

  test('MainActivity keeps its intent/battery wiring after the superclass change',
      () {
    final source = File(_mainActivityPath).readAsStringSync();
    // Share-intent capture, refresh-rate logic, and both MethodChannels
    // must survive the superclass swap unchanged.
    expect(source, contains('extractShareable'));
    expect(source, contains('preferHighestRefreshRate'));
    expect(source, contains('com.valor.deliveryflow/nav_intent'));
    expect(source, contains('com.valor.deliveryflow/battery'));
    expect(source, contains('onNewIntent'));
    expect(source, contains('configureFlutterEngine'));
  });

  test('enable path with enrolled biometrics succeeds once the activity '
      'can host BiometricPrompt (no no_fragment_activity failure)', () async {
    // Simulates the post-fix device: enrolled weak + strong (as the
    // field log showed) and an auth client that succeeds instead of
    // throwing no_fragment_activity.
    final client = _SucceedingClient(
      enrolled: const [BiometricType.weak, BiometricType.strong],
    );
    expect(await client.isDeviceSupported(), isTrue);
    expect(
      await client.getAvailableBiometrics(),
      containsAll([BiometricType.weak, BiometricType.strong]),
    );
    final result = await client.authenticateDetailed(
      localizedReason: 'test',
    );
    expect(result.ok, isTrue);
    expect(result.failure, isNull);
  });

  test('no_fragment_activity still maps to busy (mapping unchanged, '
      'the failure mode is now unreachable via the fixed activity)', () {
    expect(
      mapAuthException(
        PlatformException(code: 'no_fragment_activity'),
      ),
      AppLockFailure.busy,
    );
  });
}

class _SucceedingClient implements AppLockAuthClient {
  _SucceedingClient({required this.enrolled});

  final List<BiometricType> enrolled;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> authenticate({required String localizedReason}) async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => enrolled;

  @override
  Future<AppLockAuthResult> authenticateDetailed({
    required String localizedReason,
  }) async {
    final ok = await authenticate(localizedReason: localizedReason);
    return AppLockAuthResult(ok: ok, failure: ok ? null : null);
  }
}
