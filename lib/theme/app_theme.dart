import 'package:flutter/material.dart';

/// تم اپلیکیشن (Material Design 3) برای پایان‌نامه
class AppTheme {
  // رنگ‌های اصلی طبق نیاز پژوهش
  static const Color primaryLight = Color(0xFF2196F3);
  static const Color primaryDark = Color(0xFF1976D2);

  static const Color greyLight = Color(0xFF757575);
  static const Color greyDark = Color(0xFFBDBDBD);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Vazir',
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryLight,
        brightness: Brightness.light,
        primary: primaryLight,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryLight,
        foregroundColor: Colors.white,
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Vazir',
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryDark,
        brightness: Brightness.dark,
        primary: primaryDark,
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryDark,
        foregroundColor: Colors.white,
      ),
    );
  }
}

