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
      color: Colors.black.withValues(alpha: isDark ? .12 : .04),
      blurRadius: 10,
      offset: const Offset(0, 3),
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
          primary: isDark ? BriskaColors.darkPrimary : BriskaColors.primary,
          onPrimary: isDark ? BriskaColors.onDarkPrimary : Colors.white,
          secondary: isDark ? BriskaColors.darkPrimary : BriskaColors.accent,
          primaryContainer: isDark
              ? BriskaColors.darkSuccessTint
              : BriskaColors.successTint,
          onPrimaryContainer: isDark
              ? BriskaColors.darkPrimary
              : BriskaColors.hero,
          surfaceContainerHighest: isDark
              ? BriskaColors.elevatedSurface
              : const Color(0xFFEBF0EA),
          surfaceContainerLow: isDark ? BriskaColors.surface : Colors.white,
          outline: isDark ? BriskaColors.darkBorder : const Color(0xFF809386),
          outlineVariant: isDark
              ? BriskaColors.darkBorder
              : BriskaColors.border,
          surface: isDark ? BriskaColors.surface : Colors.white,
          onSurface: isDark ? BriskaColors.text : BriskaColors.lightText,
          onSurfaceVariant: isDark
              ? BriskaColors.secondaryText
              : BriskaColors.lightSecondaryText,
          error: isDark ? BriskaColors.darkDanger : BriskaColors.danger,
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
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: isDark ? .3 : .1),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BriskaRadii.xl),
          side: BorderSide(color: colors.outlineVariant),
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
        fillColor: isDark ? BriskaColors.dark : const Color(0xFFF7F9F6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: BriskaSpacing.md,
          vertical: BriskaSpacing.md,
        ),
        labelStyle: TextStyle(
          fontFamily: BriskaTypography.family,
          color: colors.onSurfaceVariant,
        ),
        hintStyle: TextStyle(
          fontFamily: BriskaTypography.family,
          color: colors.onSurfaceVariant,
        ),
        helperStyle: TextStyle(
          fontFamily: BriskaTypography.family,
          color: colors.onSurfaceVariant,
          fontSize: 12,
        ),
        helperMaxLines: 3,
        errorMaxLines: 3,
        border: _inputBorder(colors),
        enabledBorder: _inputBorder(colors),
        focusedBorder: _inputBorder(colors, focused: true),
        errorBorder: _inputBorder(colors, error: true),
        focusedErrorBorder: _inputBorder(colors, focused: true, error: true),
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
          textStyle: const TextStyle(
            fontFamily: BriskaTypography.family,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
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
          textStyle: const TextStyle(
            fontFamily: BriskaTypography.family,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          minimumSize: const Size(0, 52),
          side: BorderSide(color: colors.primary.withValues(alpha: .42)),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(
            fontFamily: BriskaTypography.family,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BriskaRadii.md),
          ),
          textStyle: const TextStyle(
            fontFamily: BriskaTypography.family,
            fontWeight: FontWeight.w700,
          ),
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
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BriskaRadii.xl),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: BriskaTypography.family,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
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
        backgroundColor: colors.surface,
        selectedColor: colors.primaryContainer,
        disabledColor: colors.onSurface.withValues(alpha: .06),
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BriskaRadii.md),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        labelStyle: textTheme.labelLarge,
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: colors.primary,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
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
      datePickerTheme: DatePickerThemeData(
        backgroundColor: colors.surface,
        headerBackgroundColor: colors.primaryContainer,
        headerForegroundColor: colors.onPrimaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: colors.primary,
        collapsedIconColor: colors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
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
          fontFamily: BriskaTypography.family,
          color: isDark ? BriskaColors.dark : Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BriskaRadii.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: .16),
        backgroundColor: Color.lerp(colors.surface, colors.primary, .025),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BriskaRadii.xl),
          side: BorderSide(color: colors.outlineVariant),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Color.lerp(colors.surface, colors.primary, .025),
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
        height: 72,
        indicatorColor: colors.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: BriskaTypography.family,
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
      dividerColor: colors.outlineVariant,
      visualDensity: VisualDensity.standard,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.primary,
        selectionColor: colors.primary.withValues(alpha: .22),
        selectionHandleColor: colors.primary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? colors.onPrimary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? colors.primary : null,
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(
    ColorScheme colors, {
    bool focused = false,
    bool error = false,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(BriskaRadii.md),
      borderSide: BorderSide(
        color: error
            ? colors.error
            : focused
            ? colors.primary
            : colors.outlineVariant,
        width: focused ? 2 : 1,
      ),
    );
  }
}
