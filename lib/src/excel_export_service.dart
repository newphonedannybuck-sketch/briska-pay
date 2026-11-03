import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'display_format.dart';
import 'currency.dart';
import 'export_formats.dart';
import 'models.dart';
import 'work_calculator.dart';

abstract final class ExcelExportService {
  static const columns = [
    'Date',
    'Site/job',
    'Day type',
    'Pay status',
    'Rate used',
    'Start time',
    'Finish time',
    'Break minutes',
    'Hours worked',
    'Hourly rate',
    'Base pay',
    'Daily allowance',
    'Job uplift',
    'Gross pay',
    'Deduction',
    'Deduction reason',
    'Net pay',
    'Notes',
  ];

  static Uint8List buildWorkbook(
    List<WorkEntry> source, {
    String fullName = '',
    String companyName = '',
    String periodLabel = '',
    CurrencyConfig currency = defaultCurrency,
    String primaryRateLabel = 'Home',
    String secondaryRateLabel = 'Away',
  }) {
    final summary = WorkCalculator.summarize(source);
    final workbook = Excel.createExcel();
    final sheet = workbook['Work Entries'];
    workbook.delete('Sheet1');

    sheet.appendRow([TextCellValue('Briska Pay Work Report')]);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: columns.length - 1, rowIndex: 0),
    );
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 18,
      fontColorHex: ExcelColor.fromHexString('#1B8F5A'),
    );
    sheet.appendRow([
      TextCellValue('User'),
      TextCellValue(fullName.isEmpty ? 'Not provided' : fullName),
    ]);
    final trimmedCompanyName = companyName.trim();
    if (trimmedCompanyName.isNotEmpty) {
      sheet.appendRow([
        TextCellValue('Employer / company'),
        TextCellValue(trimmedCompanyName),
      ]);
    }
    sheet.appendRow([
      TextCellValue('Period'),
      TextCellValue(periodLabel.isEmpty ? 'All entries' : periodLabel),
    ]);
    sheet.appendRow([TextCellValue('')]);

    final headerRow = sheet.maxRows;
    sheet.appendRow(columns.map(TextCellValue.new).toList());
    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('#1B8F5A'),
      horizontalAlign: HorizontalAlign.Center,
    );
    for (var column = 0; column < columns.length; column++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: headerRow,
                ),
              )
              .cellStyle =
          headerStyle;
    }

    for (var index = 0; index < summary.entries.length; index++) {
      final entry = summary.entries[index];
      sheet.appendRow([
        DateCellValue.fromDateTime(entry.date),
        TextCellValue(entry.siteName),
        TextCellValue(
          entry.entryType == 'SickDay'
              ? (entry.isPaidSickDay ? 'Paid Sick Day' : 'Unpaid Sick Day')
              : entry.entryType == 'UnpaidDayOff'
              ? 'Unpaid day off'
              : entry.entryType == 'WorkDay'
              ? 'Work day'
              : entry.type == EntryType.bankHoliday
              ? 'Bank Holiday'
              : 'Holiday',
        ),
        TextCellValue(
          entry.type == EntryType.bankHoliday
              ? (entry.isPaidBankHoliday ? 'Paid' : 'Unpaid')
              : '',
        ),
        TextCellValue(
          entry.rateType == 'secondary' ? secondaryRateLabel : primaryRateLabel,
        ),
        TextCellValue(entry.startTime),
        TextCellValue(entry.finishTime),
        IntCellValue(entry.breakMinutes),
        DoubleCellValue(entry.totalHours),
        DoubleCellValue(entry.hourlyRateUsed),
        DoubleCellValue(entry.wages),
        DoubleCellValue(entry.dailyAllowance),
        DoubleCellValue(entry.jobUplift),
        DoubleCellValue(entry.totalPay),
        DoubleCellValue(entry.deductionAmount),
        TextCellValue(entry.deductionReason),
        DoubleCellValue(entry.netPay),
        TextCellValue(entry.notes),
      ]);
      final row = headerRow + 1 + index;
      _applyDateStyle(sheet, column: 0, row: row);
      _applyWrappedTextStyle(sheet, column: 1, row: row);
      _applyWholeNumberStyle(sheet, column: 7, row: row);
      _applyFlexibleNumberStyle(sheet, column: 8, row: row);
      for (final column in [9, 10, 11, 12, 13, 14, 16]) {
        _applyCurrencyStyle(
          sheet,
          column: column,
          row: row,
          currency: currency,
        );
      }
    }

    sheet.appendRow([TextCellValue('')]);
    _summaryRow(
      sheet,
      'Days recorded',
      summary.totalDays.toDouble(),
      config: currency,
    );
    _summaryRow(
      sheet,
      'Holidays',
      summary.holidayDays.toDouble(),
      config: currency,
    );
    _summaryRow(
      sheet,
      'Bank Holidays',
      summary.bankHolidayDays.toDouble(),
      config: currency,
    );
    _summaryRow(
      sheet,
      'Paid Bank Holidays',
      summary.paidBankHolidayDays.toDouble(),
      config: currency,
    );
    _summaryRow(
      sheet,
      'Unpaid Bank Holidays',
      summary.unpaidBankHolidayDays.toDouble(),
      config: currency,
    );
    _summaryRow(
      sheet,
      'Unpaid days off',
      summary.unpaidDays.toDouble(),
      config: currency,
    );
    _summaryRow(
      sheet,
      'Paid Sick Days',
      summary.paidSickDays.toDouble(),
      config: currency,
    );
    _summaryRow(
      sheet,
      'Unpaid Sick Days',
      summary.unpaidSickDays.toDouble(),
      config: currency,
    );
    _summaryRow(
      sheet,
      'Total hours',
      summary.totalHours,
      hours: true,
      config: currency,
    );
    _summaryRow(
      sheet,
      'Total base pay',
      summary.totalWages,
      currency: true,
      config: currency,
    );
    _summaryRow(
      sheet,
      'Total daily allowance',
      summary.totalDailyAllowance,
      currency: true,
      config: currency,
    );
    _summaryRow(
      sheet,
      'Total job uplift',
      summary.totalJobUplift,
      currency: true,
      config: currency,
    );
    _summaryRow(
      sheet,
      'Gross pay',
      summary.totalExpectedPay,
      currency: true,
      config: currency,
    );
    _summaryRow(
      sheet,
      'Total deductions',
      summary.totalDeductions,
      currency: true,
      config: currency,
    );
    _summaryRow(
      sheet,
      'Net pay',
      summary.totalNetPay,
      currency: true,
      config: currency,
      highlight: true,
    );

    const widths = [
      14.0,
      28.0,
      16.0,
      14.0,
      12.0,
      12.0,
      14.0,
      14.0,
      14.0,
      14.0,
      18.0,
      14.0,
      14.0,
      32.0,
      14.0,
      18.0,
      14.0,
    ];
    for (var index = 0; index < widths.length; index++) {
      sheet.setColumnWidth(index, widths[index]);
    }

    final bytes = workbook.encode();
    if (bytes == null) throw StateError('Could not create Excel workbook.');
    return Uint8List.fromList(bytes);
  }

  static Future<ExportFileResult> export(
    List<WorkEntry> entries, {
    required String fullName,
    required String companyName,
    required String periodLabel,
    String? fileNameLabel,
    CurrencyConfig currency = defaultCurrency,
    String primaryRateLabel = 'Home',
    String secondaryRateLabel = 'Away',
  }) async {
    if (entries.isEmpty) {
      throw ArgumentError('Record a day before exporting.');
    }
    final file = await ExportFileNamer.createExportFile(
      fullName: fullName,
      companyName: companyName,
      periodLabel: periodLabel,
      format: ExportFormat.excel,
      fileNameLabel: fileNameLabel,
    );

    final bytes = buildWorkbook(
      entries,
      fullName: fullName,
      companyName: companyName,
      periodLabel: periodLabel,
      currency: currency,
      primaryRateLabel: primaryRateLabel,
      secondaryRateLabel: secondaryRateLabel,
    );
    await file.writeAsBytes(bytes, flush: true);
    return ExportFileResult(
      fileName: file.uri.pathSegments.last,
      filePath: file.path,
      fileSize: bytes.length,
    );
  }

  static String buildFileName({
    required String fullName,
    String companyName = '',
    required String periodLabel,
    String? fileNameLabel,
  }) => ExportFileNamer.buildFileName(
    fullName: fullName,
    companyName: companyName,
    periodLabel: periodLabel,
    format: ExportFormat.excel,
    fileNameLabel: fileNameLabel,
  );

  static void _summaryRow(
    Sheet sheet,
    String label,
    double value, {
    bool currency = false,
    bool hours = false,
    bool highlight = false,
    required CurrencyConfig config,
  }) {
    sheet.appendRow([TextCellValue(label), DoubleCellValue(value)]);
    final row = sheet.maxRows - 1;
    final background = highlight
        ? ExcelColor.fromHexString('#2E9D69')
        : ExcelColor.white;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = CellStyle(
      bold: true,
      backgroundColorHex: background,
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .cellStyle = CellStyle(
      bold: true,
      numberFormat: CustomNumericNumFormat(
        formatCode: _summaryNumberFormat(
          currency: currency,
          hours: hours,
          config: config,
        ),
      ),
      backgroundColorHex: background,
    );
  }

  static String _summaryNumberFormat({
    required bool currency,
    required bool hours,
    required CurrencyConfig config,
  }) {
    if (currency) return CurrencyFormatter.excelNumberFormat(config);
    if (hours) return excelFlexibleNumberFormat;
    return excelWholeNumberFormat;
  }

  static void _applyWholeNumberStyle(
    Sheet sheet, {
    required int column,
    required int row,
  }) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
        .cellStyle = CellStyle(
      numberFormat: CustomNumericNumFormat(formatCode: excelWholeNumberFormat),
    );
  }

  static void _applyDateStyle(
    Sheet sheet, {
    required int column,
    required int row,
  }) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
        .cellStyle = CellStyle(
      numberFormat: CustomDateTimeNumFormat(formatCode: 'dd/mm/yyyy'),
    );
  }

  static void _applyWrappedTextStyle(
    Sheet sheet, {
    required int column,
    required int row,
  }) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
        .cellStyle = CellStyle(
      textWrapping: TextWrapping.WrapText,
    );
  }

  static void _applyFlexibleNumberStyle(
    Sheet sheet, {
    required int column,
    required int row,
  }) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
        .cellStyle = CellStyle(
      numberFormat: CustomNumericNumFormat(
        formatCode: excelFlexibleNumberFormat,
      ),
    );
  }

  static void _applyCurrencyStyle(
    Sheet sheet, {
    required int column,
    required int row,
    required CurrencyConfig currency,
  }) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
        .cellStyle = CellStyle(
      numberFormat: CustomNumericNumFormat(
        formatCode: CurrencyFormatter.excelNumberFormat(currency),
      ),
    );
  }
}
