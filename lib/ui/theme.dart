import 'package:flutter/material.dart';

abstract final class NotebookColors {
  static const teal = Color(0xFF075F59);
  static const ivory = Color(0xFFFAF8F2);
  static const ink = Color(0xFF172B28);
  static const muted = Color(0xFF596B66);
  static const soft = Color(0xFFE6F1ED);
  static const border = Color(0xFFDCE5DF);
  static const gold = Color(0xFF927027);
}

ThemeData notebookTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Vazirmatn',
  scaffoldBackgroundColor: NotebookColors.ivory,
  colorScheme: ColorScheme.fromSeed(
    seedColor: NotebookColors.teal,
    primary: NotebookColors.teal,
    surface: Colors.white,
  ),
  textTheme: const TextTheme(
    headlineSmall: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      height: 1.6,
      color: NotebookColors.ink,
    ),
    titleLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      height: 1.6,
      color: NotebookColors.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w500,
      height: 1.6,
      color: NotebookColors.ink,
    ),
    bodyLarge: TextStyle(fontSize: 20, height: 1.7, color: NotebookColors.ink),
    bodyMedium: TextStyle(
      fontSize: 18,
      height: 1.7,
      color: NotebookColors.muted,
    ),
    labelLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: NotebookColors.ivory,
    foregroundColor: NotebookColors.ink,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontFamily: 'Vazirmatn',
      fontSize: 26,
      fontWeight: FontWeight.bold,
      color: NotebookColors.ink,
    ),
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: NotebookColors.border),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(64),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      textStyle: const TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 22,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(20),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: const BorderSide(color: NotebookColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: const BorderSide(color: NotebookColors.border),
    ),
  ),
);

String faDigits(Object value) => value.toString().split('').map((c) {
  final digit = int.tryParse(c);
  return digit == null ? c : '۰۱۲۳۴۵۶۷۸۹'[digit];
}).join();

String relativeDate(DateTime time) {
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(time.year, time.month, time.day)).inDays;
  if (days <= 0) {
    return 'امروز';
  }
  if (days == 1) {
    return 'دیروز';
  }
  return '${faDigits(days)} روز پیش';
}
