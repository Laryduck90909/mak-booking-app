import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class MakColors {
  static const teal = Color(0xFF0B3B3A);
  static const tealLight = Color(0xFF155B57);
  static const peach = Color(0xFFFFCCBF);
  static const background = Color(0xFF071F1F);
  static const surface = Color(0xFF102F2E);
  static const surfaceHigh = Color(0xFF173C3A);
  static const text = Color(0xFFFFF8F5);
  static const muted = Color(0xFFA9C3BF);
  static const success = Color(0xFF71D7AE);
  static const danger = Color(0xFFFF8E83);
}

abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.cairoTextTheme(base.textTheme).apply(
      bodyColor: MakColors.text,
      displayColor: MakColors.text,
    );
    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: MakColors.peach,
        onPrimary: MakColors.background,
        secondary: MakColors.tealLight,
        onSecondary: MakColors.text,
        surface: MakColors.surface,
        onSurface: MakColors.text,
        error: MakColors.danger,
      ),
      scaffoldBackgroundColor: MakColors.background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: MakColors.background,
        foregroundColor: MakColors.text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.cairo(
          color: MakColors.text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardTheme(
        color: MakColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF214946)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MakColors.surface,
        hintStyle: const TextStyle(color: MakColors.muted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF28514E)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF28514E)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: MakColors.peach, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          side: const BorderSide(color: MakColors.tealLight),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: MakColors.surfaceHigh,
        selectedColor: MakColors.peach,
        labelStyle: const TextStyle(color: MakColors.text),
        secondaryLabelStyle: const TextStyle(color: MakColors.background),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: MakColors.surface,
        indicatorColor: MakColors.tealLight,
        height: 72,
      ),
      dividerColor: const Color(0xFF28514E),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: MakColors.surfaceHigh,
        contentTextStyle: GoogleFonts.cairo(color: MakColors.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
