import 'package:flutter/material.dart';

/// Shared visual treatment for form groups, financial summaries and utilities.
abstract final class BriskaSurfaces {
  static BoxDecoration panel(
    BuildContext context, {
    Color? tint,
    bool prominent = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = tint ?? colors.primary;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: prominent || tint != null
            ? accent.withValues(alpha: .25)
            : colors.outlineVariant,
      ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(colors.surface, accent, prominent ? .09 : .015)!,
          Color.lerp(colors.surface, accent, prominent ? .16 : .045)!,
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? .12 : .035),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  static Color dayType(BuildContext context, String type) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (type) {
      'Holiday' => dark ? const Color(0xFFCFB1FF) : const Color(0xFF7948AA),
      'bankHoliday' ||
      'BankHoliday' => dark ? const Color(0xFFFFD28A) : const Color(0xFF996008),
      'SickDay' => dark ? const Color(0xFFFFB1CD) : const Color(0xFFA04C66),
      _ => Theme.of(context).colorScheme.primary,
    };
  }
}
