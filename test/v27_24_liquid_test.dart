import 'dart:io';

import 'package:deliveryflow/core/database/models.dart';
import 'package:deliveryflow/theme/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('v27.24 liquid-glass trial: setting persistence', () {
    test('defaults ON and survives a JSON round-trip ON/OFF', () {
      expect(UserSettings().liquidGlassEnabled, isTrue);
      final on = UserSettings()..liquidGlassEnabled = true;
      expect(UserSettings.fromJson(on.toJson()).liquidGlassEnabled, isTrue);
      final off = UserSettings()..liquidGlassEnabled = false;
      expect(UserSettings.fromJson(off.toJson()).liquidGlassEnabled,
          isFalse);
      // Missing key (pre-v27.24 rows) reads as ON: existing installs
      // get the trial, and the toggle can turn it OFF.
      expect(UserSettings.fromJson(const {}).liquidGlassEnabled, isTrue);
    });

    test('adapter appends field 51 without touching earlier indices', () {
      final src = File('lib/core/database/models.dart').readAsStringSync();
      expect(src, contains('@HiveField(51)'));
      expect(src, contains('liquidGlassEnabled'));
      expect(src, contains('..writeByte(52)')); // 52 fields, 0..51
      expect(src, contains('fields[51] as bool?) ?? true'));
      // Earlier indices untouched (app lock still defaults OFF).
      expect(src, contains('@HiveField(50)'));
      expect(src, contains('fields[50] as bool?) ?? false'));
    });

    test('localized toggle keys exist in both locales', () {
      for (final path in [
        'lib/l10n/app_ar.arb',
        'lib/l10n/app_en.arb',
      ]) {
        final arb = File(path).readAsStringSync();
        expect(arb, contains('"liquidGlass"'));
        expect(arb, contains('"liquidGlassDesc"'));
      }
      final gen = File('lib/l10n/gen/app_localizations.dart')
          .readAsStringSync();
      expect(gen, contains('liquidGlass'));
    });
  });

  group('v27.24 liquid-glass trial: rendering', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('GlassCard renders the treatment when ON, old glass when OFF',
        (tester) async {
      await tester.pumpWidget(wrap(const GlassCard(
        liquid: true,
        child: Text('home card'),
      )));
      expect(find.byKey(const Key('liquidGlassSpecular')), findsOneWidget);
      expect(find.byKey(const Key('liquidGlassEdge')), findsOneWidget);
      expect(find.byKey(const Key('liquidGlassGlow')), findsOneWidget);
      expect(find.text('home card'), findsOneWidget);

      await tester.pumpWidget(wrap(const GlassCard(child: Text('old'))));
      expect(find.byKey(const Key('liquidGlassSpecular')), findsNothing);
      expect(find.byKey(const Key('liquidGlassEdge')), findsNothing);
      expect(find.byKey(const Key('liquidGlassGlow')), findsNothing);
      expect(find.text('old'), findsOneWidget);
    });

    testWidgets('GlassNavBar renders the treatment when ON, old glass when OFF',
        (tester) async {
      Widget bar(bool liquid) => GlassNavBar(
            liquid: liquid,
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            icons: const [Icons.home_outlined, Icons.person_outlined],
            selectedIcons: const [Icons.home_rounded, Icons.person_rounded],
            labels: const ['Home', 'Profile'],
          );
      await tester.pumpWidget(wrap(bar(true)));
      expect(find.byKey(const Key('liquidGlassSpecular')), findsOneWidget);
      await tester.pumpWidget(wrap(bar(false)));
      expect(find.byKey(const Key('liquidGlassSpecular')), findsNothing);
    });

    testWidgets('liquid card tap still fires (overlay never eats taps)',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(GlassCard(
        liquid: true,
        onTap: () => taps++,
        child: const Text('tap me'),
      )));
      await tester.tap(find.text('tap me'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('no BackdropFilter without a RepaintBoundary ancestor',
        (tester) async {
      await tester.pumpWidget(wrap(Column(
        children: [
          const GlassCard(liquid: true, child: Text('card')),
          GlassNavBar(
            liquid: true,
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            icons: const [Icons.home_outlined],
            selectedIcons: const [Icons.home_rounded],
            labels: const ['Home'],
          ),
        ],
      )));
      final blurs = find.byType(BackdropFilter);
      expect(blurs, findsWidgets);
      for (final element in blurs.evaluate()) {
        var guarded = false;
        element.visitAncestorElements((ancestor) {
          if (ancestor.widget is RepaintBoundary) guarded = true;
          return true;
        });
        expect(guarded, isTrue,
            reason: 'BackdropFilter without RepaintBoundary found');
      }
      // The liquid overlay itself adds no blur at all.
      final src =
          File('lib/theme/design_system.dart').readAsStringSync();
      final overlay = src.substring(
          src.indexOf('class _LiquidGlassOverlay'),
          src.indexOf('/// A translucent frosted-glass card.'));
      expect(overlay, isNot(contains('BackdropFilter')));
      expect(overlay, isNot(contains('Shader')));
    });
  });

  group('v27.24 liquid-glass trial: scope', () {
    test('only the nav bar and home screens opt in', () {
      const allowed = {
        'lib/theme/design_system.dart',
        'lib/app/router.dart',
        'lib/features/dashboard/dashboard_screen.dart',
        'lib/features/dashboard/day_hours_section.dart',
      };
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (allowed.contains(entity.path)) continue;
        if (entity.path.contains('lib/l10n/gen')) continue;
        final src = entity.readAsStringSync();
        expect(src, isNot(contains('liquid:')),
            reason: '${entity.path} opts into liquid glass outside scope');
      }
      final router = File('lib/app/router.dart').readAsStringSync();
      expect(router, contains('liquid: ref.watch(settingsProvider'));
      final dashboard =
          File('lib/features/dashboard/dashboard_screen.dart')
              .readAsStringSync();
      expect(dashboard, contains('liquid: settings.liquidGlassEnabled'));
      final profile =
          File('lib/features/profile/profile_screen.dart').readAsStringSync();
      expect(profile, contains('l10n.liquidGlass'));
      expect(profile, contains('liquidGlassEnabled = v'));
    });
  });
}
