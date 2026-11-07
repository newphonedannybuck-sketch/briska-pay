import 'dart:convert';

import 'export_formats.dart';
import 'currency.dart';
import 'models.dart';
import 'work_calculator.dart';

abstract final class CsvExportService {
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

  static List<int> buildCsv(
    List<WorkEntry> source, {
    String fullName = '',
    String companyName = '',
    String periodLabel = '',
    CurrencyConfig currency = defaultCurrency,
    String primaryRateLabel = 'Home',
    String secondaryRateLabel = 'Away',
    bool includeNotes = true,
  }) {
    final columns = currencyColumns(currency.code);
    final summary = WorkCalculator.summarize(source);
    final rows = <List<Object?>>[
      columns,
      ...summary.entries.map(
        (entry) => [
          _dateValue(entry.date),
          entry.siteName,
          entryTypeLabel(entry.entryType, isPaidSickDay: entry.isPaidSickDay),
          entry.type == EntryType.bankHoliday
              ? (entry.isPaidBankHoliday ? 'Paid' : 'Unpaid')
              : '',
          entry.rateType == 'secondary' ? secondaryRateLabel : primaryRateLabel,
          entry.startTime,
          entry.finishTime,
          entry.breakMinutes,
          _number(entry.totalHours),
          _moneyNumber(entry.hourlyRateUsed),
          _moneyNumber(entry.wages),
          _moneyNumber(entry.dailyAllowance),
          _moneyNumber(entry.jobUplift),
          _moneyNumber(entry.totalPay),
          _moneyNumber(entry.deductionAmount),
          entry.deductionReason,
          _moneyNumber(entry.netPay),
          includeNotes ? entry.notes : '',
        ],
      ),
    ];
    final csv = rows.map(_row).join('\r\n');
    return [...utf8.encode('\uFEFF'), ...utf8.encode('$csv\r\n')];
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
    bool includeNotes = true,
  }) async {
    if (entries.isEmpty) {
      throw ArgumentError('Record a day before exporting.');
    }
    final file = await ExportFileNamer.createExportFile(
      fullName: fullName,
      companyName: companyName,
      periodLabel: periodLabel,
      format: ExportFormat.csv,
      fileNameLabel: fileNameLabel,
    );
    final bytes = buildCsv(
      entries,
      fullName: fullName,
      companyName: companyName,
      periodLabel: periodLabel,
      currency: currency,
      primaryRateLabel: primaryRateLabel,
      secondaryRateLabel: secondaryRateLabel,
      includeNotes: includeNotes,
    );
    await file.writeAsBytes(bytes, flush: true);
    return ExportFileResult(
      fileName: file.uri.pathSegments.last,
      filePath: file.path,
      fileSize: bytes.length,
    );
  }

  static String entryTypeLabel(String value, {bool isPaidSickDay = false}) {
    return switch (value) {
      'UnpaidDayOff' => 'Unpaid day off',
      'Holiday' => 'Holiday',
      'bankHoliday' || 'BankHoliday' => 'Bank Holiday',
      'SickDay' => isPaidSickDay ? 'Paid Sick Day' : 'Unpaid Sick Day',
      _ => 'Work day',
    };
  }

  static List<String> currencyColumns(String code) => [
    ...columns.take(9),
    'Hourly rate ($code)',
    'Base pay ($code)',
    'Daily allowance ($code)',
    'Job uplift ($code)',
    'Gross pay ($code)',
    'Deduction ($code)',
    'Deduction reason',
    'Net pay ($code)',
    columns.last,
  ];

  static String _row(List<Object?> values) => values.map(_cell).join(',');

  static String _cell(Object? value) {
    final text = (value ?? '').toString();
    final mustQuote =
        text.contains(',') ||
        text.contains('"') ||
        text.contains('\r') ||
        text.contains('\n');
    final escaped = text.replaceAll('"', '""');
    return mustQuote ? '"$escaped"' : escaped;
  }

  static String _dateValue(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static String _number(double value) {
    if (!value.isFinite) return '0';
    var text = value.toStringAsFixed(2);
    text = text.replaceFirst(RegExp(r'\.?0+$'), '');
    return text.isEmpty || text == '-0' ? '0' : text;
  }

  static String _moneyNumber(double value) => value.toStringAsFixed(2);
}
