import 'package:flutter/material.dart';

import '../design_system/briska_colors.dart';
import '../design_system/briska_theme.dart';

typedef AppColors = BriskaColors;

abstract final class AppTheme {
  static ThemeData get light => BriskaTheme.light;
  static ThemeData get dark => BriskaTheme.dark;
}
