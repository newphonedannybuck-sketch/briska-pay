import 'package:flutter/material.dart';

import 'briska_colors.dart';
import 'briska_radius.dart';
import 'briska_spacing.dart';
import 'briska_typography.dart';

abstract final class BriskaDurations {
  static const quick = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 200);
  static const emphasis = Duration(milliseconds: 200);
}

abstract final class BriskaShadows {
  static List<BoxShadow> card(bool isDark) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? .22 : .08),
      blurRadius: isDark ? 18 : 26,
      offset: const Offset(0, 14),
    ),
  ];
}

abstract final class BriskaTheme {
  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final colors =
        ColorScheme.fromSeed(
          seedColor: BriskaColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: BriskaColors.primary,
          onPrimary: Colors.white,
          secondary: BriskaColors.accent,
          surface: isDark ? BriskaColors.surface : Colors.white,
          onSurface: isDark ? BriskaColors.text : BriskaColors.lightText,
          onSurfaceVariant: isDark
              ? BriskaColors.secondaryText
              : BriskaColors.lightSecondaryText,
          error: BriskaColors.danger,
        );

    final textTheme = BriskaTypography.apply(base.textTheme, colors.onSurface);
    final radius = BorderRadius.circular(BriskaRadii.lg);

    return base.copyWith(
      colorScheme: colors,
      scaffoldBackgroundColor: isDark
          ? BriskaColors.background
          : BriskaColors.lightSurface,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: isDark ? 0 : 1.5,
        shadowColor: Colors.black.withValues(alpha: isDark ? .3 : .1),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BriskaRadii.xl),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: .075)
                : BriskaColors.border.withValues(alpha: .45),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: colors.onSurface, size: 24),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: .055) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: BriskaSpacing.lg,
          vertical: BriskaSpacing.md,
        ),
        labelStyle: TextStyle(color: colors.onSurfaceVariant),
        hintStyle: TextStyle(color: colors.onSurfaceVariant),
        helperStyle: TextStyle(color: colors.onSurfaceVariant),
        border: _inputBorder(isDark),
        enabledBorder: _inputBorder(isDark),
        focusedBorder: _inputBorder(isDark, focused: true),
        errorBorder: _inputBorder(isDark, error: true),
        focusedErrorBorder: _inputBorder(isDark, focused: true, error: true),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.onSurface.withValues(alpha: .12),
          disabledForegroundColor: colors.onSurface.withValues(alpha: .38),
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.onSurface.withValues(alpha: .12),
          disabledForegroundColor: colors.onSurface.withValues(alpha: .38),
          elevation: 0,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          minimumSize: const Size(0, 52),
          side: BorderSide(color: colors.primary.withValues(alpha: .42)),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BriskaRadii.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BriskaRadii.md),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BriskaRadii.xl),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? colors.primary.withValues(alpha: .7)
                  : colors.onSurface.withValues(alpha: .26),
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radius),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colors.primary.withValues(alpha: .07),
        selectedColor: colors.primary.withValues(alpha: .14),
        disabledColor: colors.onSurface.withValues(alpha: .06),
        side: BorderSide(color: colors.primary.withValues(alpha: .16)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        labelStyle: textTheme.labelLarge,
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: colors.primary,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white12 : BriskaColors.border,
        thickness: 1,
        space: BriskaSpacing.md,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: BriskaSpacing.md,
          vertical: BriskaSpacing.xxs,
        ),
        minTileHeight: 56,
        iconColor: colors.primary,
        titleTextStyle: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BriskaRadii.lg),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium,
        inputDecorationTheme: const InputDecorationTheme(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? Colors.white : BriskaColors.dark,
        contentTextStyle: TextStyle(
          color: isDark ? BriskaColors.dark : Colors.white,
          fontFamily: BriskaTypography.family,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BriskaRadii.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BriskaRadii.xl),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: colors.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(BriskaRadii.xl),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.primary.withValues(alpha: .14),
      ),
      iconTheme: IconThemeData(color: colors.onSurfaceVariant, size: 22),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: colors.primary.withValues(alpha: isDark ? .18 : .12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          ),
        ),
      ),
      dividerColor: isDark ? Colors.white12 : BriskaColors.border,
      visualDensity: VisualDensity.standard,
    );
  }

  static OutlineInputBorder _inputBorder(
    bool isDark, {
    bool focused = false,
    bool error = false,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(BriskaRadii.lg),
      borderSide: BorderSide(
        color: error
            ? BriskaColors.danger
            : focused
            ? BriskaColors.primary
            : (isDark ? Colors.white24 : BriskaColors.border),
        width: focused ? 1.5 : 1,
      ),
    );
  }
}
