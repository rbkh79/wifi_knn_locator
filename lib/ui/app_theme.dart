import 'package:flutter/material.dart';
import '../config.dart';

class AppTheme {
  static const Color primary = Color(0xFF1A73E8);
  static const Color secondary = Color(0xFF34A853);
  static const Color background = Color(0xFFF8F9FA);
  static const Color cardShadow = Color(0x10000000);

  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: secondary,
        background: background,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      // keep card theme default (avoid SDK mismatches)
      fontFamily: 'Vazir',
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        bodyMedium: TextStyle(fontSize: 14),
        labelSmall: TextStyle(fontSize: 12),
      ),
    );
  }

   static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1976D2),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1976D2),
        foregroundColor: Colors.white,
      ),
      fontFamily: 'Vazir',
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        bodyMedium: TextStyle(fontSize: 14),
        labelSmall: TextStyle(fontSize: 12),
      ),
    );
  }
}
