import '../currency.dart';

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
