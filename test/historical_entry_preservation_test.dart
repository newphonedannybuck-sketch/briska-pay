import 'dart:convert';

import 'package:briska/main.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/csv_export_service.dart';
import 'package:briska/src/excel_export_service.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/pdf_export_service.dart';
import 'package:briska/src/work_calculator.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkEntry historicalEntry({String type = 'WorkDay', bool paid = true}) =>
    WorkEntry(
      id: '$type-$paid',
      entryType: type,
      date: DateTime.now(),
      siteName: 'Historical Site',
      startTime: '08:00',
      finishTime: '09:00',
      breakMinutes: 120,
      hourlyRateUsed: 20,
      dailyAllowance: 10,
      jobUplift: 5,
      totalHours: 6.25,
      wages: 123.45,
      totalPay: 138.45,
      deductionAmount: 10,
      notes: '',
      isPaidSickDay: paid,
      isPaidBankHoliday: paid,
    );

void main() {
  test(
    'summary aggregates recorded values and preserves entries and order',
    () {
      final entries = [
        historicalEntry(),
        historicalEntry(type: 'Holiday'),
        historicalEntry(type: 'bankHoliday'),
        historicalEntry(type: 'bankHoliday', paid: false),
        historicalEntry(type: 'SickDay'),
        historicalEntry(type: 'SickDay', paid: false),
        historicalEntry(type: 'UnpaidDayOff'),
      ];
      expect(WorkCalculator.recalculateEntry(entries.first).totalPay, 0);
      final summary = WorkCalculator.summarize(entries);
      for (var index = 0; index < entries.length; index++) {
        expect(summary.entries[index], same(entries[index]));
        expect(summary.entries[index].totalHours, 6.25);
        expect(summary.entries[index].wages, 123.45);
        expect(summary.entries[index].totalPay, 138.45);
        expect(summary.entries[index].netPay, closeTo(128.45, 0.000001));
      }
      expect(summary.totalHours, 43.75);
      expect(summary.totalWages, closeTo(864.15, 0.000001));
      expect(summary.totalExpectedPay, closeTo(969.15, 0.000001));
      expect(summary.totalNetPay, closeTo(899.15, 0.000001));
      expect(summary.totalDeductions, 70);
      expect(summary.totalDailyAllowance, 70);
      expect(summary.totalJobUplift, 35);
      expect(summary.holidayDays, 1);
      expect(summary.bankHolidayDays, 2);
      expect(summary.paidBankHolidayDays, 1);
      expect(summary.unpaidBankHolidayDays, 1);
      expect(summary.sickDays, 2);
      expect(summary.paidSickDays, 1);
      expect(summary.unpaidSickDays, 1);
      expect(summary.unpaidDays, 1);
    },
  );

  test('CSV, Excel and PDF report totals preserve recorded earnings', () {
    final entries = [historicalEntry()];
    final csv = utf8.decode(CsvExportService.buildCsv(entries));
    final row = csv.trim().split('\r\n').last.split(',');
    expect(row[8], '6.25');
    expect(row[10], '123.45');
    expect(row[13], '138.45');
    expect(row[16], '128.45');

    final sheet = Excel.decodeBytes(
      ExcelExportService.buildWorkbook(entries),
    ).tables['Work Entries']!;
    expect(sheet.rows[5][8]!.value, const DoubleCellValue(6.25));
    expect(sheet.rows[5][10]!.value, const DoubleCellValue(123.45));
    expect(sheet.rows[5][13]!.value, const DoubleCellValue(138.45));
    final grossRow = sheet.rows.firstWhere(
      (row) => row.isNotEmpty && row.first?.value.toString() == 'Gross pay',
    );
    expect(grossRow[1]!.value, const DoubleCellValue(138.45));

    final totals = PdfExportService.calculateTotals(
      WorkCalculator.summarize(entries).entries,
    );
    expect(totals.hoursWorked, 6.25);
    expect(totals.primaryPay, 123.45);
    expect(totals.grossTotal, 138.45);
    expect(totals.netTotal, closeTo(128.45, 0.000001));
  });

  testWidgets(
    'initial entries retain earnings in Recent Activity and details',
    (tester) async {
      final entry = historicalEntry();
      await tester.pumpWidget(BriskaApp(initialEntries: [entry]));
      await tester.pumpAndSettle();
      final recent = find.byKey(ValueKey('recent-activity-${entry.id}'));
      await tester.ensureVisible(recent);
      expect(
        find.descendant(of: recent, matching: find.text('£138.45')),
        findsOneWidget,
      );
      await tester.tap(recent);
      await tester.pumpAndSettle();
      expect(find.text('Entry Details'), findsOneWidget);
      expect(find.text('£138.45'), findsWidgets);
      expect(find.text('£123.45'), findsWidgets);
      expect(find.text('£128.45'), findsWidgets);
      expect(find.text('6.25h'), findsWidgets);
    },
  );

  testWidgets('entry card displays stored hours, base pay and gross pay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkEntryCard(entry: historicalEntry())),
      ),
    );
    expect(find.text('£138.45'), findsOneWidget);
    expect(find.textContaining('123.45', findRichText: true), findsOneWidget);
    expect(find.text('6.25h'), findsOneWidget);
  });

  testWidgets('calendar summary retains earnings and opens supplied entry', (
    tester,
  ) async {
    final entry = historicalEntry();
    WorkEntry? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MonthlyCalendarSection(
              entries: [entry],
              settings: const AppSettings(),
              onEditEntry: (value) => opened = value,
              onAddDate: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('£138.45'), findsWidgets);
    expect(find.text('6.25h · Standard'), findsOneWidget);
    await tester.ensureVisible(find.text('Historical Site'));
    await tester.tap(find.text('Historical Site'));
    expect(opened, same(entry));
  });

  testWidgets('Reports displays recorded earnings despite invalid inputs', (
    tester,
  ) async {
    await tester.pumpWidget(BriskaApp(initialEntries: [historicalEntry()]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports').last);
    await tester.pumpAndSettle();
    expect(find.text('£138.45'), findsWidgets);
    expect(find.text('6.25h'), findsWidgets);
  });
}
