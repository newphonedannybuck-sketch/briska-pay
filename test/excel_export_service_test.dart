import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briska/src/display_format.dart';
import 'package:briska/src/excel_export_service.dart';
import 'package:briska/src/currency.dart';
import 'package:briska/src/models.dart';

void main() {
  test('creates Excel workbook with entry columns and summary rows', () {
    final entry = WorkEntry(
      id: '1',
      date: DateTime(2026, 7, 9),
      siteName: 'Test Job',
      startTime: '08:00',
      finishTime: '17:00',
      breakMinutes: 30,
      workLocation: 'Away',
      hourlyRateUsed: 20,
      dailyAllowance: 10,
      jobUplift: 150,
      totalHours: 8.5,
      wages: 170,
      totalPay: 330,
      notes: 'Completed',
    );

    final bytes = ExcelExportService.buildWorkbook(
      [entry],
      fullName: 'Daniel Beckett',
      periodLabel: 'July 2026',
    );
    final workbook = Excel.decodeBytes(bytes);
    final sheet = workbook.tables['Work Entries']!;

    expect(
      (sheet.rows.first.first!.value as TextCellValue).value.text,
      'Briska Pay Work Report',
    );
    expect(
      (sheet.rows[1][1]!.value as TextCellValue).value.text,
      'Daniel Beckett',
    );
    expect((sheet.rows[4][0]!.value as TextCellValue).value.text, 'Date');
    expect(sheet.rows[5][0]!.cellStyle?.numberFormat.formatCode, 'dd/mm/yyyy');
    expect((sheet.rows[5][1]!.value as TextCellValue).value.text, 'Test Job');
    expect(sheet.rows[5][8]!.value, const DoubleCellValue(8.5));
    expect(sheet.rows[5][10]!.value.toString(), '170');
    expect(sheet.rows[5][13]!.value.toString(), '330');
    expect(
      sheet.rows[5][13]!.cellStyle?.numberFormat.formatCode,
      CurrencyFormatter.excelNumberFormat(defaultCurrency),
    );

    final headers = sheet.rows[4]
        .map((cell) => (cell!.value as TextCellValue).value.text)
        .toList();
    expect(headers, ExcelExportService.columns);
    final labels = sheet.rows
        .where((row) => row.isNotEmpty && row.first?.value is TextCellValue)
        .map((row) => (row.first!.value as TextCellValue).value.text)
        .toList();
    expect(labels, contains('Days recorded'));
    expect(labels, contains('Holidays'));
    expect(labels, contains('Unpaid days off'));
    expect(labels, contains('Total hours'));
    expect(labels, contains('Total base pay'));
    expect(labels, contains('Total daily allowance'));
    expect(labels, contains('Total job uplift'));
    expect(labels, contains('Gross pay'));
  });

  test('builds export filename from full name and month year label', () {
    expect(
      ExcelExportService.buildFileName(
        fullName: 'Daniel Beckett',
        periodLabel: '4 Jul - 17 Jul',
        fileNameLabel: 'July 2026',
      ),
      'Briska_Daniel_Beckett_July_2026.xlsx',
    );
    expect(
      ExcelExportService.buildFileName(
        fullName: 'Daniel Beckett',
        companyName: 'Cool Canvas',
        periodLabel: '4 Jul - 17 Jul',
        fileNameLabel: 'July 2026',
      ),
      'Briska_Cool_Canvas_Daniel_Beckett_July_2026.xlsx',
    );
  });

  test('adds company name near top when provided', () {
    final entry = WorkEntry(
      id: '1',
      date: DateTime(2026, 7, 9),
      siteName: 'Test Job',
      startTime: '08:00',
      finishTime: '16:30',
      breakMinutes: 30,
      workLocation: 'Home',
      hourlyRateUsed: 20,
      dailyAllowance: 0,
      jobUplift: 0,
      totalHours: 8,
      wages: 160,
      totalPay: 160,
      notes: '',
    );

    final bytes = ExcelExportService.buildWorkbook(
      [entry],
      fullName: 'Daniel Beckett',
      companyName: 'Example Company Ltd',
      periodLabel: 'July 2026',
    );
    final sheet = Excel.decodeBytes(bytes).tables['Work Entries']!;

    expect((sheet.rows[1][0]!.value as TextCellValue).value.text, 'User');
    expect(
      (sheet.rows[2][0]!.value as TextCellValue).value.text,
      'Employer / company',
    );
    expect(
      (sheet.rows[2][1]!.value as TextCellValue).value.text,
      'Example Company Ltd',
    );
    expect((sheet.rows[3][0]!.value as TextCellValue).value.text, 'Period');
  });

  test('uses field-specific numeric and GBP currency cell formats', () {
    WorkEntry entry(
      String id,
      String finishTime,
      double hours,
      double allowance,
    ) => WorkEntry(
      id: id,
      date: DateTime(2026, 7, 9),
      siteName: 'Test Job',
      startTime: '08:00',
      finishTime: finishTime,
      breakMinutes: 30,
      workLocation: 'Away',
      hourlyRateUsed: 20,
      dailyAllowance: allowance,
      jobUplift: 0,
      totalHours: hours,
      wages: hours * 20,
      totalPay: hours * 20 + allowance,
      notes: '',
    );

    final bytes = ExcelExportService.buildWorkbook([
      entry('whole', '16:30', 8, 20),
      entry('half', '17:00', 8.5, 20),
      entry('quarter', '15:45', 7.25, 20),
    ]);
    final sheet = Excel.decodeBytes(bytes).tables['Work Entries']!;

    expect(sheet.rows[5][8]!.value, const IntCellValue(8));
    expect(sheet.rows[6][8]!.value, const DoubleCellValue(8.5));
    expect(sheet.rows[7][8]!.value, const DoubleCellValue(7.25));
    expect(
      sheet.rows[5][8]!.cellStyle?.numberFormat.formatCode,
      excelFlexibleNumberFormat,
    );
    expect(
      sheet.rows[5][7]!.cellStyle?.numberFormat.formatCode,
      excelWholeNumberFormat,
    );
    expect(
      sheet.rows[5][11]!.cellStyle?.numberFormat.formatCode,
      CurrencyFormatter.excelNumberFormat(defaultCurrency),
    );
    expect(sheet.rows[5][11]!.value, const IntCellValue(20));

    Data? summaryCell(String label) {
      final row = sheet.rows.firstWhere(
        (row) =>
            row.isNotEmpty &&
            row.first?.value is TextCellValue &&
            (row.first!.value as TextCellValue).value.text == label,
      );
      return row[1];
    }

    for (final label in ['Days recorded', 'Holidays', 'Unpaid days off']) {
      final cell = summaryCell(label)!;
      expect(cell.value, isNot(isA<TextCellValue>()));
      expect(cell.value, anyOf(isA<IntCellValue>(), isA<DoubleCellValue>()));
      expect(cell.cellStyle?.numberFormat.formatCode, excelWholeNumberFormat);
    }

    expect(
      summaryCell('Total hours')!.cellStyle?.numberFormat.formatCode,
      excelFlexibleNumberFormat,
    );
    expect(
      summaryCell('Gross pay')!.cellStyle?.numberFormat.formatCode,
      CurrencyFormatter.excelNumberFormat(defaultCurrency),
    );
  });

  test('Excel number format constants do not end with a decimal point', () {
    expect(excelWholeNumberFormat, '0');
    expect(excelFlexibleNumberFormat, '0.##');
    expect([
      excelWholeNumberFormat,
      excelFlexibleNumberFormat,
      CurrencyFormatter.excelNumberFormat(defaultCurrency),
    ], everyElement(isNot(endsWith('.'))));
  });
  test('Excel signature section appears only when enabled', () {
    final entry = WorkEntry(
      id: 'signature-test',
      date: DateTime(2026, 7, 9),
      siteName: 'Test Job',
      startTime: '08:00',
      finishTime: '16:00',
      breakMinutes: 0,
      hourlyRateUsed: 20,
      dailyAllowance: 0,
      jobUplift: 0,
      totalHours: 8,
      wages: 160,
      totalPay: 160,
      notes: '',
    );

    List<String> labels(bool includeSignature) {
      final bytes = ExcelExportService.buildWorkbook([
        entry,
      ], includeSignatureLine: includeSignature);
      final sheet = Excel.decodeBytes(bytes).tables['Work Entries']!;
      return sheet.rows
          .where((row) => row.isNotEmpty && row.first?.value is TextCellValue)
          .map(
            (row) => (row.first!.value as TextCellValue).value.text.toString(),
          )
          .toList();
    }

    final withoutSignature = labels(false);
    final withSignature = labels(true);

    expect(withoutSignature, isNot(contains('Employee signature')));
    expect(withoutSignature, isNot(contains('Signature date')));

    expect(withSignature, contains('Employee signature'));
    expect(withSignature, contains('Signature date'));
    expect(withSignature, contains('Net pay'));
    final sheet = Excel.decodeBytes(
      ExcelExportService.buildWorkbook([entry], includeSignatureLine: true),
    ).tables['Work Entries']!;
    for (final label in ['Employee signature', 'Signature date']) {
      final row = sheet.rows.singleWhere(
        (row) => row.isNotEmpty && row.first?.value.toString() == label,
      );
      expect(row[1]?.value?.toString() ?? '', isEmpty);
    }
  });
}
