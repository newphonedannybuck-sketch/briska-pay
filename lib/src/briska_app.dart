
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'ads/ads_configuration.dart';
import 'ads/ads_consent_coordinator.dart';
import 'ads/briska_banner_ad.dart';
import 'ads/ads_service.dart';
import 'app_lock_service.dart';
import 'app_theme.dart';
import 'backup_service.dart';
import 'csv_export_service.dart';
import 'currency.dart';
import 'display_format.dart';
import 'excel_export_service.dart';
import 'export_formats.dart';
import 'local_storage.dart';
import 'models.dart';
import 'pdf_export_service.dart';
import 'pay_schedule.dart';
import 'release_info.dart';
import 'site_name_suggestions.dart';
import 'support_service.dart';
import 'work_calculator.dart';
import 'premium_home_screen.dart';
import '../design_system/briska_colors.dart';
import '../design_system/briska_cards.dart';
import '../design_system/briska_icons.dart';
import '../design_system/briska_radius.dart';
import '../design_system/briska_spacing.dart';
import '../design_system/briska_theme.dart';
import '../features/export/models/export_config.dart';
import '../features/export/services/export_filename_service.dart';

part 'screens/about_screen.dart';
part 'screens/legal_text_screen.dart';
part 'screens/support_screen.dart';
part 'screens/beta_checklist_screen.dart';
part 'screens/startup_recovery_screen.dart';
part 'screens/startup_initialization_screen.dart';
part 'screens/app_lock_initialization_error_screen.dart';
part 'screens/app_lock_screen.dart';
part 'screens/onboarding_screen.dart';
part 'screens/reports_screen.dart';
part 'screens/professional_reports_screen.dart';
part 'screens/entries_screen.dart';
part 'screens/monthly_calendar_section.dart';
part 'screens/export_screen.dart';
part 'screens/settings_screen.dart';
part 'screens/add_work_day_screen.dart';
part 'screens/legacy_home_screen.dart';
part 'widgets/work_entry_card.dart';
part 'widgets/shared_ui.dart';
part 'screens/briska_shell.dart';

String get _currencyPrefix => '${CurrencyFormatter.current.symbol}  ';
String _money(double value, [CurrencyConfig? currency]) =>
    CurrencyFormatter.format(value, currency);
String _currencyInputValue(double value) =>
    value == 0 ? '' : value.toStringAsFixed(2);

String _formatFileSize(int? bytes) {
  if (bytes == null) return 'Size unavailable';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

enum ExportFileAction { open, share, rename, print, delete }

String exportFileActionFailureMessage(ExportFileAction action) =>
    switch (action) {
      ExportFileAction.open => 'Could not open this export.',
      ExportFileAction.share => 'Could not share this export.',
      ExportFileAction.rename => 'Could not rename this export.',
      ExportFileAction.print => 'Could not print this export.',
      ExportFileAction.delete => 'Could not delete this export.',
    };

String exportCreationFailureMessage(Object error) =>
    error is FileSystemException
    ? 'The report was generated, but the file could not be saved.'
    : 'Could not generate the report.';

ThemeMode themeModeFromSettings(String value) {
  return switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.light,
  };
}

String themeModeToSettings(ThemeMode value) {
  return switch (value) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'light',
  };
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _fullMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
String _weekdayName(DateTime date) => _weekdayNames[date.weekday - 1];
String _payPeriodLabel(PayPeriodRange period) => period.periodLabel;
String _dateTimeLabel(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.day} ${_monthNames[date.month - 1]} ${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}

String _entryTitle(WorkEntry entry) => entry.siteName.isNotEmpty
    ? entry.siteName
    : entry.entryType == 'Holiday'
    ? 'Holiday'
    : entry.type == EntryType.bankHoliday
    ? 'Bank Holiday'
    : entry.entryType == 'UnpaidDayOff'
    ? 'Unpaid day off'
    : entry.entryType == 'SickDay'
    ? (entry.isPaidSickDay ? 'Paid Sick Day' : 'Unpaid Sick Day')
    : 'Untitled work day';
PayPeriodRange _currentWeekPeriod(DateTime date) {
  final today = DateTime(date.year, date.month, date.day);
  final start = today.subtract(Duration(days: today.weekday - 1));
  final end = start.add(const Duration(days: 6));
  return PayPeriodRange(
    start: start,
    end: end,
    payday: end,
    periodLabel: 'Current week',
  );
}

List<WorkEntry> _entriesInPeriod(
  Iterable<WorkEntry> entries,
  PayPeriodRange period,
) => entries.where((entry) => period.contains(entry.date)).toList();

enum AppLockInitializationState { loading, locked, unlocked, failed }

enum AdvertisingConsentGateState { waiting, checking, complete }

