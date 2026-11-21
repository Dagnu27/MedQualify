import 'package:flutter/material.dart';

enum AppThemeMode {
  clinical('Clinical Mint', 'Soft mint green, standard medical theme', Color(0xFFF7FAF8), Color(0xFF0B6B67)),
  clean('Pure Light', 'High-contrast bright white background', Color(0xFFF8FAFC), Color(0xFF0D9488)),
  warm('Warm Paper', 'Eye-comfort warm cream, reduced strain', Color(0xFFF9F6F0), Color(0xFFB45309)),
  dark('Night Slate', 'Deep charcoal dark mode for low light', Color(0xFF0D1716), Color(0xFF2DD4BF));

  const AppThemeMode(this.label, this.description, this.bgPreview, this.accentPreview);
  final String label;
  final String description;
  final Color bgPreview;
  final Color accentPreview;
}

class AppColors {
  static const ink = Color(0xFF173533);
  static const inkSoft = Color(0xFF5F7270);
  static const muted = Color(0xFF91A09D);
  static const line = Color(0xFFDDE6E2);
  static const lineStrong = Color(0xFFCDDBD5);
  static const paper = Color(0xFFF7FAF8);
  static const card = Color(0xFFFFFFFF);
  static const deep = Color(0xFF143C3A);
  static const teal = Color(0xFF0B6B67);
  static const mint = Color(0xFFDFF1E7);
  static const aqua = Color(0xFFCCECE7);
  static const gold = Color(0xFFF1D88A);
  static const goldInk = Color(0xFF786126);
  static const plum = Color(0xFFE6D9EF);
  static const coral = Color(0xFFF4D6CA);
  static const blue = Color(0xFFDCEAF6);
  static const green = Color(0xFF43845B);
  static const red = Color(0xFFB2604E);
  static const sidebarText = Color(0xFFA9C2BA);
  static const sidebarActive = Color(0xFF285956);
}

class AppTheme {
  static ThemeData getTheme(AppThemeMode mode) {
    final bool isDark = mode == AppThemeMode.dark;

    final Color scaffoldBg = switch (mode) {
      AppThemeMode.clinical => const Color(0xFFF7FAF8),
      AppThemeMode.clean => const Color(0xFFF8FAFC),
      AppThemeMode.warm => const Color(0xFFF9F6F0),
      AppThemeMode.dark => const Color(0xFF0D1716),
    };

    final Color cardBg = switch (mode) {
      AppThemeMode.clinical => const Color(0xFFFFFFFF),
      AppThemeMode.clean => const Color(0xFFFFFFFF),
      AppThemeMode.warm => const Color(0xFFFFFDF9),
      AppThemeMode.dark => const Color(0xFF142422),
    };

    final Color primaryColor = switch (mode) {
      AppThemeMode.clinical => AppColors.teal,
      AppThemeMode.clean => const Color(0xFF0D9488),
      AppThemeMode.warm => const Color(0xFFB45309),
      AppThemeMode.dark => const Color(0xFF2DD4BF),
    };

    final Color onSurfaceText = switch (mode) {
      AppThemeMode.dark => const Color(0xFFF0FDF4),
      AppThemeMode.warm => const Color(0xFF292524),
      _ => AppColors.ink,
    };

    final Color borderColor = switch (mode) {
      AppThemeMode.dark => const Color(0xFF1F3835),
      AppThemeMode.warm => const Color(0xFFE8E0D2),
      _ => AppColors.line,
    };

    final scheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: primaryColor,
      onPrimary: isDark ? const Color(0xFF0D1716) : Colors.white,
      secondary: isDark ? const Color(0xFF1E3D39) : AppColors.mint,
      onSecondary: isDark ? Colors.white : AppColors.deep,
      surface: cardBg,
      onSurface: onSurfaceText,
      error: AppColors.red,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      cardColor: cardBg,
      dividerColor: borderColor,
      fontFamily: 'Segoe UI',
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg.withValues(alpha: 0.95),
        foregroundColor: onSurfaceText,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF0F1E1C) : const Color(0xFFFBFDFB),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: primaryColor, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: isDark ? const Color(0xFF0D1716) : Colors.white,
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }

  static ThemeData get data => getTheme(AppThemeMode.clinical);
}

class TemplateAccent {
  const TemplateAccent(this.background, this.foreground);
  final Color background;
  final Color foreground;
}

const templateAccents = [
  TemplateAccent(AppColors.aqua, Color(0xFF287A72)),
  TemplateAccent(Color(0xFFF6E7B7), Color(0xFF8C6B25)),
  TemplateAccent(AppColors.plum, Color(0xFF79568B)),
  TemplateAccent(AppColors.blue, Color(0xFF456F95)),
  TemplateAccent(AppColors.coral, Color(0xFFA55E4C)),
  TemplateAccent(AppColors.mint, Color(0xFF3C7D5C)),
  TemplateAccent(Color(0xFFDEDFF5), Color(0xFF5D5D9B)),
];

const templateMarks = ['CP', 'DS', '4P', 'MC', 'PT', 'PC', 'OP'];
