import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'util.dart';

/// ألوان مأخوذة من لوحات التحكم الأصلية (admin: ذهبي، موظف/عميل: تركوازي).
class Palette {
  final bool dark;
  final Color bg, sidebar, surface, surfaceHi, elevated, border, borderSoft;
  final Color fg, text, muted, subtle, input;
  final Color accent, onAccent, gold, teal, blue, violet, amber, red, green;

  const Palette({
    required this.dark, required this.bg, required this.sidebar, required this.surface,
    required this.surfaceHi, required this.elevated, required this.border, required this.borderSoft,
    required this.fg, required this.text, required this.muted, required this.subtle, required this.input,
    required this.accent, required this.onAccent, required this.gold, required this.teal,
    required this.blue, required this.violet, required this.amber, required this.red, required this.green,
  });

  /// توهج الخلفية (من لوحات التحكم الأصلية): تركوازي أعلى اليسار وذهبي أعلى اليمين.
  Color get glow1 => (dark ? teal : accent).fade(dark ? 0.10 : 0.10);
  Color get glow2 => gold.fade(dark ? 0.09 : 0.10);

  /// ظل البطاقات (ناعم في الفاتح، عميق في الداكن).
  List<BoxShadow> get cardShadow => [
        BoxShadow(color: Color(dark ? 0x59000000 : 0x1F101828), blurRadius: dark ? 36 : 30, spreadRadius: -16, offset: const Offset(0, 14)),
      ];
  List<BoxShadow> get floatShadow => [
        BoxShadow(color: Color(dark ? 0x80000000 : 0x29101828), blurRadius: 50, spreadRadius: -14, offset: const Offset(0, 22)),
      ];

  /// role: admin | staff | client | brand (شاشة الدخول بهوية M.A.K)
  factory Palette.build({required bool dark, required String role}) {
    if (role == 'brand') {
      return const Palette(
        dark: true, bg: Color(0xFF0B3B3A), sidebar: Color(0xFF082E2D), surface: Color(0xFF104846),
        surfaceHi: Color(0xFF145552), elevated: Color(0xFF1B625F), border: Color(0xFF2A6B68),
        borderSoft: Color(0xFF1F5754), fg: Color(0xFFFFFFFF), text: Color(0xFFE6F1F0),
        muted: Color(0xFFA9C9C6), subtle: Color(0xFF86ADAA), input: Color(0xFF0A3231),
        accent: Color(0xFFFFCCBF), onAccent: Color(0xFF0B3B3A), gold: Color(0xFFFFCCBF),
        teal: Color(0xFF62BAAA), blue: Color(0xFF7B9DC4), violet: Color(0xFFA497CD),
        amber: Color(0xFFD4A46C), red: Color(0xFFE59A98), green: Color(0xFF70C5A2),
      );
    }
    if (role == 'client') {
      // لوحة العميل الأصلية (luxury-client-command-center)
      if (dark) {
        return const Palette(
          dark: true, bg: Color(0xFF0A0B0D), sidebar: Color(0xFF0E1013), surface: Color(0xFF121417),
          surfaceHi: Color(0xFF15181D), elevated: Color(0xFF1A1D21), border: Color(0x24FFFFFF),
          borderSoft: Color(0x14FFFFFF), fg: Color(0xFFF3F5F7), text: Color(0xFFD3D8DE),
          muted: Color(0xFFA3ABB6), subtle: Color(0xFF7B8492), input: Color(0xFF15181D),
          accent: Color(0xFF2DD4BF), onAccent: Color(0xFF04120F), gold: Color(0xFFF4B942), teal: Color(0xFF14B8A6),
          blue: Color(0xFF3B82F6), violet: Color(0xFFA78BFA), amber: Color(0xFFF59E0B), red: Color(0xFFEF4444),
          green: Color(0xFF22C55E),
        );
      }
      return const Palette(
        dark: false, bg: Color(0xFFF3F5F8), sidebar: Color(0xFFFFFFFF), surface: Color(0xFFFFFFFF),
        surfaceHi: Color(0xFFF7F9FB), elevated: Color(0xFFF1F4F8), border: Color(0x1F0A0B0D),
        borderSoft: Color(0x140A0B0D), fg: Color(0xFF0E1114), text: Color(0xFF2B323B),
        muted: Color(0xFF4A525D), subtle: Color(0xFF667080), input: Color(0xFFF7F9FB),
        accent: Color(0xFF0B6F66), onAccent: Color(0xFFFFFFFF), gold: Color(0xFF8A5A00), teal: Color(0xFF0F766E),
        blue: Color(0xFF2563EB), violet: Color(0xFF7C3AED), amber: Color(0xFFB45309), red: Color(0xFFB91C1C),
        green: Color(0xFF15803D),
      );
    }
    final accentDark = role == 'admin' ? const Color(0xFFD3B176) : (role == 'staff' ? const Color(0xFF25BBA4) : const Color(0xFF2DD4BF));
    final accentLight = role == 'admin' ? const Color(0xFF967038) : (role == 'staff' ? const Color(0xFF087A65) : const Color(0xFF0B6F66));
    if (dark) {
      return Palette(
        dark: true, bg: const Color(0xFF0C0E10), sidebar: const Color(0xFF101214), surface: const Color(0xFF151719),
        surfaceHi: const Color(0xFF191C1F), elevated: const Color(0xFF202326), border: const Color(0xFF2B2E31),
        borderSoft: const Color(0xFF24272A), fg: const Color(0xFFEFF0F1), text: const Color(0xFFC6C9CC),
        muted: const Color(0xFF91969C), subtle: const Color(0xFF747B83), input: const Color(0xFF121416),
        accent: accentDark, onAccent: const Color(0xFF101214), gold: const Color(0xFFD3B176),
        teal: const Color(0xFF62BAAA), blue: const Color(0xFF7B9DC4), violet: const Color(0xFFA497CD),
        amber: const Color(0xFFD4A46C), red: const Color(0xFFD48A89), green: const Color(0xFF70C5A2),
      );
    }
    return Palette(
      dark: false, bg: const Color(0xFFF1F2F0), sidebar: const Color(0xFFFAFBF9), surface: const Color(0xFFFFFFFF),
      surfaceHi: const Color(0xFFF5F6F3), elevated: const Color(0xFFE7E9E6), border: const Color(0xFFD4D9D6),
      borderSoft: const Color(0xFFE4E8E4), fg: const Color(0xFF202627), text: const Color(0xFF384443),
      muted: const Color(0xFF606D6F), subtle: const Color(0xFF727F7E), input: const Color(0xFFF7F8F5),
      accent: accentLight, onAccent: const Color(0xFFFFFFFF), gold: const Color(0xFF967038),
      teal: const Color(0xFF348574), blue: const Color(0xFF4B7698), violet: const Color(0xFF7D699B),
      amber: const Color(0xFF9C692D), red: const Color(0xFFA74E4E), green: const Color(0xFF2F8965),
    );
  }
}

class PalScope extends InheritedWidget {
  final Palette palette;
  final String lang;
  const PalScope({super.key, required this.palette, required this.lang, required super.child});

  static Palette of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<PalScope>();
    return s?.palette ?? Palette.build(dark: true, role: 'client');
  }

  @override
  bool updateShouldNotify(PalScope old) => old.palette != palette || old.lang != lang;
}

/// اختصار: final p = P(context);
Palette P(BuildContext context) => PalScope.of(context);

ThemeData buildTheme(Palette p) {
  final base = p.dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  final tt = GoogleFonts.cairoTextTheme(base.textTheme).apply(bodyColor: p.text, displayColor: p.fg);
  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.surface,
    dividerColor: p.border,
    textTheme: tt,
    primaryTextTheme: tt,
    colorScheme: ColorScheme(
      brightness: p.dark ? Brightness.dark : Brightness.light,
      primary: p.accent, onPrimary: p.onAccent, secondary: p.teal,
      onSecondary: p.onAccent, error: p.red, onError: Colors.white,
      surface: p.surface, onSurface: p.fg,
    ),
    appBarTheme: AppBarTheme(backgroundColor: p.sidebar, foregroundColor: p.fg, elevation: 0),
    textSelectionTheme: TextSelectionThemeData(cursorColor: p.accent),
  );
}

TextStyle ts(Palette p, {double size = 13, FontWeight w = FontWeight.w400, Color? color, double? height, bool display = false}) => TextStyle(
      fontSize: size, fontWeight: w, color: color ?? p.text, height: height,
      // العناوين والأرقام: Sora كما في اللوحات الأصلية، والعربي يرجع تلقائياً إلى Cairo.
      fontFamily: display ? GoogleFonts.sora().fontFamily : GoogleFonts.cairo().fontFamily,
      fontFamilyFallback: display ? [GoogleFonts.cairo().fontFamily!] : null,
    );
