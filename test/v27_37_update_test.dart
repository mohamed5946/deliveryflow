import 'dart:convert';
import 'dart:io';

import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/core/date_time/time_format.dart';
import 'package:deliveryflow/core/update/app_update.dart';
import 'package:deliveryflow/core/update/software_update_screen.dart';
import 'package:deliveryflow/features/dashboard/day_hours_section.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:deliveryflow/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// v27.37: in-app self-update + gesture-driven swipe circles.
///
/// - Manifest parsing + version comparison (newer / equal / older).
/// - SHA-256 verification, including mismatch rejection + bad-file
///   deletion (a bad file must never install).
/// - Session dismissal + "remind tonight" suppression rules.
/// - iOS-style Software Update screen: version + REAL size +
///   changelog, Update Now flow, Remind Me Tonight, back = dismiss,
///   unknown-apps permission guidance, no fake "ALSO AVAILABLE".
/// - Swipe circles: circle shape + icon, scale tracks the swipe
///   fraction forward AND backward (gesture-driven, not timed),
///   Delete/Break semantics + confirmations unchanged.

// ── Fakes ──────────────────────────────────────────────────────

class _FakeUpdateClient extends http.BaseClient {
  _FakeUpdateClient({
    required this.manifestBody,
    required this.apkBytes,
    this.manifestStatus = 200,
  });

  final String manifestBody;
  final List<int> apkBytes;
  final int manifestStatus;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.toString().contains('version.json')) {
      final body = utf8.encode(manifestBody);
      return http.StreamedResponse(
        Stream.value(body),
        manifestStatus,
        contentLength: body.length,
        request: request,
      );
    }
    return http.StreamedResponse(
      Stream.value(apkBytes),
      200,
      contentLength: apkBytes.length,
      request: request,
    );
  }
}

class _FakeInstaller implements AppUpdateInstaller {
  _FakeInstaller({this.canInstall = true});

  bool canInstall;
  var openSettingsCalls = 0;
  final installed = <File>[];

  @override
  Future<bool> canInstallUnknownApps() async => canInstall;

  @override
  Future<void> openUnknownAppsSettings() async {
    openSettingsCalls++;
  }

  @override
  Future<void> installApk(File apkFile) async {
    installed.add(apkFile);
  }
}

class _FakeUpdateService extends AppUpdateService {
  _FakeUpdateService({required _FakeInstaller installer})
      : _installer = installer,
        super(client: _FakeUpdateClient(manifestBody: '{}', apkBytes: []),
            installer: installer);

  final _FakeInstaller _installer;
  var downloadCalls = 0;
  var installCalls = 0;

  @override
  Future<File> downloadAndVerify(
    AppUpdateManifest manifest, {
    void Function(double? progress)? onProgress,
  }) async {
    downloadCalls++;
    onProgress?.call(1.0);
    return File('/tmp/deliveryflow-test-update.apk');
  }

  @override
  Future<bool> canInstallUnknownApps() => _installer.canInstallUnknownApps();

  @override
  Future<void> openUnknownAppsSettings() =>
      _installer.openUnknownAppsSettings();

  @override
  Future<void> installVerifiedApk(File apkFile) async {
    installCalls++;
    await _installer.installApk(apkFile);
  }
}

String _manifestJson({
  required int versionCode,
  String versionName = '27.38.0',
  String changelog = 'This update provides fixes for DeliveryFlow.',
  String apkSha256 = '',
  int apkSizeBytes = 0,
}) =>
    jsonEncode({
      'versionCode': versionCode,
      'versionName': versionName,
      'changelog': changelog,
      'apkUrl': 'https://example.invalid/app-release.apk',
      'apkSha256': apkSha256,
      'apkSizeBytes': apkSizeBytes,
    });

AppUpdateManifest _manifest({int code = 71, int size = 0, String sha = ''}) =>
    AppUpdateManifest(
      versionCode: code,
      versionName: '27.38.0',
      changelog: 'This update provides fixes for DeliveryFlow.',
      apkUrl: 'https://example.invalid/app-release.apk',
      apkSha256: sha,
      apkSizeBytes: size,
    );

Future<void> _pumpUpdateScreen(
  WidgetTester tester, {
  required AppUpdateService service,
  AppUpdateManifest? manifest,
  void Function()? onClosed,
  void Function()? onRemind,
  void Function(bool)? onAutoCheck,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('en'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SoftwareUpdateScreen(
          manifest: manifest ?? _manifest(),
          service: service,
          autoCheckEnabled: true,
          onAutoCheckChanged: onAutoCheck ?? (_) {},
          onRemindTonight: onRemind ?? () {},
          onClosed: onClosed ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('manifest parsing (v27.37)', () {
    test('valid manifest parses with all fields', () {
      final m = AppUpdateManifest.tryParse(_manifestJson(
        versionCode: 71,
        apkSha256: 'abc',
        apkSizeBytes: 123,
      ));
      expect(m, isNotNull);
      expect(m!.versionCode, 71);
      expect(m.versionName, '27.38.0');
      expect(m.apkSha256, 'abc');
      expect(m.apkSizeBytes, 123);
      expect(m.changelog, contains('fixes'));
    });

    test('malformed JSON, missing fields, and non-numeric code reject', () {
      expect(AppUpdateManifest.tryParse('not json'), isNull);
      expect(AppUpdateManifest.tryParse('[]'), isNull);
      expect(
          AppUpdateManifest.tryParse(jsonEncode({
            'versionName': '27.38.0',
            'apkUrl': 'https://example.invalid/a.apk',
            'apkSha256': 'abc',
          })),
          isNull);
      expect(
          AppUpdateManifest.tryParse(jsonEncode({
            'versionCode': 'seventy-one',
            'versionName': '27.38.0',
            'apkUrl': 'https://example.invalid/a.apk',
            'apkSha256': 'abc',
          })),
          isNull);
      // Empty APK URL or hash must not trigger a download either.
      expect(
          AppUpdateManifest.tryParse(jsonEncode({
            'versionCode': 71,
            'versionName': '27.38.0',
            'apkUrl': '',
            'apkSha256': 'abc',
          })),
          isNull);
    });
  });

  group('version comparison (v27.37)', () {
    test('only a strictly newer versionCode is an update', () {
      final m = _manifest(code: 71);
      expect(m.isNewerThan(70), isTrue);
      expect(m.isNewerThan(71), isFalse, reason: 'equal must stay silent');
      expect(m.isNewerThan(72), isFalse, reason: 'older must stay silent');
    });

    test('stable URLs point at the latest release, never a fast link',
        () {
      expect(defaultManifestUrl, contains('releases/download/latest'));
      expect(defaultApkUrl, contains('releases/download/latest'));
      expect(defaultManifestUrl, isNot(contains('muse.ai')));
      expect(defaultApkUrl, isNot(contains('muse.ai')));
    });
  });

  group('SHA-256 verification (v27.37)', () {
    test('sha256Hex matches the known vector for "abc"', () {
      expect(sha256Hex(utf8.encode('abc')),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('matching hash + size verifies; mismatches explain why', () {
      final bytes = utf8.encode('fake-apk-bytes');
      final good = _manifest(
          size: bytes.length, sha: sha256Hex(bytes));
      expect(verifyDownloadedApk(bytes, good), isNull);

      final wrongSize = _manifest(
          size: bytes.length + 1, sha: sha256Hex(bytes));
      expect(verifyDownloadedApk(bytes, wrongSize),
          contains('size mismatch'));

      final wrongHash = _manifest(size: bytes.length, sha: '0' * 64);
      expect(
          verifyDownloadedApk(bytes, wrongHash), contains('SHA-256'));
    });

    test('formatApkSize renders iOS-style real sizes', () {
      expect(formatApkSize(74 * 1024 * 1024), '74 MB');
      expect(formatApkSize((6.25 * 1024 * 1024 * 1024).round()), '6.25 GB');
      expect(formatApkSize(0), '');
    });
  });

  group('service fetch + download (v27.37)', () {
    test('fetchManifest throws a real reason on HTTP failure', () async {
      final service = AppUpdateService(
        client: _FakeUpdateClient(
            manifestBody: '{}', apkBytes: [], manifestStatus: 500),
      );
      await expectLater(
        service.fetchManifest(),
        throwsA(isA<AppUpdateException>()
            .having((e) => e.reason, 'reason', contains('500'))),
      );
    });

    test('download mismatch rejects AND deletes the bad file', () async {
      final tmp = Directory.systemTemp.createTempSync('df-update-test-');
      try {
        final bytes = utf8.encode('tampered-apk');
        final service = AppUpdateService(
          client: _FakeUpdateClient(
              manifestBody: '{}', apkBytes: bytes),
          downloadDir: () => tmp,
        );
        final manifest = _manifest(
            size: bytes.length, sha: 'f' * 64); // wrong hash on purpose
        await expectLater(
          service.downloadAndVerify(manifest),
          throwsA(isA<AppUpdateException>()
              .having((e) => e.reason, 'reason', contains('SHA-256'))),
        );
        expect(File('${tmp.path}/updates/app-release.apk').existsSync(),
            isFalse,
            reason: 'a failed verification must leave no installable file');
      } finally {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('download match verifies and returns the file', () async {
      final tmp = Directory.systemTemp.createTempSync('df-update-test-');
      try {
        final bytes = utf8.encode('good-apk');
        final service = AppUpdateService(
          client: _FakeUpdateClient(
              manifestBody: '{}', apkBytes: bytes),
          downloadDir: () => tmp,
        );
        final manifest =
            _manifest(size: bytes.length, sha: sha256Hex(bytes));
        final file = await service.downloadAndVerify(manifest);
        expect(file.existsSync(), isTrue);
        expect(file.readAsBytesSync(), bytes);
      } finally {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });

  group('dismissal + remind-tonight policy (v27.37)', () {
    test('session dismissal covers exactly the dismissed version', () {
      final session = AppUpdateSession();
      expect(session.isDismissed(71), isFalse);
      session.dismiss(71);
      expect(session.isDismissed(71), isTrue);
      expect(session.isDismissed(72), isFalse);
    });

    test('remind-tonight suppresses only until 18:00 the same day', () {
      final setAt = DateTime(2026, 10, 30, 13, 0);
      // Same day, afternoon: suppressed.
      expect(
          AppUpdateSession.isRemindSuppressed(
            remindCode: 71,
            remindSetAt: setAt,
            manifestCode: 71,
            now: DateTime(2026, 10, 30, 16, 0),
          ),
          isTrue);
      // Same day, evening: "tonight" has arrived — show again.
      expect(
          AppUpdateSession.isRemindSuppressed(
            remindCode: 71,
            remindSetAt: setAt,
            manifestCode: 71,
            now: DateTime(2026, 10, 30, 19, 0),
          ),
          isFalse);
      // Next day: show again.
      expect(
          AppUpdateSession.isRemindSuppressed(
            remindCode: 71,
            remindSetAt: setAt,
            manifestCode: 71,
            now: DateTime(2026, 10, 31, 10, 0),
          ),
          isFalse);
      // Different version or no reminder: never suppressed.
      expect(
          AppUpdateSession.isRemindSuppressed(
            remindCode: 71,
            remindSetAt: setAt,
            manifestCode: 72,
            now: DateTime(2026, 10, 30, 16, 0),
          ),
          isFalse);
      expect(
          AppUpdateSession.isRemindSuppressed(
            remindCode: null,
            remindSetAt: null,
            manifestCode: 71,
            now: DateTime(2026, 10, 30, 16, 0),
          ),
          isFalse);
    });
  });

  group('Software Update screen (v27.37)', () {
    testWidgets('renders version, real size, changelog, actions; '
        'no ALSO AVAILABLE section', (tester) async {
      final installer = _FakeInstaller();
      await _pumpUpdateScreen(tester,
          service: _FakeUpdateService(installer: installer),
          manifest: _manifest(
              size: 74 * 1024 * 1024, sha: 'a' * 64));
      expect(find.text('Software Update'), findsOneWidget);
      expect(find.text('DeliveryFlow 27.38.0'), findsOneWidget);
      expect(find.text('74 MB'), findsOneWidget);
      expect(find.text('This update provides fixes for DeliveryFlow.'),
          findsOneWidget);
      expect(find.text('Update Now'), findsOneWidget);
      expect(find.text('Remind Me Tonight'), findsOneWidget);
      expect(
          find.text(
              'By updating, you install the latest version of DeliveryFlow.'),
          findsOneWidget);
      expect(find.text('Automatic Updates'), findsOneWidget);
      expect(find.text('ALSO AVAILABLE'), findsNothing);
      expect(find.text('Upgrade to iOS 27'), findsNothing);
    });

    testWidgets('back reports a session dismissal, not a reminder',
        (tester) async {
      var closed = 0;
      var reminded = 0;
      await _pumpUpdateScreen(tester,
          service: _FakeUpdateService(installer: _FakeInstaller()),
          onClosed: () => closed++,
          onRemind: () => reminded++);
      await tester.tap(find.byKey(const ValueKey('software-update-back')));
      await tester.pump();
      expect(closed, 1);
      expect(reminded, 0);
    });

    testWidgets('Remind Me Tonight reports a reminder, not a dismissal',
        (tester) async {
      var closed = 0;
      var reminded = 0;
      await _pumpUpdateScreen(tester,
          service: _FakeUpdateService(installer: _FakeInstaller()),
          onClosed: () => closed++,
          onRemind: () => reminded++);
      await tester.tap(find.byKey(const ValueKey('remind-tonight-button')));
      await tester.pump();
      expect(reminded, 1);
      expect(closed, 0);
    });

    testWidgets('Update Now downloads, verifies, then installs',
        (tester) async {
      final installer = _FakeInstaller();
      final service = _FakeUpdateService(installer: installer);
      await _pumpUpdateScreen(tester, service: service);
      await tester.tap(find.byKey(const ValueKey('update-now-button')));
      await tester.pump();
      expect(service.downloadCalls, 1);
      expect(service.installCalls, 1);
      expect(installer.installed, hasLength(1));
    });

    testWidgets(
        'missing unknown-apps permission shows guidance instead of '
        'downloading', (tester) async {
      final installer = _FakeInstaller(canInstall: false);
      final service = _FakeUpdateService(installer: installer);
      await _pumpUpdateScreen(tester, service: service);
      await tester.tap(find.byKey(const ValueKey('update-now-button')));
      await tester.pump();
      expect(service.downloadCalls, 0);
      expect(find.text('Allow app installs'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.pump();
      expect(installer.openSettingsCalls, 1);
      expect(service.downloadCalls, 0);
    });
  });

  group('swipe circles (v27.37)', () {
    Future<void> pumpSection(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: SingleChildScrollView(
              child: DayHoursSection(
                day: DailySchedule(
                  dateKey: '2026-10-25',
                  startMinutes: 11 * 60,
                  endMinutes: 22 * 60,
                  breakDurationMinutes: 0,
                ),
                selectedDay: DateTime(2026, 10, 25),
                now: DateTime(2026, 10, 25, 13, 30),
                timeFormat: TimeFormatMode.h24,
                arabic: true,
                onToggleBreak: (_) {},
                onDelete: (_) {},
                onAssignHour: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Finder blockKey(int start) =>
        find.byKey(ValueKey('day-hour-block-2026-10-25-$start'));
    Finder circleScaleKey(int start) =>
        find.byKey(ValueKey('block-action-circle-scale-$start'));

    double circleScale(WidgetTester tester, int start) {
      final t =
          tester.widget<Transform>(circleScaleKey(start));
      return t.transform.getMaxScaleOnAxis();
    }

    bool hasCircle(WidgetTester tester) => find
        .byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle)
        .evaluate()
        .isNotEmpty;

    testWidgets('revealed Delete is a red circle with a trash icon',
        (tester) async {
      await pumpSection(tester);
      await tester.timedDrag(
          blockKey(840), const Offset(-150, 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(hasCircle(tester), isTrue);
      expect(find.byIcon(Icons.delete_rounded), findsOneWidget);
      expect(
          find.byKey(const ValueKey('block-action-delete-840')), findsOneWidget);
      expect(circleScale(tester, 840), greaterThan(0.95),
          reason: 'fully revealed circle is full size');
    });

    testWidgets('revealed Break is an orange circle with a coffee icon',
        (tester) async {
      await pumpSection(tester);
      await tester.timedDrag(
          blockKey(840), const Offset(150, 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(hasCircle(tester), isTrue);
      expect(find.byIcon(Icons.coffee_rounded), findsOneWidget);
      expect(
          find.byKey(const ValueKey('block-action-break-840')), findsOneWidget);
    });

    testWidgets('circle scale tracks the swipe: small drag = dot, '
        'drag back = shrink', (tester) async {
      await pumpSection(tester);
      // Held gesture (no release): the reveal stays exactly where
      // the finger holds it, so the scale reads the live drag
      // fraction — a timedDrag would release and snap, which is a
      // different behaviour from the scrub under test.
      final gesture =
          await tester.startGesture(tester.getCenter(blockKey(840)));
      // Held gesture (no release): drag open in steps, then drag
      // BACK in steps, reading the circle's scale at each held
      // position. The scale must follow the finger in both
      // directions. Four open moves + two back moves are used on
      // purpose: whether or not the gesture recognizer swallows
      // the first move into its touch slop, the held offsets stay
      // strictly decreasing (near-full -> mid -> dot), so every
      // assertion below holds under either delivery.
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(-30, 0));
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('block-action-delete-840')),
          findsOneWidget);
      expect(circleScaleKey(840), findsOneWidget);
      final openScale = circleScale(tester, 840);
      expect(openScale, greaterThan(0.9),
          reason: 'near-full reveal must be near full size');

      // Drag BACK one step: the circle shrinks, but stays big.
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(circleScaleKey(840), findsOneWidget);
      final midScale = circleScale(tester, 840);
      expect(midScale, lessThan(openScale),
          reason: 'reversing the swipe must shrink the circle');
      expect(midScale, greaterThan(0.5));

      // Drag BACK another step: the circle shrinks to a dot.
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(circleScaleKey(840), findsOneWidget);
      final dotScale = circleScale(tester, 840);
      expect(dotScale, lessThan(midScale),
          reason: 'reversing further must shrink the circle further');
      expect(dotScale, lessThan(0.5),
          reason: 'a small remaining reveal must be a small dot');
      expect(dotScale, greaterThan(0.05));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('swipe alone still changes nothing; Delete still '
        'confirms before deleting', (tester) async {
      var deleted = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: SingleChildScrollView(
              child: DayHoursSection(
                day: DailySchedule(
                  dateKey: '2026-10-25',
                  startMinutes: 11 * 60,
                  endMinutes: 22 * 60,
                  breakDurationMinutes: 0,
                ),
                selectedDay: DateTime(2026, 10, 25),
                now: DateTime(2026, 10, 25, 13, 30),
                timeFormat: TimeFormatMode.h24,
                arabic: true,
                onToggleBreak: (_) {},
                onDelete: (s) => deleted.add(s),
                onAssignHour: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.timedDrag(
          blockKey(840), const Offset(-150, 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty, reason: 'swiping alone never deletes');
      await tester.tap(find.byKey(const ValueKey('block-action-delete-840')));
      await tester.pump();
      expect(find.text('هل أنت متأكد من حذف البلوكاية؟'), findsOneWidget);
    });
  });
}
