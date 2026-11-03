import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:briska/src/csv_export_service.dart';
import 'package:briska/src/currency.dart';
import 'package:briska/src/export_formats.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/pdf_export_service.dart';

void main() {
  final entries = [
    WorkEntry(
      id: '1',
      date: DateTime(2026, 7, 9),
      siteName: 'Station, Road',
      startTime: '08:00',
      finishTime: '17:00',
      breakMinutes: 30,
      workLocation: 'Away',
      hourlyRateUsed: 20,
      dailyAllowance: 10,
      jobUplift: 25,
      totalHours: 8.5,
      wages: 170,
      totalPay: 205,
      notes: 'Completed "snagging"',
    ),
    WorkEntry(
      id: '2',
      entryType: 'Holiday',
      date: DateTime(2026, 7, 10),
      siteName: '',
      startTime: '',
      finishTime: '',
      breakMinutes: 0,
      workLocation: 'Home',
      hourlyRateUsed: 20,
      dailyAllowance: 0,
      jobUplift: 0,
      totalHours: 8,
      wages: 160,
      totalPay: 160,
      notes: '',
    ),
    WorkEntry(
      id: '3',
      entryType: 'UnpaidDayOff',
      date: DateTime(2026, 7, 11),
      siteName: '',
      startTime: '',
      finishTime: '',
      breakMinutes: 0,
      workLocation: 'Home',
      hourlyRateUsed: 0,
      dailyAllowance: 0,
      jobUplift: 5,
      totalHours: 0,
      wages: 0,
      totalPay: 5,
      notes: '',
    ),
  ];

  test('builds professional filenames for all export formats', () {
    expect(
      ExportFileNamer.buildFileName(
        fullName: 'Danny Buck',
        companyName: '',
        periodLabel: 'July 2026',
        fileNameLabel: 'July 2026',
        format: ExportFormat.excel,
      ),
      'Briska_Danny_Buck_July_2026.xlsx',
    );
    expect(
      ExportFileNamer.buildFileName(
        fullName: 'Danny Buck',
        companyName: '',
        periodLabel: 'July 2026',
        fileNameLabel: 'July 2026',
        format: ExportFormat.pdfTimesheet,
      ),
      'Briska_Danny_Buck_July_2026_Timesheet.pdf',
    );
    expect(
      ExportFileNamer.buildFileName(
        fullName: 'Danny Buck',
        companyName: '',
        periodLabel: 'July 2026',
        fileNameLabel: 'July 2026',
        format: ExportFormat.pdfSummary,
      ),
      'Briska_Danny_Buck_July_2026_Summary.pdf',
    );
    expect(
      ExportFileNamer.buildFileName(
        fullName: 'Danny Buck',
        companyName: 'CoolCanvas',
        periodLabel: 'July 2026',
        fileNameLabel: 'July 2026',
        format: ExportFormat.csv,
      ),
      'Briska_CoolCanvas_Danny_Buck_July_2026.csv',
    );
  });

  test(
    'builds CSV with headings, escaped values and spreadsheet-friendly BOM',
    () {
      final bytes = CsvExportService.buildCsv(entries);
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);

      final csv = utf8.decode(bytes.skip(3).toList());
      expect(csv, startsWith('Date,Site/job,Day type'));
      expect(csv, contains('2026-07-09,"Station, Road",Work day'));
      expect(csv, contains('"Completed ""snagging"""'));
      expect(csv, contains('8.5,20.00,170.00,10.00,25.00,205.00'));
    },
  );

  test('calculates PDF summary totals without changing calculations', () {
    final totals = PdfExportService.calculateTotals(entries);

    expect(totals.workDays, 1);
    expect(totals.holidayDays, 1);
    expect(totals.unpaidDays, 1);
    expect(totals.hoursWorked, 16.5);
    expect(totals.averageHours, 16.5);
    expect(totals.homePay, 160);
    expect(totals.awayPay, 170);
    expect(totals.allowances, 10);
    expect(totals.uplifts, 30);
    expect(totals.grossTotal, 370);
  });

  test('builds valid PDF timesheet and summary bytes', () async {
    final logo = File('assets/branding/briska-bp-in-app.png').readAsBytesSync();
    final regularFont = File(
      'assets/fonts/Poppins-Regular.ttf',
    ).readAsBytesSync();
    final boldFont = File(
      'assets/fonts/Poppins-SemiBold.ttf',
    ).readAsBytesSync();

    final timesheet = await PdfExportService.buildTimesheetPdf(
      entries,
      fullName: 'Danny Buck',
      companyName: 'CoolCanvas',
      periodLabel: 'July 2026',
      generatedAt: DateTime(2026, 7, 31),
      logoBytes: logo,
      regularFontBytes: regularFont,
      boldFontBytes: boldFont,
    );
    final summary = await PdfExportService.buildSummaryPdf(
      entries,
      fullName: 'Danny Buck',
      companyName: 'CoolCanvas',
      periodLabel: 'July 2026',
      generatedAt: DateTime(2026, 7, 31),
      logoBytes: logo,
      regularFontBytes: regularFont,
      boldFontBytes: boldFont,
    );

    expect(ascii.decode(timesheet.take(4).toList()), '%PDF');
    expect(ascii.decode(summary.take(4).toList()), '%PDF');
    expect(timesheet.length, greaterThan(1000));
    expect(summary.length, greaterThan(1000));
  });

  test('builds Unicode currency PDF reports', () async {
    final logo = File('assets/branding/briska-bp-in-app.png').readAsBytesSync();
    final regularFont = File(
      'assets/fonts/Poppins-Regular.ttf',
    ).readAsBytesSync();
    final boldFont = File(
      'assets/fonts/Poppins-SemiBold.ttf',
    ).readAsBytesSync();

    for (final code in ['EUR', 'DKK', 'PLN', 'INR', 'JPY']) {
      final bytes = await PdfExportService.buildSummaryPdf(
        entries,
        fullName: 'Danny Buck',
        companyName: 'CoolCanvas',
        periodLabel: 'July 2026',
        generatedAt: DateTime(2026, 7, 31),
        logoBytes: logo,
        regularFontBytes: regularFont,
        boldFontBytes: boldFont,
        currency: CurrencyCatalog.byCode(code),
      );
      expect(ascii.decode(bytes.take(4).toList()), '%PDF', reason: code);
      expect(bytes.length, greaterThan(1000), reason: code);
    }
  });
}
