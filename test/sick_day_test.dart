import 'dart:convert';

import 'package:briska/src/backup_service.dart';
import 'package:briska/src/csv_export_service.dart';
import 'package:briska/src/excel_export_service.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/work_calculator.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

WorkEntry sickDay({required bool paid, double uplift = 0}) {
  final result = WorkCalculator.calculate(
    startTime: '',
    finishTime: '',
    breakMinutes: 0,
    hourlyRate: paid ? 25 : 0,
    dailyAllowance: 0,
    jobUplift: uplift,
    entryType: 'SickDay',
    isPaidSickDay: paid,
  );
  return WorkEntry(
    id: paid ? 'paid' : 'unpaid',
    entryType: 'SickDay',
    isPaidSickDay: paid,
    date: DateTime(2026, 8, paid ? 1 : 2),
    siteName: '',
    startTime: '',
    finishTime: '',
    breakMinutes: 0,
    hourlyRateUsed: paid ? 25 : 0,
    dailyAllowance: 0,
    jobUplift: uplift,
    totalHours: result.totalHours,
    wages: result.wages,
    totalPay: result.totalPay,
    notes: 'Rest',
  );
}

void main() {
  test('paid and unpaid sick-day calculations follow pay rules', () {
    final paid = WorkCalculator.recalculateEntry(
      sickDay(paid: true, uplift: 10),
    );
    final unpaid = WorkCalculator.recalculateEntry(
      sickDay(paid: false, uplift: 10),
    );

    expect(
      (paid.totalHours, paid.hourlyRateUsed, paid.wages, paid.totalPay),
      (8, 25, 200, 210),
    );
    expect(
      (unpaid.totalHours, unpaid.hourlyRateUsed, unpaid.wages, unpaid.totalPay),
      (0, 0, 0, 10),
    );
  });

  test('editing paid status recalculates from paid to unpaid and back', () {
    final paid = sickDay(paid: true, uplift: 5);
    final unpaidEdit = WorkEntry.fromJson({
      ...paid.toJson(),
      'isPaidSickDay': false,
      'hourlyRateUsed': 0,
    });
    final paidEdit = WorkEntry.fromJson({
      ...unpaidEdit.toJson(),
      'isPaidSickDay': true,
      'hourlyRateUsed': 25,
    });

    expect(WorkCalculator.recalculateEntry(unpaidEdit).totalPay, 5);
    expect(WorkCalculator.recalculateEntry(paidEdit).totalPay, 205);
  });

  test('summary counts sick days and includes paid hours and all uplifts', () {
    final summary = WorkCalculator.summarize([
      sickDay(paid: true, uplift: 3),
      sickDay(paid: false, uplift: 7),
    ]);

    expect(
      (summary.sickDays, summary.paidSickDays, summary.unpaidSickDays),
      (2, 1, 1),
    );
    expect(
      (
        summary.totalHours,
        summary.totalWages,
        summary.totalJobUplift,
        summary.totalExpectedPay,
      ),
      (8, 200, 10, 210),
    );
  });

  test('CSV and Excel distinguish paid and unpaid sick days', () {
    final entries = [sickDay(paid: true), sickDay(paid: false, uplift: 4)];
    final csv = utf8.decode(
      CsvExportService.buildCsv(entries),
      allowMalformed: true,
    );
    expect(csv, contains('Paid Sick Day'));
    expect(csv, contains('Unpaid Sick Day'));

    final workbook = Excel.decodeBytes(
      ExcelExportService.buildWorkbook(entries),
    );
    final values = workbook.tables['Work Entries']!.rows
        .expand((row) => row)
        .whereType<Data?>()
        .map((cell) => cell?.value.toString() ?? '')
        .join(' ');
    expect(values, contains('Paid Sick Day'));
    expect(values, contains('Unpaid Sick Day'));
  });

  test('backup restores sick status and older entries default safely', () {
    Map<String, Object?> backupFor(Map<String, Object?> entry) => {
      'backupVersion': 1,
      'createdAt': '2026-08-06T10:00:00.000',
      'appName': 'Briska',
      'settings': const AppSettings().toJson(),
      'workEntries': [entry],
      'exportRecords': <Object?>[],
    };

    final restored = BriskaBackupService.previewJson(
      backupFor(sickDay(paid: true).toJson()),
    );
    expect(restored.data.workEntries.single.isPaidSickDay, isTrue);

    final legacy = sickDay(paid: false).toJson()
      ..remove('isPaidSickDay')
      ..['entryType'] = 'WorkDay'
      ..['siteName'] = 'Legacy site'
      ..['startTime'] = '08:00'
      ..['finishTime'] = '16:00';
    final oldRestored = BriskaBackupService.previewJson(backupFor(legacy));
    expect(oldRestored.data.workEntries.single.isPaidSickDay, isFalse);
  });
}
