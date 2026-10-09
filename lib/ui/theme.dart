import 'package:flutter/material.dart';

import '../domain/jalali_date.dart';

abstract final class NotebookColors {
  static const teal = Color(0xFF075F59);
  static const ivory = Color(0xFFFAF8F2);
  static const ink = Color(0xFF172B28);
  static const muted = Color(0xFF596B66);
  static const soft = Color(0xFFE6F1ED);
  static const border = Color(0xFFDCE5DF);
  static const gold = Color(0xFF927027);
}

abstract final class NotebookTypeScale {
  static const small = 16.0;
  static const body = 20.0;
  static const title = 24.0;
  static const display = 28.0;
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
    displayLarge: TextStyle(
      fontSize: NotebookTypeScale.display,
      fontWeight: FontWeight.bold,
      height: 1.6,
      color: NotebookColors.ink,
    ),
    displayMedium: TextStyle(
      fontSize: NotebookTypeScale.display,
      fontWeight: FontWeight.bold,
      height: 1.6,
      color: NotebookColors.ink,
    ),
    displaySmall: TextStyle(
      fontSize: NotebookTypeScale.title,
      fontWeight: FontWeight.bold,
      height: 1.6,
      color: NotebookColors.ink,
    ),
    headlineLarge: TextStyle(
      fontSize: NotebookTypeScale.display,
      fontWeight: FontWeight.bold,
      height: 1.6,
      color: NotebookColors.ink,
    ),
    headlineMedium: TextStyle(
      fontSize: NotebookTypeScale.title,
      fontWeight: FontWeight.bold,
      height: 1.6,
      color: NotebookColors.ink,
    ),
    headlineSmall: TextStyle(
      fontSize: NotebookTypeScale.display,
      fontWeight: FontWeight.bold,
      height: 1.6,
      color: NotebookColors.ink,
    ),
    titleLarge: TextStyle(
      fontSize: NotebookTypeScale.title,
      fontWeight: FontWeight.bold,
      height: 1.6,
      color: NotebookColors.ink,
    ),
    titleMedium: TextStyle(
      fontSize: NotebookTypeScale.body,
      fontWeight: FontWeight.w500,
      height: 1.6,
      color: NotebookColors.ink,
    ),
    titleSmall: TextStyle(
      fontSize: NotebookTypeScale.body,
      fontWeight: FontWeight.w500,
      height: 1.6,
      color: NotebookColors.ink,
    ),
    bodyLarge: TextStyle(
      fontSize: NotebookTypeScale.body,
      height: 1.7,
      color: NotebookColors.ink,
    ),
    bodyMedium: TextStyle(
      fontSize: NotebookTypeScale.small,
      height: 1.7,
      color: NotebookColors.muted,
    ),
    bodySmall: TextStyle(
      fontSize: NotebookTypeScale.small,
      height: 1.7,
      color: NotebookColors.muted,
    ),
    labelLarge: TextStyle(
      fontSize: NotebookTypeScale.body,
      fontWeight: FontWeight.w500,
    ),
    labelMedium: TextStyle(
      fontSize: NotebookTypeScale.small,
      fontWeight: FontWeight.w500,
    ),
    labelSmall: TextStyle(
      fontSize: NotebookTypeScale.small,
      fontWeight: FontWeight.w500,
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: NotebookColors.ivory,
    foregroundColor: NotebookColors.ink,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontFamily: 'Vazirmatn',
      fontSize: NotebookTypeScale.title,
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
        fontSize: NotebookTypeScale.body,
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

String relativeDate(
  DateTime time, {
  JalaliDateService service = const ShamsiDateService(),
}) {
  return service.relativeDate(time);
}
