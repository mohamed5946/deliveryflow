import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/providers.dart';
import '../theme/app_theme.dart';
import 'router.dart';

/// Root widget: theme, locale and router wiring.
class DeliveryFlowApp extends ConsumerWidget {
  const DeliveryFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);

    final locale = Locale(settings.languageCode);
    // Keep intl in sync for date/number formatting.
    Intl.defaultLocale = settings.languageCode == 'ar' ? 'ar' : 'en';

    return MaterialApp.router(
      title: 'DeliveryFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(settings.themePreset),
      darkTheme: AppTheme.dark(settings.themePreset),
      themeMode: AppTheme.themeModeFromInt(settings.themeMode),
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
