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
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 2,
        shadowColor: cardShadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textTheme: const TextTheme(
        headline6: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        subtitle1: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        bodyText2: TextStyle(fontSize: 14),
      ),
    );
  }
}
