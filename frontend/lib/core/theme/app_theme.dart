import 'package:flutter/material.dart';

class AppTheme {
  // Brand colors - Midnight Navy & Executive Gold (KuhuGrantha Identity)
  static const Color primaryDark = Color(0xFF060A12); // Deep Obsidian
  static const Color primaryNavy = Color(0xFF0F172A); // Slate 900
  static const Color sidebarBackground = Color(0xFF080D1A); // Premium Midnight Dark
  static const Color primaryBlue = Color(0xFF3B82F6); // Vibrant Electric Blue
  static const Color accentIndigo = Color(0xFF6366F1); // Indigo 500
  static const Color accentGold = Color(0xFFF59E0B); // KuhuGrantha Brand Gold
  static const Color accentAmber = Color(0xFFFBBF24); // Amber 400
  static const Color accentCyan = Color(0xFF38BDF8); // Sky 400

  // Modern Dark / Slate Backgrounds
  static const Color scaffoldBackground = Color(0xFF0A0F1D); // Deep Slate Canvas
  static const Color cardBackground = Color(0xFF131D31); // Elevated Modern Slate Card
  static const Color surfaceElevated = Color(0xFF1A2640); // Inner Elevated Surface
  static const Color surfaceInput = Color(0xFF0D1526); // Dark Input Field Canvas

  // Typography Colors for Dark Theme
  static const Color textPrimary = Color(0xFFF8FAFC); // Slate 50 - High contrast crisp white
  static const Color textSecondary = Color(0xFF94A3B8); // Slate 400 - Clean secondary text
  static const Color textMuted = Color(0xFF64748B); // Slate 500 - Muted captions & hints
  static const Color borderColor = Color(0xFF1E293B); // Slate 800 - Subtle card border
  static const Color borderHover = Color(0xFF38BDF8); // Cyan highlight on hover

  // Status indicators with rich modern accents
  static const Color success = Color(0xFF10B981); // Emerald 500
  static const Color successLight = Color(0xFF064E3B); // Emerald 900 / dark tint
  static const Color warning = Color(0xFFF59E0B); // Amber 500
  static const Color warningLight = Color(0xFF78350F); // Amber 900 / dark tint
  static const Color danger = Color(0xFFEF4444); // Red 500
  static const Color dangerLight = Color(0xFF7F1D1D); // Red 900 / dark tint
  static const Color info = Color(0xFF0EA5E9); // Sky 500
  static const Color infoLight = Color(0xFF0C4A6E); // Sky 900 / dark tint

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primaryBlue,
        secondary: accentGold,
        surface: cardBackground,
        background: scaffoldBackground,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onBackground: textPrimary,
      ),
      scaffoldBackgroundColor: scaffoldBackground,
      fontFamily: 'Segoe UI',
      cardTheme: CardTheme(
        color: cardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderColor, width: 1.2),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D1526),
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 3,
          shadowColor: primaryBlue.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accentCyan,
          side: const BorderSide(color: Color(0xFF2E4062), width: 1.2),
          backgroundColor: const Color(0xFF131D31).withOpacity(0.6),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceInput,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: textMuted, fontSize: 13),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF24324D)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF24324D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentCyan, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cardBackground,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF24324D)),
        ),
        insetPadding: const EdgeInsets.all(18),
        elevation: 10,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: const Color(0xFF111A2E),
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF24324D), width: 1.2),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          color: textSecondary,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 11.5),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const MaterialStatePropertyAll(8),
        radius: const Radius.circular(8),
        thumbColor: const MaterialStatePropertyAll(Color(0x66475569)),
        crossAxisMargin: 2,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF131D31),
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF24324D)),
        ),
        textStyle: const TextStyle(color: textPrimary, fontSize: 13),
      ),
      dividerTheme: const DividerThemeData(
        color: borderColor,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
