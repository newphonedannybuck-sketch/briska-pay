import 'package:flutter/material.dart';

abstract final class BriskaColors {
  static const primary = Color(0xFF1B8F5A);
  static const secondary = Color(0xFF2E9D69);
  static const dark = Color(0xFF121417);
  static const accent = secondary;
  static const background = dark;
  static const lightBackground = Color(0xFFF7F8FA);
  static const text = Colors.white;
  static const secondaryText = Color(0xFFA7ADB6);
  static const surface = Color(0xFF1D2025);
  static const lightSurface = lightBackground;
  static const lightText = Color(0xFF1D1F23);
  static const lightSecondaryText = Color(0xFF69707A);
  static const border = Color(0xFFE7E8EB);
  static const danger = Colors.red;
  static const warning = Colors.orange;
  static const calendarHoliday = Color(0xFF6674D9);
  static const calendarSickDay = Color(0xFFB76778);
  static const calendarEmpty = border;
  static const successTint = Color(0xFFE4F5EC);

  static const green = primary;
  static const greenDark = dark;
  static const mint = lightSurface;
  static const mintStrong = successTint;
  static const charcoal = lightText;
  static const muted = secondaryText;
}
