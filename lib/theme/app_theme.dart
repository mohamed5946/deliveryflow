import 'package:flutter/material.dart';

/// One selectable visual theme: seed color for the Material 3 color scheme
/// plus the animated aurora background palette (dark + light variants).
class AppThemePreset {
  final int id;
  final String nameAr;
  final String nameEn;
  final Color seed;
  final List<Color> auroraDark; // 4 blob colors
  final List<Color> auroraLight; // 4 blob colors
  final List<Color> bgDark; // 2 background gradient colors
  final List<Color> bgLight; // 2 background gradient colors

  const AppThemePreset({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.seed,
    required this.auroraDark,
    required this.auroraLight,
    required this.bgDark,
    required this.bgLight,
  });

  String name(String languageCode) =>
      languageCode == 'ar' ? nameAr : nameEn;

  static AppThemePreset of(int id) =>
      all[id.clamp(0, all.length - 1)];

  static const List<AppThemePreset> all = [
    AppThemePreset(
      id: 0,
      nameAr: 'أورورا',
      nameEn: 'Aurora',
      seed: Color(0xFF4D7CFE),
      auroraDark: [
        Color(0xFF2E7CF6),
        Color(0xFF7A5CFF),
        Color(0xFF00B8CC),
        Color(0xFFFF5CA8),
      ],
      auroraLight: [
        Color(0xFF8FBEFF),
        Color(0xFFC0A6FF),
        Color(0xFF9FE6FF),
        Color(0xFFFFB9DC),
      ],
      bgDark: [Color(0xFF0A0F24), Color(0xFF060A18)],
      bgLight: [Color(0xFFE9F2FF), Color(0xFFF7F0FF)],
    ),
    AppThemePreset(
      id: 1,
      nameAr: 'الغروب',
      nameEn: 'Sunset',
      seed: Color(0xFFFF6B35),
      auroraDark: [
        Color(0xFFFF6B35),
        Color(0xFFFF2E93),
        Color(0xFF7A2FFF),
        Color(0xFFFFC93C),
      ],
      auroraLight: [
        Color(0xFFFFB38A),
        Color(0xFFFF9ECF),
        Color(0xFFC9A8FF),
        Color(0xFFFFE08A),
      ],
      bgDark: [Color(0xFF1F0E1A), Color(0xFF120812)],
      bgLight: [Color(0xFFFFF0E6), Color(0xFFFFE6F2)],
    ),
    AppThemePreset(
      id: 2,
      nameAr: 'المحيط',
      nameEn: 'Ocean',
      seed: Color(0xFF00A8CC),
      auroraDark: [
        Color(0xFF00A8CC),
        Color(0xFF0066FF),
        Color(0xFF00E5A0),
        Color(0xFF4D7CFE),
      ],
      auroraLight: [
        Color(0xFF9FE6FF),
        Color(0xFF8FBEFF),
        Color(0xFFA8F0D1),
        Color(0xFFAEC6FF),
      ],
      bgDark: [Color(0xFF06202B), Color(0xFF04141C)],
      bgLight: [Color(0xFFE6F9FF), Color(0xFFE6F4FF)],
    ),
    AppThemePreset(
      id: 3,
      nameAr: 'الغابة',
      nameEn: 'Forest',
      seed: Color(0xFF22C55E),
      auroraDark: [
        Color(0xFF22C55E),
        Color(0xFF00B8A0),
        Color(0xFFA3E635),
        Color(0xFF0E9F6E),
      ],
      auroraLight: [
        Color(0xFFA8E6B8),
        Color(0xFF9FE8DC),
        Color(0xFFD9F99D),
        Color(0xFFA8DCC0),
      ],
      bgDark: [Color(0xFF0A1F14), Color(0xFF061209)],
      bgLight: [Color(0xFFEDFDF2), Color(0xFFF0FDF4)],
    ),
    AppThemePreset(
      id: 4,
      nameAr: 'الملكي',
      nameEn: 'Royal',
      seed: Color(0xFF8B5CF6),
      auroraDark: [
        Color(0xFF8B5CF6),
        Color(0xFFD4AF37),
        Color(0xFF5B21B6),
        Color(0xFFFF5CA8),
      ],
      auroraLight: [
        Color(0xFFC4B5FD),
        Color(0xFFF0D98C),
        Color(0xFFA78BFA),
        Color(0xFFFFB9DC),
      ],
      bgDark: [Color(0xFF160F2E), Color(0xFF0D0918)],
      bgLight: [Color(0xFFF3EDFF), Color(0xFFFFF8E6)],
    ),
    AppThemePreset(
      id: 5,
      nameAr: 'القرمزي',
      nameEn: 'Crimson',
      seed: Color(0xFFEF4444),
      auroraDark: [
        Color(0xFFEF4444),
        Color(0xFFFF2E93),
        Color(0xFFFF7A45),
        Color(0xFF991B1B),
      ],
      auroraLight: [
        Color(0xFFFFB3B3),
        Color(0xFFFF9ECF),
        Color(0xFFFFC9A8),
        Color(0xFFD68A8A),
      ],
      bgDark: [Color(0xFF220D0D), Color(0xFF140808)],
      bgLight: [Color(0xFFFFEEEE), Color(0xFFFFF0F0)],
    ),
    AppThemePreset(
      id: 6,
      nameAr: 'منتصف الليل',
      nameEn: 'Midnight',
      seed: Color(0xFF3B82F6),
      auroraDark: [
        Color(0xFF1E40AF),
        Color(0xFF3B82F6),
        Color(0xFF64748B),
        Color(0xFF0EA5E9),
      ],
      auroraLight: [
        Color(0xFF93B8F5),
        Color(0xFFBFDBFE),
        Color(0xFFCBD5E1),
        Color(0xFF7DD3FC),
      ],
      bgDark: [Color(0xFF050914), Color(0xFF03060D)],
      bgLight: [Color(0xFFEFF4FB), Color(0xFFF1F5F9)],
    ),
    AppThemePreset(
      id: 7,
      nameAr: 'النعناع',
      nameEn: 'Mint',
      seed: Color(0xFF14B8A6),
      auroraDark: [
        Color(0xFF14B8A6),
        Color(0xFFA3E635),
        Color(0xFF00E5A0),
        Color(0xFF38E1FF),
      ],
      auroraLight: [
        Color(0xFF9FE8DC),
        Color(0xFFD9F99D),
        Color(0xFFA8F0D1),
        Color(0xFFB3ECFF),
      ],
      bgDark: [Color(0xFF06201D), Color(0xFF041310)],
      bgLight: [Color(0xFFE6FBF7), Color(0xFFF2FDE8)],
    ),
    AppThemePreset(
      id: 8,
      nameAr: 'الخوخي',
      nameEn: 'Peach',
      seed: Color(0xFFFF8A5C),
      auroraDark: [
        Color(0xFFFF8A5C),
        Color(0xFFFF5CA8),
        Color(0xFFFFC93C),
        Color(0xFFB45309),
      ],
      auroraLight: [
        Color(0xFFFFD3B8),
        Color(0xFFFFB9DC),
        Color(0xFFFFE08A),
        Color(0xFFE8B98A),
      ],
      bgDark: [Color(0xFF221206), Color(0xFF140C04)],
      bgLight: [Color(0xFFFFF4EA), Color(0xFFFFF9F0)],
    ),
    AppThemePreset(
      id: 9,
      nameAr: 'الذهبي',
      nameEn: 'Golden',
      seed: Color(0xFFF59E0B),
      auroraDark: [
        Color(0xFFF59E0B),
        Color(0xFFD4AF37),
        Color(0xFFFF6B35),
        Color(0xFF92400E),
      ],
      auroraLight: [
        Color(0xFFFFD98A),
        Color(0xFFF0D98C),
        Color(0xFFFFB38A),
        Color(0xFFE8B98A),
      ],
      bgDark: [Color(0xFF201503), Color(0xFF120D02)],
      bgLight: [Color(0xFFFFF8E6), Color(0xFFFFF4E0)],
    ),
  ];
}

/// Premium Material 3 themes: midnight-navy dark and clean light,
/// recolored by the selected [AppThemePreset].
class AppTheme {
  static ThemeData dark([int presetId = 0]) {
    final preset = AppThemePreset.of(presetId);
    final scheme = ColorScheme.fromSeed(
      seedColor: preset.seed,
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
          borderSide: BorderSide(color: preset.seed, width: 1.6),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? const Color(0xFF0EA5E9)
                : null),
      ),
      textTheme: _textTheme(Brightness.dark),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData light([int presetId = 0]) {
    final preset = AppThemePreset.of(presetId);
    final scheme = ColorScheme.fromSeed(
      seedColor: preset.seed,
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
          borderSide: BorderSide(color: preset.seed, width: 1.6),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? const Color(0xFF0EA5E9)
                : null),
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
    // Cairo: the app's Arabic-first typeface (variable font, full weights).
    const family = 'Cairo';
    return const TextTheme(
      displayLarge: TextStyle(fontFamily: family, fontWeight: FontWeight.w800),
      displayMedium: TextStyle(fontFamily: family, fontWeight: FontWeight.w800),
      headlineSmall: TextStyle(fontFamily: family, fontWeight: FontWeight.w800),
      headlineMedium: TextStyle(fontFamily: family, fontWeight: FontWeight.w800),
      titleLarge: TextStyle(fontFamily: family, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontFamily: family, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(fontFamily: family, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontFamily: family),
      bodyMedium: TextStyle(fontFamily: family),
      bodySmall: TextStyle(fontFamily: family),
      labelLarge: TextStyle(fontFamily: family, fontWeight: FontWeight.w700),
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
