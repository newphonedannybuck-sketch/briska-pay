import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'work_calculator.dart';

const briskaBackupVersion = 1;
const _legacyBackupAppName =
    'Wage'
    'Mate';

class BriskaBackupData {
  const BriskaBackupData({
    required this.createdAt,
    required this.settings,
    required this.workEntries,
    required this.exportRecords,
  });

  final DateTime createdAt;
  final AppSettings settings;
  final List<WorkEntry> workEntries;
  final List<ExportedFileRecord> exportRecords;

  Map<String, Object?> toJson() => {
    'backupVersion': briskaBackupVersion,
    'createdAt': createdAt.toIso8601String(),
    'appName': 'Briska',
    'settings': settings.toJson(),
    'workEntries': workEntries.map((entry) => entry.toJson()).toList(),
    'exportRecords': exportRecords.map((record) => record.toJson()).toList(),
  };
}

class BriskaBackupPreview {
  const BriskaBackupPreview({
    required this.createdAt,
    required this.userName,
    required this.companyName,
    required this.entryCount,
    required this.exportCount,
    required this.data,
  });

  final DateTime createdAt;
  final String userName;
  final String companyName;
  final int entryCount;
  final int exportCount;
  final BriskaBackupData data;
}

class BriskaBackupException implements Exception {
  const BriskaBackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract final class BriskaBackupService {
  static const _invalidBackupMessage =
      'This backup could not be restored.\n\n'
      'The backup file is damaged, incomplete, or not supported by this '
      'version of Briska Pay.';

  static String backupFileName(DateTime createdAt) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'Briska_Backup_${createdAt.year}-${two(createdAt.month)}-${two(createdAt.day)}_'
        '${two(createdAt.hour)}${two(createdAt.minute)}.json';
  }

  static Future<File> createBackupFile({
    required AppSettings settings,
    required List<WorkEntry> workEntries,
    required List<ExportedFileRecord> exportRecords,
    DateTime? createdAt,
  }) async {
    final now = createdAt ?? DateTime.now();
    final directory = await getApplicationDocumentsDirectory();
    final backupDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}backups',
    );
    await backupDirectory.create(recursive: true);
    final file = File(
      '${backupDirectory.path}${Platform.pathSeparator}${backupFileName(now)}',
    );
    final data = BriskaBackupData(
      createdAt: now,
      settings: settings,
      workEntries: workEntries.map(WorkCalculator.recalculateEntry).toList(),
      exportRecords: exportRecords,
    );
    const encoder = JsonEncoder.withIndent('  ');
    return file.writeAsString(encoder.convert(data.toJson()), flush: true);
  }

  static Future<void> shareBackup(File file) {
    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Briska Pay backup',
      ),
    );
  }

  static Future<File?> pickBackupFile() async {
    const jsonType = XTypeGroup(
      label: 'Briska Pay backup',
      extensions: ['json'],
      mimeTypes: ['application/json'],
    );
    final file = await openFile(acceptedTypeGroups: [jsonType]);
    if (file == null || file.path.isEmpty) return null;
    return File(file.path);
  }

  static Future<BriskaBackupPreview> previewFile(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        _rejectInvalidBackup();
      }
      return previewJson(decoded);
    } on BriskaBackupException {
      rethrow;
    } catch (_) {
      _rejectInvalidBackup();
    }
  }

  static BriskaBackupPreview previewJson(Map<String, dynamic> json) {
    final version = json['backupVersion'];
    if (version is! int || version != briskaBackupVersion) {
      throw const BriskaBackupException(
        'This backup version is not supported.',
      );
    }
    final appName = json['appName'];
    if (appName != 'Briska' && appName != _legacyBackupAppName) {
      _rejectInvalidBackup();
    }
    final isLegacy = appName == _legacyBackupAppName;
    final settingsJson = json['settings'];
    final entriesJson = json['workEntries'];
    final exportsJson = json['exportRecords'];
    if (settingsJson is! Map<String, dynamic> || entriesJson is! List) {
      _rejectInvalidBackup();
    }
    if (exportsJson != null && exportsJson is! List) _rejectInvalidBackup();

    try {
      final createdAt = _requiredDate(json['createdAt']);
      final hasLegacyRates =
          settingsJson.containsKey('homeHourlyRate') ||
          settingsJson.containsKey('awayHourlyRate');
      if (!isLegacy &&
          hasLegacyRates &&
          (!settingsJson.containsKey('homeHourlyRate') ||
              !settingsJson.containsKey('awayHourlyRate'))) {
        _rejectInvalidBackup();
      }
      _validateSettings(
        settingsJson,
        allowMissingLegacyFields:
            isLegacy || settingsJson.containsKey('homeHourlyRate'),
      );
      final entries = entriesJson.map(_validatedWorkEntry).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      final records =
          (exportsJson as List? ?? const [])
              .map(_validatedExportRecord)
              .toList()
            ..sort((a, b) => b.exportedAt.compareTo(a.exportedAt));
      final settings = AppSettings.fromJson(settingsJson);
      final data = BriskaBackupData(
        createdAt: createdAt,
        settings: settings,
        workEntries: entries,
        exportRecords: records,
      );
      return BriskaBackupPreview(
        createdAt: createdAt,
        userName: settings.fullName,
        companyName: settings.companyName,
        entryCount: entries.length,
        exportCount: records.length,
        data: data,
      );
    } on BriskaBackupException {
      rethrow;
    } catch (_) {
      _rejectInvalidBackup();
    }
  }

  static Never _rejectInvalidBackup() {
    throw const BriskaBackupException(_invalidBackupMessage);
  }

  static Map<String, dynamic> _stringMap(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      _rejectInvalidBackup();
    }
    return Map<String, dynamic>.from(value);
  }

  static void _requireKeys(Map<String, dynamic> json, Iterable<String> keys) {
    if (keys.any((key) => !json.containsKey(key))) _rejectInvalidBackup();
  }

  static bool _isFiniteNonNegative(Object? value) =>
      value is num && value.isFinite && value >= 0;

  static bool _isIntegerInRange(Object? value, int min, int max) =>
      value is int && value >= min && value <= max;

  static DateTime _requiredDate(Object? value) {
    if (value is! String) _rejectInvalidBackup();
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:T.*)?$',
    ).firstMatch(value);
    final parsed = DateTime.tryParse(value);
    if (match == null ||
        parsed == null ||
        parsed.year != int.parse(match.group(1)!) ||
        parsed.month != int.parse(match.group(2)!) ||
        parsed.day != int.parse(match.group(3)!)) {
      _rejectInvalidBackup();
    }
    return parsed;
  }

  static bool _isValidTime(Object? value) {
    if (value is! String) return false;
    final normalized = WorkCalculator.normalizeTime(value);
    if (normalized == null) return false;
    final parts = normalized.split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    return hour != null &&
        minute != null &&
        hour >= 0 &&
        hour <= 23 &&
        minute >= 0 &&
        minute <= 59;
  }

  static WorkEntry _validatedWorkEntry(Object? value) {
    final json = _stringMap(value);
    if (!json.containsKey('rateType') && json['workLocation'] is String) {
      json['rateType'] = json['workLocation'] == 'Away'
          ? 'secondary'
          : 'primary';
    }
    _requireKeys(json, const [
      'id',
      'entryType',
      'date',
      'siteName',
      'startTime',
      'finishTime',
      'breakMinutes',
      'rateType',
      'hourlyRateUsed',
      'jobUplift',
      'totalHours',
      'wages',
      'totalPay',
      'notes',
    ]);
    final type = json['entryType'];
    if (json['id'] is! String ||
        (json['id'] as String).isEmpty ||
        type is! String ||
        !const {
          'WorkDay',
          'Holiday',
          'bankHoliday',
          'BankHoliday',
          'UnpaidDayOff',
          'SickDay',
        }.contains(type) ||
        json['siteName'] is! String ||
        json['startTime'] is! String ||
        json['finishTime'] is! String ||
        json['rateType'] is! String ||
        !const {'primary', 'secondary'}.contains(json['rateType']) ||
        json['notes'] is! String ||
        (json.containsKey('isPaidSickDay') && json['isPaidSickDay'] is! bool) ||
        (json.containsKey('isPaidBankHoliday') &&
            json['isPaidBankHoliday'] is! bool) ||
        (json.containsKey('isBankHoliday') && json['isBankHoliday'] is! bool) ||
        !_isIntegerInRange(json['breakMinutes'], 0, 1440) ||
        !_isFiniteNonNegative(json['hourlyRateUsed']) ||
        !_isFiniteNonNegative(json['dailyAllowance']) ||
        !_isFiniteNonNegative(json['jobUplift']) ||
        !_isFiniteNonNegative(json['totalHours']) ||
        (json['totalHours'] as num) > 24 ||
        !_isFiniteNonNegative(json['wages']) ||
        !_isFiniteNonNegative(json['totalPay'])) {
      _rejectInvalidBackup();
    }
    _requiredDate(json['date']);
    if (type == 'WorkDay') {
      if (!_isValidTime(json['startTime']) ||
          !_isValidTime(json['finishTime'])) {
        _rejectInvalidBackup();
      }
      final calculation = WorkCalculator.calculate(
        startTime: json['startTime'] as String,
        finishTime: json['finishTime'] as String,
        breakMinutes: json['breakMinutes'] as int,
        hourlyRate: (json['hourlyRateUsed'] as num).toDouble(),
        rateType: json['rateType'] as String,
        dailyAllowance: (json['dailyAllowance'] as num).toDouble(),
        jobUplift: (json['jobUplift'] as num).toDouble(),
      );
      if (!calculation.isValid) _rejectInvalidBackup();
    }
    return WorkCalculator.recalculateEntry(WorkEntry.fromJson(json));
  }

  static void _validateSettings(
    Map<String, dynamic> json, {
    required bool allowMissingLegacyFields,
  }) {
    const keys = [
      'fullName',
      'companyName',
      'onboardingCompleted',
      'primaryRateLabel',
      'primaryRateValue',
      'secondaryRateLabel',
      'secondaryRateValue',
      'payFrequency',
      'payDay',
      'payPeriodAnchorDate',
      'paydayRule',
      'paydayOffsetDays',
      'paydayFixedDay',
      'paydaySelectedWeekday',
      'paydayWeekday',
      'customPeriodStartDay',
      'payScheduleAnchorPrompted',
      'defaultStartTime',
      'defaultFinishTime',
      'defaultBreakMinutes',
      'defaultRateType',
      'themeMode',
      'lastExportFormat',
      'currency',
    ];
    if (!allowMissingLegacyFields) _requireKeys(json, keys);
    void validateIfPresent(String key, bool Function(Object?) validator) {
      if (json.containsKey(key) && !validator(json[key])) {
        _rejectInvalidBackup();
      }
    }

    for (final key in const [
      'fullName',
      'companyName',
      'payFrequency',
      'payDay',
      'payPeriodAnchorDate',
      'paydayRule',
      'paydayWeekday',
    ]) {
      validateIfPresent(key, (value) => value is String);
    }
    for (final key in const [
      'onboardingCompleted',
      'payScheduleAnchorPrompted',
    ]) {
      validateIfPresent(key, (value) => value is bool);
    }
    for (final key in const [
      'primaryRateValue',
      'secondaryRateValue',
      'homeHourlyRate',
      'awayHourlyRate',
    ]) {
      validateIfPresent(key, _isFiniteNonNegative);
    }
    for (final key in const ['primaryRateLabel', 'secondaryRateLabel']) {
      validateIfPresent(
        key,
        (value) =>
            value is String &&
            value.trim().isNotEmpty &&
            value.trim().length <= 24,
      );
    }
    validateIfPresent(
      'paydayOffsetDays',
      (value) => _isIntegerInRange(value, 0, 366),
    );
    validateIfPresent(
      'paydayFixedDay',
      (value) => _isIntegerInRange(value, 1, 31),
    );
    validateIfPresent(
      'paydaySelectedWeekday',
      (value) => _isIntegerInRange(value, 1, 7),
    );
    validateIfPresent(
      'customPeriodStartDay',
      (value) => _isIntegerInRange(value, 1, 31),
    );
    validateIfPresent(
      'defaultBreakMinutes',
      (value) => _isIntegerInRange(value, 0, 1440),
    );
    validateIfPresent('defaultStartTime', _isValidTime);
    validateIfPresent('defaultFinishTime', _isValidTime);
    validateIfPresent(
      'defaultRateType',
      (value) => const {'primary', 'secondary'}.contains(value),
    );
    validateIfPresent(
      'defaultWorkLocation',
      (value) => const {'Home', 'Away'}.contains(value),
    );
    validateIfPresent(
      'themeMode',
      (value) => const {
        'light',
        'dark',
        'system',
        'ThemeMode.light',
        'ThemeMode.dark',
        'ThemeMode.system',
      }.contains(value),
    );
    validateIfPresent(
      'lastExportFormat',
      (value) =>
          const {'pdfTimesheet', 'pdfSummary', 'csv', 'excel'}.contains(value),
    );
    if (json.containsKey('payPeriodAnchorDate') &&
        (json['payPeriodAnchorDate'] as String).isNotEmpty) {
      _requiredDate(json['payPeriodAnchorDate']);
    }
    if (json.containsKey('currency')) {
      final currency = _stringMap(json['currency']);
      _requireKeys(currency, const [
        'code',
        'symbol',
        'displayName',
        'locale',
        'decimalDigits',
      ]);
      if (currency['code'] is! String ||
          (currency['code'] as String).isEmpty ||
          currency['symbol'] is! String ||
          currency['displayName'] is! String ||
          currency['locale'] is! String ||
          !_isIntegerInRange(currency['decimalDigits'], 0, 6)) {
        _rejectInvalidBackup();
      }
    }
  }

  static ExportedFileRecord _validatedExportRecord(Object? value) {
    final json = _stringMap(value);
    _requireKeys(json, const ['id', 'fileName', 'exportedAt']);
    if (json['id'] is! String ||
        (json['id'] as String).isEmpty ||
        json['fileName'] is! String ||
        (json['fileName'] as String).isEmpty) {
      _rejectInvalidBackup();
    }
    _requiredDate(json['exportedAt']);
    for (final key in const [
      'fileType',
      'filePath',
      'periodLabel',
      'reportType',
      'dateRangeType',
      'currencyCode',
      'currencySymbol',
    ]) {
      if (json.containsKey(key) && json[key] is! String) {
        _rejectInvalidBackup();
      }
    }
    if (json.containsKey('workDays') &&
        !_isIntegerInRange(json['workDays'], 0, 1000000)) {
      _rejectInvalidBackup();
    }
    for (final key in const ['totalHours', 'totalPay']) {
      if (json.containsKey(key) && !_isFiniteNonNegative(json[key])) {
        _rejectInvalidBackup();
      }
    }
    if (json.containsKey('fileSize') &&
        json['fileSize'] != null &&
        !_isIntegerInRange(json['fileSize'], 0, 0x7fffffffffffffff)) {
      _rejectInvalidBackup();
    }
    if (json.containsKey('isFavourite') && json['isFavourite'] is! bool) {
      _rejectInvalidBackup();
    }
    if (json.containsKey('templateId') &&
        json['templateId'] != null &&
        json['templateId'] is! String) {
      _rejectInvalidBackup();
    }
    for (final key in const ['startDate', 'endDate']) {
      if (json.containsKey(key) && json[key] != null) {
        _requiredDate(json[key]);
      }
    }
    return ExportedFileRecord.fromJson(json);
  }
}
