import 'package:flutter/material.dart';

abstract final class BriskaTypography {
  static const family = 'Poppins';

  static TextTheme apply(TextTheme base, Color color) {
    final theme = base.apply(
      bodyColor: color,
      displayColor: color,
      fontFamily: family,
    );
    return theme.copyWith(
      displaySmall: theme.displaySmall?.copyWith(
        fontSize: 40,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        height: 1.08,
      ),
      headlineLarge: theme.headlineLarge?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      headlineMedium: theme.headlineMedium?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        height: 1.16,
      ),
      headlineSmall: theme.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleLarge: theme.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleMedium: theme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleSmall: theme.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      bodyLarge: theme.bodyLarge?.copyWith(fontSize: 15, height: 1.5),
      bodyMedium: theme.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
      bodySmall: theme.bodySmall?.copyWith(fontSize: 12, height: 1.4),
      labelLarge: theme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      labelSmall: theme.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}
