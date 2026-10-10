import 'package:flutter/material.dart';

/// Premium Material 3 themes: midnight-navy dark and clean light.
class AppTheme {
  static const _seedDark = Color(0xFF4D7CFE);
  static const _seedLight = Color(0xFF2E7CF6);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedDark,
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF0B1020),
      surfaceContainerHighest: const Color(0xFF141B30),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
      // Transparent so the AuroraBackground behind every screen shows through.
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.14)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.14)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF38E1FF), width: 1.6),
        ),
      ),
      textTheme: _textTheme(Brightness.dark),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedLight,
      brightness: Brightness.light,
    ).copyWith(
      surface: const Color(0xFFF4F8FF),
      surfaceContainerHighest: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.light,
      // Transparent so the AuroraBackground behind every screen shows through.
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2E7CF6), width: 1.6),
        ),
      ),
      textTheme: _textTheme(Brightness.light),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(Brightness b) {
    const family = null; // system fonts with good Arabic shaping
    return const TextTheme(
      displayLarge: TextStyle(fontFamily: family, fontWeight: FontWeight.w800),
      headlineSmall: TextStyle(fontFamily: family, fontWeight: FontWeight.w800),
      titleLarge: TextStyle(fontFamily: family, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontFamily: family, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontFamily: family),
      bodyMedium: TextStyle(fontFamily: family),
    );
  }

  /// Resolves the effective [ThemeMode] from the stored int:
  /// 0 = system, 1 = light, 2 = dark.
  static ThemeMode themeModeFromInt(int v) => switch (v) {
        1 => ThemeMode.light,
        2 => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
