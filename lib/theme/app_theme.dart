import 'package:flutter/material.dart';

class AppTheme {
  // Brand luxury obsidian colors
  static const Color bg = Color(0xFF0A0B10);
  static const Color bgCard = Color(0xFF12131D);
  static const Color bgElevated = Color(0xFF181926);
  static const Color bgSurface = Color(0xFF1F2133);

  // Vibrant cyber accents
  static const Color neon = Color(0xFF00F5D4);
  static const Color cyan = Color(0xFF00E5FF);
  static const Color accent = Color(0xFF10B981);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color violetGlow = Color(0x668B5CF6);
  static const Color neonGlow = Color(0x5500F5D4);
  static const Color danger = Color(0xFFFF3366);

  // Text hierarchy
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Borders & Glass
  static const Color border = Color(0x22FFFFFF);
  static const Color borderHairline = Color(0x12FFFFFF);
  static const Color glassFill = Color(0x1AFFFFFF);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00F5D4), Color(0xFF00C8FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGlowGradient = LinearGradient(
    colors: [Color(0x3300F5D4), Color(0x1A8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF151624), Color(0xFF0F101A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF1E1B4B), Color(0xFF0D0E18)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: neon,
      colorScheme: const ColorScheme.dark(
        primary: neon,
        secondary: cyan,
        surface: bgCard,
        error: danger,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: textPrimary,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.3,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF0D0E16),
        selectedItemColor: neon,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 16,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: TextStyle(fontSize: 10.5),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: neon,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
        thumbColor: Colors.white,
        overlayColor: neon.withValues(alpha: 0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
        trackHeight: 3.5,
      ),
    );
  }
}
