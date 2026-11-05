import 'dart:convert';
import 'package:briska/src/models.dart';
import 'package:briska/src/pdf_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

WorkEntry recorded(String type, double hours, {bool paid = true}) => WorkEntry(
  id: '$type-$paid',
  entryType: type,
  date: DateTime(2026, 7, 1),
  siteName: 'Historic',
  startTime: '08:00',
  finishTime: '09:00',
  breakMinutes: 120,
  hourlyRateUsed: 999,
  dailyAllowance: 3,
  jobUplift: 4,
  totalHours: hours,
  wages: 100,
  totalPay: 107,
  deductionAmount: 7,
  notes: '',
  isPaidBankHoliday: paid,
  isPaidSickDay: paid,
);

void main() {
  test(
    'PDF metrics distinguish all recorded hours without recalculating earnings',
    () {
      final entries = [
        recorded('WorkDay', 6.25),
        recorded('WorkDay', 3.75),
        recorded('Holiday', 7.5),
        recorded('bankHoliday', 8),
        recorded('BankHoliday', 4, paid: false),
        recorded('SickDay', 8),
        recorded('SickDay', 2, paid: false),
        recorded('UnpaidDayOff', 1),
      ];
      final before = jsonEncode(entries.map((e) => e.toJson()).toList());
      final totals = PdfExportService.calculateTotals(entries);
      expect(totals.workDays, 2);
      expect(totals.hoursWorked, 10);
      expect(totals.averageHours, 5);
      expect(totals.holidayHours, 7.5);
      expect(totals.bankHolidayHours, 12);
      expect(totals.totalRecordedHours, 40.5);
      expect(totals.paidBankHolidayDays, 1);
      expect(totals.unpaidBankHolidayDays, 1);
      expect(totals.primaryPay, 800);
      expect(totals.secondaryPay, 0);
      expect(totals.allowances, 24);
      expect(totals.uplifts, 32);
      expect(totals.grossTotal, 856);
      expect(totals.deductions, 56);
      expect(totals.netTotal, 800);
      expect(jsonEncode(entries.map((e) => e.toJson()).toList()), before);
    },
  );
  for (final type in [
    'Holiday',
    'bankHoliday',
    'BankHoliday',
    'SickDay',
    'UnpaidDayOff',
  ]) {
    for (final paid in [true, false]) {
      test('$type paid=$paid contributes recorded hours but no work hours', () {
        final totals = PdfExportService.calculateTotals([
          recorded(type, 7.5, paid: paid),
        ]);
        expect(totals.hoursWorked, 0);
        expect(totals.averageHours, 0);
        expect(totals.totalRecordedHours, 7.5);
        expect(totals.holidayHours, type == 'Holiday' ? 7.5 : 0);
        expect(
          totals.bankHolidayHours,
          type.toLowerCase() == 'bankholiday' ? 7.5 : 0,
        );
        expect(totals.grossTotal, 107);
      });
    }
  }
  test('empty PDF report has zero hours and average', () {
    final totals = PdfExportService.calculateTotals([]);
    expect(totals.hoursWorked, 0);
    expect(totals.averageHours, 0);
    expect(totals.holidayHours, 0);
    expect(totals.bankHolidayHours, 0);
    expect(totals.totalRecordedHours, 0);
  });
}
