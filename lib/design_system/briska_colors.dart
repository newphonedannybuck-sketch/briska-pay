import 'package:flutter/material.dart';

/// Briska's brand green, with accessible action and surface tones for each theme.
abstract final class BriskaColors {
  static const primary = Color(0xFF16764F);
  static const secondary = Color(0xFF1B8F5A);
  static const darkPrimary = Color(0xFF78DBAD);
  static const onDarkPrimary = Color(0xFF073823);
  static const hero = Color(0xFF115B40);
  static const dark = Color(0xFF121B18);
  static const accent = secondary;
  static const background = dark;
  static const lightBackground = Color(0xFFF4F6F3);
  static const text = Color(0xFFEDF3EE);
  static const secondaryText = Color(0xFFB2C1B8);
  static const surface = Color(0xFF1B2721);
  static const elevatedSurface = Color(0xFF26352D);
  static const lightSurface = lightBackground;
  static const lightText = Color(0xFF182D23);
  static const lightSecondaryText = Color(0xFF56685D);
  static const border = Color(0xFFDCE4DD);
  static const darkBorder = Color(0xFF3B4D42);
  static const danger = Color(0xFFB62D40);
  static const darkDanger = Color(0xFFFFB3BA);
  static const warning = Color(0xFF96620B);
  static const calendarHoliday = Color(0xFF6268AB);
  static const calendarSickDay = Color(0xFFA04C66);
  static const calendarEmpty = border;
  static const successTint = Color(0xFFE2F2E8);
  static const darkSuccessTint = Color(0xFF233F31);

  static const green = primary;
  static const greenDark = dark;
  static const mint = lightSurface;
  static const mintStrong = successTint;
  static const charcoal = lightText;
  static const muted = secondaryText;
}
