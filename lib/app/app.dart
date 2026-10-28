import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/providers.dart';
import '../core/app_lock/app_lock_gate.dart';
import '../theme/app_theme.dart';
import '../theme/theme_reveal.dart';
import 'router.dart';

/// Root widget: theme, locale and router wiring.
class DeliveryFlowApp extends ConsumerWidget {
  const DeliveryFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    // v27.25: in-memory theme override, set for a single frame while the
    // reveal captures the target theme (never persisted directly).
    final themeOverride = ref.watch(themeOverrideProvider);

    final locale = Locale(settings.languageCode);
    // Keep intl in sync for date/number formatting.
    Intl.defaultLocale = settings.languageCode == 'ar' ? 'ar' : 'en';

    return MaterialApp.router(
      title: 'DeliveryFlow',
      debugShowCheckedModeBanner: false,
      theme: themeOverride ?? AppTheme.light(settings.themePreset),
      darkTheme: themeOverride ?? AppTheme.dark(settings.themePreset),
      themeMode: themeOverride != null
          ? ThemeMode.light
          : AppTheme.themeModeFromInt(settings.themeMode),
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // v27.24: app lock overlay above every route (see AppLockGate).
      // v27.25: the whole content sits in a RepaintBoundary so the
      // theme reveal can screenshot it (including the bottom nav bar),
      // with the reveal overlay stacked on top.
      builder: (context, child) => Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              key: themeRevealBoundaryKey,
              child: AppLockGate(child: child ?? const SizedBox()),
            ),
          ),
          const Positioned.fill(child: ThemeRevealOverlay()),
        ],
      ),
      routerConfig: router,
    );
  }
}
