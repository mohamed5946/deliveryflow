# DeliveryFlow

A Flutter Android app for delivery workers to track their weekly schedule,
daily completed orders, and working hours — with local notifications, weekly
reports, and CSV export. Offline-first, no accounts, no tracking.

- **Language:** Arabic (default, RTL) + English (LTR), switchable instantly
- **Theme:** Liquid Glass design system — dark (midnight navy/cyan/violet)
  and light (white/light blue), System/Light/Dark persisted
- **Storage:** Hive (local, schema-versioned) + SharedPreferences

## Requirements

- Flutter SDK 3.35+ (tested with 3.47.7) with Dart 3.13+
- JDK 17 (e.g. Eclipse Temurin 17)
- Android SDK: `platforms;android-34`, `build-tools;34.0.0`, `platform-tools`
- Android device/emulator running Android 7.0 (API 24)+

## Setup

```bash
cd deliveryflow
# If `flutter pub get` hangs behind a proxy, use:
dart pub get
flutter gen-l10n   # regenerate localizations after editing .arb files
```

### Environment variables (example)

```bash
export JAVA_HOME=~/workspace/.jdk
export ANDROID_HOME=~/workspace/.android-sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=~/workspace/.flutter-sdk/bin:$PATH
```

## Running tests

```bash
flutter analyze   # must report "No issues found!"
flutter test      # 45 tests: unit + widget
```

Test files:

- `test/week_calendar_test.dart` — week arithmetic (Sun–Sat), overnight
  shifts, leap years, DST-safe date math
- `test/database_logic_test.dart` — Hive CRUD, no-duplicate daily
  records/schedules, report averages over recorded days only, CSV export,
  JSON backup/restore, settings persistence
- `test/widget_test.dart` — dashboard (RTL + LTR), order entry stepper,
  theme switching, settings toggles

> Widget tests use real Hive boxes in temp dirs (created synchronously in
> `setUp`, because `testWidgets` runs in a FakeAsync zone where `dart:io`
> async operations never complete). Async DB writes inside test bodies are
> wrapped in `tester.runAsync()`.

## Notifications

Local only, via `flutter_local_notifications` (timezone-aware):

| Reminder | Default | Configurable |
|---|---|---|
| Weekly schedule (Saturday) | 10:00 | time + toggle |
| Daily order entry | 21:00 | time + toggle |
| Weekly report (Saturday) | 20:00 | time + toggle |
| Follow-up (if today unrecorded) | 22:30 | time + toggle |

- Notification channels: schedule / daily / report / follow-up
- Exact alarms: uses `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` where
  granted, with an inexact fallback
- Permission is requested on first enable; a **Send test notification**
  action in Settings verifies delivery
- All scheduling is refreshed automatically after any settings change,
  record save, or schedule save

> Notification delivery was **not tested on real hardware** in this
> environment — verify on a physical device.

## Building the APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

Optional app bundle:

```bash
flutter build appbundle --release
```

### Install on a device

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Troubleshooting

- **Gradle wrapper download fails behind a proxy:** download the
  distribution manually (see `android/gradle/wrapper/gradle-wrapper.properties`
  for the version) and either place it in
  `~/.gradle/wrapper/dists/<name>/<hash>/` or temporarily point
  `distributionUrl` at a `file:///` URL.
- **`sdkmanager` fails with proxy tunneling errors:** download the
  command-line tools / platform packages with `curl` from `dl.google.com`
  using the repository XML, and accept licenses manually.
- **Gradle daemon dies on low-RAM machines:** reduce
  `org.gradle.jvmargs` in `android/gradle.properties`
  (e.g. `-Xmx2G -XX:MaxMetaspaceSize=1G`).

## Project structure

```
lib/
  main.dart                 # entry point, Hive init, notification init
  app/                      # MaterialApp, GoRouter (onboarding redirect)
  core/
    date_time/week_calendar.dart   # Sun–Sat week logic, overnight math
    database/               # Hive models + DatabaseService (CRUD, reports, CSV, backup)
    notifications/          # timezone-aware local notifications
    providers.dart          # Riverpod providers
  theme/                    # Liquid Glass design system (dark/light)
  l10n/                     # app_en.arb / app_ar.arb (ar default)
  features/
    onboarding/ dashboard/ schedule/ daily_orders/
    hours/ reports/ history/ settings/
test/                       # unit + widget tests
android/                    # applicationId com.valor.deliveryflow
```

## Privacy

All data stays on the device (Hive boxes + SharedPreferences). No accounts,
no location, no analytics, no network calls. The only permission beyond the
defaults is notifications (`POST_NOTIFICATIONS`, plus exact-alarm where the
OS requires it). Clearing data is always behind an explicit confirmation.
