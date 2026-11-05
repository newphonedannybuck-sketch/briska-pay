import 'dart:convert';

import 'package:briska/src/csv_export_service.dart';
import 'package:briska/src/backup_service.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/pay_schedule.dart';
import 'package:briska/src/pdf_export_service.dart';
import 'package:briska/src/work_calculator.dart';
import 'package:briska/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkEntry _entry({
  EntryType type = EntryType.workDay,
  bool paidBankHoliday = true,
  double deduction = 0,
  String reason = '',
  String start = '22:00',
  String finish = '06:00',
  int breakMinutes = 0,
}) {
  final calculation = WorkCalculator.calculate(
    startTime: start,
    finishTime: finish,
    breakMinutes: breakMinutes,
    hourlyRate: 20,
    dailyAllowance: 10,
    jobUplift: 5,
    deductionAmount: deduction,
    entryType: type.storageValue,
    isPaidBankHoliday: paidBankHoliday,
    holidayHours: paidBankHoliday ? 8 : 0,
  );
  return WorkEntry(
    id: 'entry',
    entryType: type,
    date: DateTime(2026, 9, 10),
    siteName: 'Night job',
    startTime: start,
    finishTime: finish,
    breakMinutes: breakMinutes,
    hourlyRateUsed: 20,
    dailyAllowance: 10,
    jobUplift: 5,
    totalHours: calculation.totalHours,
    wages: calculation.wages,
    totalPay: calculation.totalPay,
    notes: '',
    isPaidBankHoliday: paidBankHoliday,
    deductionAmount: deduction,
    deductionReason: reason,
  );
}

void main() {
  group('Bank Holiday day type and deduction persistence', () {
    test('legacy entries default safely', () {
      final legacy = _entry().toJson()
        ..remove('isBankHoliday')
        ..remove('deductionAmount')
        ..remove('deductionReason');
      final restored = WorkEntry.fromJson(legacy);
      expect(restored.type, EntryType.workDay);
      expect(restored.deductionAmount, 0);
      expect(restored.deductionReason, isEmpty);
    });

    test('new fields round trip without changing gross pay', () {
      final entry = _entry(
        type: EntryType.bankHoliday,
        deduction: 50,
        reason: 'Advance',
      );
      final restored = WorkEntry.fromJson(entry.toJson());
      expect(restored.type, EntryType.bankHoliday);
      expect(restored.isPaidBankHoliday, isTrue);
      expect(restored.deductionReason, 'Advance');
      expect(restored.grossPay, 165);
      expect(restored.netPay, 115);
      expect(restored.toJson(), isNot(contains('isBankHoliday')));
    });

    test(
      'legacy flag migrates safe non-work types but preserves worked shifts',
      () {
        final holiday = _entry(type: EntryType.holiday).toJson()
          ..['isBankHoliday'] = true;
        final unpaid = _entry(type: EntryType.unpaidDayOff).toJson()
          ..['isBankHoliday'] = true;
        final worked = _entry().toJson()..['isBankHoliday'] = true;
        final migratedHoliday = WorkEntry.fromJson(holiday);
        final migratedUnpaid = WorkEntry.fromJson(unpaid);
        final migratedWork = WorkEntry.fromJson(worked);
        expect(migratedHoliday.type, EntryType.bankHoliday);
        expect(migratedHoliday.isPaidBankHoliday, isTrue);
        expect(migratedUnpaid.type, EntryType.bankHoliday);
        expect(migratedUnpaid.isPaidBankHoliday, isFalse);
        expect(migratedWork.type, EntryType.workDay);
        expect(migratedWork.startTime, '22:00');
        expect(migratedWork.finishTime, '06:00');
        expect(migratedWork.totalHours, 8);
      },
    );

    test('backup restore accepts current type and short-lived flag data', () {
      Map<String, Object?> backupFor(Map<String, Object?> entry) => {
        'backupVersion': 1,
        'createdAt': '2026-08-31T10:00:00.000',
        'appName': 'Briska',
        'settings': const AppSettings().toJson(),
        'workEntries': [entry],
        'exportRecords': <Object?>[],
      };
      final current = BriskaBackupService.previewJson(
        backupFor(_entry(type: EntryType.bankHoliday).toJson()),
      ).data.workEntries.single;
      expect(current.type, EntryType.bankHoliday);
      expect(current.isPaidBankHoliday, isTrue);

      final flaggedWork = _entry().toJson()..['isBankHoliday'] = true;
      final legacy = BriskaBackupService.previewJson(
        backupFor(flaggedWork),
      ).data.workEntries.single;
      expect(legacy.type, EntryType.workDay);
      expect(legacy.totalHours, 8);
    });
  });

  test('paid and unpaid Bank Holidays use central calculation rules', () {
    final paid = _entry(type: EntryType.bankHoliday, deduction: 50);
    final unpaid = _entry(
      type: EntryType.bankHoliday,
      paidBankHoliday: false,
      deduction: 2,
    );
    expect(paid.totalHours, 8);
    expect(paid.wages, 160);
    expect(paid.grossPay, 165);
    expect(paid.netPay, 115);
    expect(unpaid.totalHours, 0);
    expect(unpaid.wages, 0);
    expect(unpaid.grossPay, 5);
    expect(unpaid.netPay, 3);
  });

  testWidgets('Bank Holiday is a Day Type and no flag toggle remains', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.tap(find.byTooltip('Add Day'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-type-bankHoliday')), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Bank Holiday'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('day-type-bankHoliday')));
    await tester.pumpAndSettle();
    expect(find.text('Pay Status'), findsOneWidget);
    expect(find.text('Paid'), findsNWidgets(2));
    expect(find.text('Site/job name'), findsNothing);
    expect(find.text('Start time'), findsNothing);
  });

  group('overnight duration', () {
    double hours(String start, String finish, [int breakMinutes = 0]) =>
        WorkCalculator.calculate(
          startTime: start,
          finishTime: finish,
          breakMinutes: breakMinutes,
          hourlyRate: 1,
          dailyAllowance: 0,
          jobUplift: 0,
        ).totalHours;

    test('common overnight spans calculate on the starting entry', () {
      expect(hours('22:00', '06:00'), 8);
      expect(hours('20:30', '04:30'), 8);
      expect(hours('23:45', '00:15'), .5);
      expect(hours('22:00', '06:00', 30), 7.5);
      expect(_entry().date, DateTime(2026, 9, 10));
    });

    test('equal times and excessive spans are rejected', () {
      final equal = WorkCalculator.calculate(
        startTime: '08:00',
        finishTime: '08:00',
        breakMinutes: 0,
        hourlyRate: 1,
        dailyAllowance: 0,
        jobUplift: 0,
      );
      expect(equal.isValid, isFalse);
      expect(hours('08:00', '07:00'), 0);
    });
  });

  test('summary and exports distinguish gross, deductions and net', () {
    final entry = _entry(
      type: EntryType.bankHoliday,
      deduction: 50,
      reason: 'Advance',
    );
    final summary = WorkCalculator.summarize([entry]);
    expect(summary.totalJobUplift, 5);
    expect(summary.totalExpectedPay, 165);
    expect(summary.totalDeductions, 50);
    expect(summary.totalNetPay, 115);

    final csv = utf8.decode(
      CsvExportService.buildCsv([entry]).skip(3).toList(),
    );
    expect(csv, contains('Bank Holiday'));
    expect(csv, contains('Pay status'));
    expect(csv, contains('Deduction reason'));
    expect(csv, contains('Advance'));
    expect(csv, contains('Net pay'));

    final totals = PdfExportService.calculateTotals([entry]);
    expect(totals.grossTotal, 165);
    expect(totals.deductions, 50);
    expect(totals.netTotal, 115);
  });

  test('previous periods reuse the central resolver', () {
    const settings = AppSettings(
      payFrequency: weeklyPayFrequency,
      payPeriodAnchorDate: '2026-08-24',
    );
    final current = getCurrentPayPeriodForSettings(
      date: DateTime(2026, 8, 30),
      settings: settings,
    );
    final previous = getCurrentPayPeriodForSettings(
      date: current.start.subtract(const Duration(days: 1)),
      settings: settings,
    );
    expect(current.start, DateTime(2026, 8, 24));
    expect(previous.start, DateTime(2026, 8, 17));
    expect(previous.end, DateTime(2026, 8, 23));
  });
}
