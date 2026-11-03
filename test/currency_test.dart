import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briska/src/csv_export_service.dart';
import 'package:briska/src/currency.dart';
import 'package:briska/src/excel_export_service.dart';
import 'package:briska/src/models.dart';

void main() {
  final entry = WorkEntry(
    id: 'currency',
    date: DateTime(2026, 7, 18),
    siteName: 'Site',
    startTime: '08:00',
    finishTime: '16:00',
    breakMinutes: 0,
    workLocation: 'Home',
    hourlyRateUsed: 20,
    dailyAllowance: 0,
    jobUplift: 0,
    totalHours: 8,
    wages: 160,
    totalPay: 160,
    notes: '',
  );

  test('formats supported currencies with locale and decimal rules', () {
    expect(
      CurrencyFormatter.format(1234.5, CurrencyCatalog.byCode('GBP')),
      '£1,234.50',
    );
    expect(
      CurrencyFormatter.format(1234.5, CurrencyCatalog.byCode('USD')),
      r'$1,234.50',
    );
    expect(
      CurrencyFormatter.format(1234.5, CurrencyCatalog.byCode('EUR')),
      contains('1.234,50'),
    );
    expect(
      CurrencyFormatter.format(1234.5, CurrencyCatalog.byCode('DKK')),
      contains('1.234,50'),
    );
    expect(
      CurrencyFormatter.format(1234.5, CurrencyCatalog.byCode('JPY')),
      '¥1,235',
    );
  });

  test('resolves device locales and falls back safely to GBP', () {
    expect(CurrencyCatalog.fromLocale('en_GB').code, 'GBP');
    expect(CurrencyCatalog.fromLocale('da-DK').code, 'DKK');
    expect(CurrencyCatalog.fromLocale('unknown').code, 'GBP');
  });

  test('persists the complete currency setting', () {
    final settings = AppSettings(currency: CurrencyCatalog.byCode('EUR'));
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.currency.code, 'EUR');
    expect(restored.currency.symbol, '€');
    expect(restored.currency.locale, 'de_DE');
    expect(restored.currency.decimalDigits, 2);
  });

  test('changing currency does not convert stored numeric wage values', () {
    const original = AppSettings(homeHourlyRate: 100);
    final changed = original.copyWith(currency: CurrencyCatalog.byCode('EUR'));
    expect(changed.homeHourlyRate, 100);
    expect(
      CurrencyFormatter.format(changed.homeHourlyRate, changed.currency),
      contains('100,00'),
    );
  });

  test('legacy settings receive the safe GBP model fallback', () {
    expect(
      AppSettings.fromJson({'fullName': 'Existing'}).currency,
      defaultCurrency,
    );
  });

  test('Excel keeps money numeric and applies selected currency format', () {
    final currency = CurrencyCatalog.byCode('EUR');
    final bytes = ExcelExportService.buildWorkbook([entry], currency: currency);
    final sheet = Excel.decodeBytes(bytes).tables['Work Entries']!;
    expect(sheet.rows[5][13]!.value, const IntCellValue(160));
    expect(
      sheet.rows[5][13]!.cellStyle?.numberFormat.formatCode,
      CurrencyFormatter.excelNumberFormat(currency),
    );
  });

  test('CSV keeps money numeric and adds the currency code to headings', () {
    final bytes = CsvExportService.buildCsv([
      entry,
    ], currency: CurrencyCatalog.byCode('EUR'));
    final csv = utf8.decode(bytes.skip(3).toList());
    expect(csv, startsWith('Date,Site/job,Day type'));
    expect(csv, contains('Hourly rate (EUR)'));
    expect(csv, contains(',20.00,160.00,0.00,0.00,160.00,0.00,,160.00,'));
    expect(csv, isNot(contains('€160')));
  });

  test('export records preserve their historical currency identity', () {
    final record = ExportedFileRecord(
      id: '1',
      fileName: 'report.pdf',
      fileType: 'PDF',
      filePath: '',
      exportedAt: DateTime(2026, 7, 18),
      periodLabel: 'July',
      workDays: 1,
      totalHours: 8,
      totalPay: 160,
      currencyCode: 'EUR',
      currencySymbol: '€',
    );
    final restored = ExportedFileRecord.fromJson(
      jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>,
    );
    expect(restored.currencyCode, 'EUR');
    expect(restored.currencySymbol, '€');
    expect(restored.totalPay, 160);
  });
}
