import 'dart:io';

import 'currency.dart';

enum EntryType {
  workDay('WorkDay'),
  holiday('Holiday'),
  bankHoliday('bankHoliday'),
  unpaidDayOff('UnpaidDayOff'),
  sickDay('SickDay');

  const EntryType(this.storageValue);
  final String storageValue;

  static EntryType fromStorage(Object? value) => switch (value) {
    EntryType type => type,
    'Holiday' => holiday,
    'bankHoliday' || 'BankHoliday' => bankHoliday,
    'SickDay' => sickDay,
    'UnpaidDayOff' => unpaidDayOff,
    _ => workDay,
  };
}

class WorkEntry {
  WorkEntry({
    required this.id,
    Object? entryType = EntryType.workDay,
    required this.date,
    required this.siteName,
    required this.startTime,
    required this.finishTime,
    required this.breakMinutes,
    String rateType = 'primary',
    String? workLocation,
    required this.hourlyRateUsed,
    required this.dailyAllowance,
    required this.jobUplift,
    required this.totalHours,
    required this.wages,
    required this.totalPay,
    required this.notes,
    this.isPaidSickDay = false,
    this.isPaidBankHoliday = true,
    this.deductionAmount = 0,
    this.deductionReason = '',
  }) : type = EntryType.fromStorage(entryType),
       rateType = workLocation == 'Away' ? 'secondary' : rateType;

  final String id;
  final EntryType type;
  String get entryType => type.storageValue;
  final DateTime date;
  final String siteName;
  final String startTime;
  final String finishTime;
  final int breakMinutes;
  final String rateType;
  @Deprecated('Use rateType')
  String get workLocation => rateType == 'secondary' ? 'Away' : 'Home';
  final double hourlyRateUsed;
  final double dailyAllowance;
  final double jobUplift;
  final double totalHours;
  final double wages;
  final double totalPay;
  final String notes;
  final bool isPaidSickDay;
  final bool isPaidBankHoliday;
  final double deductionAmount;
  final String deductionReason;
  double get grossPay => totalPay;
  double get netPay => totalPay - deductionAmount;

  Map<String, Object?> toJson() => {
    'id': id,
    'entryType': entryType,
    'date': date.toIso8601String(),
    'siteName': siteName,
    'startTime': startTime,
    'finishTime': finishTime,
    'breakMinutes': breakMinutes,
    'rateType': rateType,
    'hourlyRateUsed': hourlyRateUsed,
    'dailyAllowance': dailyAllowance,
    'jobUplift': jobUplift,
    'totalHours': totalHours,
    'wages': wages,
    'totalPay': totalPay,
    'notes': notes,
    'isPaidSickDay': isPaidSickDay,
    if (type == EntryType.bankHoliday) 'isPaidBankHoliday': isPaidBankHoliday,
    'deductionAmount': deductionAmount,
    'deductionReason': deductionReason,
  };

  factory WorkEntry.fromJson(Map<String, dynamic> json) => WorkEntry(
    id: json['id'] as String,
    entryType: _migratedEntryType(json),
    date: DateTime.parse(json['date'] as String),
    siteName: json['siteName'] as String? ?? '',
    startTime: json['startTime'] as String? ?? '08:00',
    finishTime: json['finishTime'] as String? ?? '16:00',
    breakMinutes: (json['breakMinutes'] as num?)?.toInt() ?? 0,
    rateType: _rateTypeFromJson(json['rateType'] ?? json['workLocation']),
    hourlyRateUsed: (json['hourlyRateUsed'] as num?)?.toDouble() ?? 0,
    dailyAllowance: (json['dailyAllowance'] as num?)?.toDouble() ?? 0,
    jobUplift: (json['jobUplift'] as num?)?.toDouble() ?? 0,
    totalHours: (json['totalHours'] as num?)?.toDouble() ?? 0,
    wages: (json['wages'] as num?)?.toDouble() ?? 0,
    totalPay: (json['totalPay'] as num?)?.toDouble() ?? 0,
    notes: json['notes'] as String? ?? '',
    isPaidSickDay: json['isPaidSickDay'] as bool? ?? false,
    isPaidBankHoliday: _migratedBankHolidayPaidStatus(json),
    deductionAmount: (json['deductionAmount'] as num?)?.toDouble() ?? 0,
    deductionReason: json['deductionReason'] as String? ?? '',
  );
}

Object _migratedEntryType(Map<String, dynamic> json) {
  final stored = json['entryType'] as String? ?? 'WorkDay';
  if (stored == 'bankHoliday' || stored == 'BankHoliday') {
    return EntryType.bankHoliday;
  }
  if (json['isBankHoliday'] == true) {
    // The short-lived flag could coexist with real worked or sick entries.
    // Only non-work day types that can be mapped without losing time data are
    // converted. Worked shifts and sick days retain their original type.
    if (stored == 'Holiday' || stored == 'UnpaidDayOff') {
      return EntryType.bankHoliday;
    }
  }
  return stored;
}

bool _migratedBankHolidayPaidStatus(Map<String, dynamic> json) {
  final explicit = json['isPaidBankHoliday'];
  if (explicit is bool) return explicit;
  if (json['isBankHoliday'] == true && json['entryType'] == 'UnpaidDayOff') {
    return false;
  }
  return true;
}

class AppSettings {
  const AppSettings({
    this.fullName = '',
    this.companyName = '',
    this.onboardingCompleted = false,
    String? primaryRateLabel,
    double primaryRateValue = 0,
    String? secondaryRateLabel,
    double secondaryRateValue = 0,
    double? homeHourlyRate,
    double? awayHourlyRate,
    this.payFrequency = 'Calendar monthly',
    this.payDay = 'Friday',
    this.payPeriodAnchorDate = '',
    this.paydayRule = 'On period end date',
    this.paydayOffsetDays = 0,
    this.paydayFixedDay = 1,
    this.paydaySelectedWeekday = DateTime.friday,
    this.paydayWeekday = 'Friday',
    this.customPeriodStartDay = 1,
    this.payScheduleAnchorPrompted = false,
    this.defaultStartTime = '08:00',
    this.defaultFinishTime = '16:30',
    this.defaultBreakMinutes = 30,
    String defaultRateType = 'primary',
    String? defaultWorkLocation,
    this.themeMode = 'light',
    this.lastExportFormat = 'excel',
    this.currency = defaultCurrency,
  }) : primaryRateLabel = primaryRateLabel ?? 'Standard',
       secondaryRateLabel = secondaryRateLabel ?? 'Overtime',
       primaryRateValue = homeHourlyRate ?? primaryRateValue,
       secondaryRateValue = awayHourlyRate ?? secondaryRateValue,
       defaultRateType = defaultWorkLocation == 'Away'
           ? 'secondary'
           : defaultRateType;

  final String fullName;
  final String companyName;
  final bool onboardingCompleted;
  final String primaryRateLabel;
  final double primaryRateValue;
  final String secondaryRateLabel;
  final double secondaryRateValue;
  @Deprecated('Use primaryRateValue')
  double get homeHourlyRate => primaryRateValue;
  @Deprecated('Use secondaryRateValue')
  double get awayHourlyRate => secondaryRateValue;
  final String payFrequency;
  final String payDay;
  final String payPeriodAnchorDate;
  final String paydayRule;
  final int paydayOffsetDays;
  final int paydayFixedDay;
  final int paydaySelectedWeekday;
  final String paydayWeekday;
  final int customPeriodStartDay;
  final bool payScheduleAnchorPrompted;
  final String defaultStartTime;
  final String defaultFinishTime;
  final int defaultBreakMinutes;
  final String defaultRateType;
  @Deprecated('Use defaultRateType')
  String get defaultWorkLocation =>
      defaultRateType == 'secondary' ? 'Away' : 'Home';

  String labelForRate(String rateType) => rateType == 'secondary'
      ? _validRateLabel(secondaryRateLabel, 'Secondary Rate')
      : _validRateLabel(primaryRateLabel, 'Primary Rate');
  final String themeMode;
  final String lastExportFormat;
  final CurrencyConfig currency;

  AppSettings copyWith({
    String? fullName,
    String? companyName,
    bool? onboardingCompleted,
    String? primaryRateLabel,
    double? primaryRateValue,
    String? secondaryRateLabel,
    double? secondaryRateValue,
    double? homeHourlyRate,
    double? awayHourlyRate,
    String? payFrequency,
    String? payDay,
    String? payPeriodAnchorDate,
    String? paydayRule,
    int? paydayOffsetDays,
    int? paydayFixedDay,
    int? paydaySelectedWeekday,
    String? paydayWeekday,
    int? customPeriodStartDay,
    bool? payScheduleAnchorPrompted,
    String? defaultStartTime,
    String? defaultFinishTime,
    int? defaultBreakMinutes,
    String? defaultRateType,
    String? defaultWorkLocation,
    String? themeMode,
    String? lastExportFormat,
    CurrencyConfig? currency,
  }) => AppSettings(
    fullName: fullName ?? this.fullName,
    companyName: companyName ?? this.companyName,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    primaryRateLabel: primaryRateLabel ?? this.primaryRateLabel,
    primaryRateValue:
        homeHourlyRate ?? primaryRateValue ?? this.primaryRateValue,
    secondaryRateLabel: secondaryRateLabel ?? this.secondaryRateLabel,
    secondaryRateValue:
        awayHourlyRate ?? secondaryRateValue ?? this.secondaryRateValue,
    payFrequency: payFrequency ?? this.payFrequency,
    payDay: payDay ?? this.payDay,
    payPeriodAnchorDate: payPeriodAnchorDate ?? this.payPeriodAnchorDate,
    paydayRule: paydayRule ?? this.paydayRule,
    paydayOffsetDays: paydayOffsetDays ?? this.paydayOffsetDays,
    paydayFixedDay: paydayFixedDay ?? this.paydayFixedDay,
    paydaySelectedWeekday: paydaySelectedWeekday ?? this.paydaySelectedWeekday,
    paydayWeekday: paydayWeekday ?? this.paydayWeekday,
    customPeriodStartDay: customPeriodStartDay ?? this.customPeriodStartDay,
    payScheduleAnchorPrompted:
        payScheduleAnchorPrompted ?? this.payScheduleAnchorPrompted,
    defaultStartTime: defaultStartTime ?? this.defaultStartTime,
    defaultFinishTime: defaultFinishTime ?? this.defaultFinishTime,
    defaultBreakMinutes: defaultBreakMinutes ?? this.defaultBreakMinutes,
    defaultRateType: defaultWorkLocation == 'Away'
        ? 'secondary'
        : defaultRateType ?? this.defaultRateType,
    themeMode: themeMode ?? this.themeMode,
    lastExportFormat: lastExportFormat ?? this.lastExportFormat,
    currency: currency ?? this.currency,
  );

  Map<String, Object?> toJson() => {
    'fullName': fullName,
    'companyName': companyName,
    'onboardingCompleted': onboardingCompleted,
    'primaryRateLabel': primaryRateLabel,
    'primaryRateValue': primaryRateValue,
    'secondaryRateLabel': secondaryRateLabel,
    'secondaryRateValue': secondaryRateValue,
    'payFrequency': payFrequency,
    'payDay': payDay,
    'payPeriodAnchorDate': payPeriodAnchorDate,
    'paydayRule': paydayRule,
    'paydayOffsetDays': paydayOffsetDays,
    'paydayFixedDay': paydayFixedDay,
    'paydaySelectedWeekday': paydaySelectedWeekday,
    'paydayWeekday': paydayWeekday,
    'customPeriodStartDay': customPeriodStartDay,
    'payScheduleAnchorPrompted': payScheduleAnchorPrompted,
    'defaultStartTime': defaultStartTime,
    'defaultFinishTime': defaultFinishTime,
    'defaultBreakMinutes': defaultBreakMinutes,
    'defaultRateType': defaultRateType,
    'themeMode': themeMode,
    'lastExportFormat': lastExportFormat,
    'currency': currency.toJson(),
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    fullName: json['fullName'] as String? ?? '',
    companyName: json['companyName'] as String? ?? '',
    onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
    primaryRateLabel: _migratedRateLabel(json, 'primaryRateLabel', 'Home'),
    primaryRateValue:
        ((json['primaryRateValue'] ?? json['homeHourlyRate']) as num?)
            ?.toDouble() ??
        0,
    secondaryRateLabel: _migratedRateLabel(json, 'secondaryRateLabel', 'Away'),
    secondaryRateValue:
        ((json['secondaryRateValue'] ?? json['awayHourlyRate']) as num?)
            ?.toDouble() ??
        0,
    payFrequency: switch (json['payFrequency'] as String?) {
      'Monthly' => 'Calendar monthly',
      final value? => value,
      _ => 'Calendar monthly',
    },
    payDay: json['payDay'] as String? ?? 'Friday',
    payPeriodAnchorDate: json['payPeriodAnchorDate'] as String? ?? '',
    paydayRule: _paydayRuleFromJson(json['paydayRule']),
    paydayOffsetDays: (json['paydayOffsetDays'] as num?)?.toInt() ?? 0,
    paydayFixedDay: (json['paydayFixedDay'] as num?)?.toInt() ?? 1,
    paydaySelectedWeekday: _weekdayFromJson(
      json['paydaySelectedWeekday'],
      fallbackName:
          (json['paydayWeekday'] as String?) ?? (json['payDay'] as String?),
    ),
    paydayWeekday:
        (json['paydayWeekday'] as String?) ??
        _weekdayNameFromValue(json['paydaySelectedWeekday']) ??
        (json['payDay'] as String?) ??
        'Friday',
    customPeriodStartDay: (json['customPeriodStartDay'] as num?)?.toInt() ?? 1,
    payScheduleAnchorPrompted:
        json['payScheduleAnchorPrompted'] as bool? ?? false,
    defaultStartTime: json['defaultStartTime'] as String? ?? '08:00',
    defaultFinishTime: json['defaultFinishTime'] as String? ?? '16:30',
    defaultBreakMinutes: (json['defaultBreakMinutes'] as num?)?.toInt() ?? 30,
    defaultRateType: _rateTypeFromJson(
      json['defaultRateType'] ?? json['defaultWorkLocation'],
    ),
    themeMode: _themeModeFromJson(json['themeMode']),
    lastExportFormat: _exportFormatFromJson(json['lastExportFormat']),
    currency: json['currency'] is Map
        ? CurrencyConfig.fromJson(
            Map<String, dynamic>.from(json['currency'] as Map),
          )
        : defaultCurrency,
  );
}

String _rateTypeFromJson(Object? value) =>
    value == 'secondary' || value == 'Away' ? 'secondary' : 'primary';

String _migratedRateLabel(
  Map<String, dynamic> json,
  String key,
  String legacy,
) {
  final value = (json[key] as String?)?.trim();
  if (value != null && value.isNotEmpty) return value;
  final isLegacy =
      json.containsKey('homeHourlyRate') || json.containsKey('awayHourlyRate');
  return isLegacy
      ? legacy
      : (key == 'primaryRateLabel' ? 'Standard' : 'Overtime');
}

String _validRateLabel(String value, String fallback) =>
    value.trim().isEmpty ? fallback : value.trim();

String _themeModeFromJson(Object? value) {
  return switch (value) {
    'light' || 'dark' => value as String,
    'ThemeMode.light' => 'light',
    'ThemeMode.dark' => 'dark',
    'ThemeMode.system' || 'system' => 'light',
    _ => 'light',
  };
}

String _paydayRuleFromJson(Object? value) {
  return switch (value) {
    'Following weekday' => 'Next selected weekday after period end',
    final String rule => rule,
    _ => 'On period end date',
  };
}

String _exportFormatFromJson(Object? value) {
  return switch (value) {
    'pdfTimesheet' || 'pdfSummary' || 'csv' || 'excel' => value as String,
    _ => 'excel',
  };
}

int _weekdayFromJson(Object? value, {String? fallbackName}) {
  if (value is num) {
    final weekday = value.toInt();
    if (weekday >= DateTime.monday && weekday <= DateTime.sunday) {
      return weekday;
    }
  }
  return _weekdayValueFromName(fallbackName);
}

int _weekdayValueFromName(String? value) {
  return switch (value) {
    'Monday' => DateTime.monday,
    'Tuesday' => DateTime.tuesday,
    'Wednesday' => DateTime.wednesday,
    'Thursday' => DateTime.thursday,
    'Friday' => DateTime.friday,
    'Saturday' => DateTime.saturday,
    'Sunday' => DateTime.sunday,
    _ => DateTime.friday,
  };
}

String? _weekdayNameFromValue(Object? value) {
  if (value is! num) return null;
  return switch (value.toInt()) {
    DateTime.monday => 'Monday',
    DateTime.tuesday => 'Tuesday',
    DateTime.wednesday => 'Wednesday',
    DateTime.thursday => 'Thursday',
    DateTime.friday => 'Friday',
    DateTime.saturday => 'Saturday',
    DateTime.sunday => 'Sunday',
    _ => null,
  };
}

class ExportedFileRecord {
  const ExportedFileRecord({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.filePath,
    required this.exportedAt,
    required this.periodLabel,
    required this.workDays,
    required this.totalHours,
    required this.totalPay,
    this.fileSize,
    this.reportType = 'Timesheet',
    this.dateRangeType = 'currentPayPeriod',
    this.startDate,
    this.endDate,
    this.isFavourite = false,
    this.templateId,
    this.currencyCode = defaultCurrencyCode,
    this.currencySymbol = defaultCurrencySymbol,
  });

  final String id;
  final String fileName;
  final String fileType;
  final String filePath;
  final DateTime exportedAt;
  final String periodLabel;
  final int workDays;
  final double totalHours;
  final double totalPay;
  final int? fileSize;
  final String reportType;
  final String dateRangeType;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isFavourite;
  final String? templateId;
  final String currencyCode;
  final String currencySymbol;

  bool get isAvailable => filePath.isNotEmpty && File(filePath).existsSync();

  ExportedFileRecord copyWith({
    String? fileName,
    String? fileType,
    String? filePath,
    bool? isFavourite,
    String? currencyCode,
    String? currencySymbol,
  }) => ExportedFileRecord(
    id: id,
    fileName: fileName ?? this.fileName,
    fileType: fileType ?? this.fileType,
    filePath: filePath ?? this.filePath,
    exportedAt: exportedAt,
    periodLabel: periodLabel,
    workDays: workDays,
    totalHours: totalHours,
    totalPay: totalPay,
    fileSize: fileSize,
    reportType: reportType,
    dateRangeType: dateRangeType,
    startDate: startDate,
    endDate: endDate,
    isFavourite: isFavourite ?? this.isFavourite,
    templateId: templateId,
    currencyCode: currencyCode ?? this.currencyCode,
    currencySymbol: currencySymbol ?? this.currencySymbol,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'fileName': fileName,
    'fileType': fileType,
    'filePath': filePath,
    'exportedAt': exportedAt.toIso8601String(),
    'periodLabel': periodLabel,
    'workDays': workDays,
    'totalHours': totalHours,
    'totalPay': totalPay,
    'fileSize': fileSize,
    'reportType': reportType,
    'dateRangeType': dateRangeType,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'isFavourite': isFavourite,
    'templateId': templateId,
    'currencyCode': currencyCode,
    'currencySymbol': currencySymbol,
  };

  factory ExportedFileRecord.fromJson(Map<String, dynamic> json) =>
      ExportedFileRecord(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        fileType: json['fileType'] as String? ?? 'Excel',
        filePath: json['filePath'] as String? ?? '',
        exportedAt: DateTime.parse(json['exportedAt'] as String),
        periodLabel: json['periodLabel'] as String? ?? '',
        workDays: (json['workDays'] as num?)?.toInt() ?? 0,
        totalHours: (json['totalHours'] as num?)?.toDouble() ?? 0,
        totalPay: (json['totalPay'] as num?)?.toDouble() ?? 0,
        fileSize: (json['fileSize'] as num?)?.toInt(),
        reportType: json['reportType'] as String? ?? 'Timesheet',
        dateRangeType: json['dateRangeType'] as String? ?? 'currentPayPeriod',
        startDate: DateTime.tryParse(json['startDate'] as String? ?? ''),
        endDate: DateTime.tryParse(json['endDate'] as String? ?? ''),
        isFavourite: json['isFavourite'] as bool? ?? false,
        templateId: json['templateId'] as String?,
        currencyCode: json['currencyCode'] as String? ?? defaultCurrency.code,
        currencySymbol:
            json['currencySymbol'] as String? ?? defaultCurrency.symbol,
      );
}
