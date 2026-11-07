import 'dart:convert';

import 'package:briska/src/csv_export_service.dart';
import 'package:briska/src/excel_export_service.dart';
import 'package:briska/src/models.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final entry = WorkEntry(
    id: 'privacy-test',
    date: DateTime(2026, 7, 14),
    siteName: 'Test Site',
    startTime: '08:00',
    finishTime: '16:00',
    breakMinutes: 0,
    hourlyRateUsed: 20,
    dailyAllowance: 0,
    jobUplift: 0,
    totalHours: 8,
    wages: 160,
    totalPay: 160,
    notes: 'PRIVATE_NOTES_DO_NOT_EXPORT',
  );

  test('CSV excludes private notes when disabled', () {
    final csv = utf8.decode(
      CsvExportService.buildCsv([entry], includeNotes: false),
    );

    expect(csv, isNot(contains('PRIVATE_NOTES_DO_NOT_EXPORT')));
    expect(csv, contains('Notes'));
    expect(csv, contains('Test Site'));
  });

  test('CSV includes notes when explicitly enabled', () {
    final csv = utf8.decode(
      CsvExportService.buildCsv([entry], includeNotes: true),
    );

    expect(csv, contains('PRIVATE_NOTES_DO_NOT_EXPORT'));
  });

  test('Excel excludes private notes when disabled', () {
    final bytes = ExcelExportService.buildWorkbook([
      entry,
    ], includeNotes: false);

    final sheet = Excel.decodeBytes(bytes).tables['Work Entries']!;
    final content = sheet.rows
        .expand((row) => row)
        .map((cell) => cell?.value.toString() ?? '')
        .join(' ');

    expect(content, isNot(contains('PRIVATE_NOTES_DO_NOT_EXPORT')));
    expect(content, contains('Notes'));
    expect(content, contains('Test Site'));
  });

  test('Excel includes notes when explicitly enabled', () {
    final bytes = ExcelExportService.buildWorkbook([entry], includeNotes: true);

    final sheet = Excel.decodeBytes(bytes).tables['Work Entries']!;
    final content = sheet.rows
        .expand((row) => row)
        .map((cell) => cell?.value.toString() ?? '')
        .join(' ');

    expect(content, contains('PRIVATE_NOTES_DO_NOT_EXPORT'));
  });
}
