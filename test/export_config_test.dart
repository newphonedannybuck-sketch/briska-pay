import 'package:briska/features/export/models/export_config.dart';
import 'package:briska/features/export/services/export_filename_service.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/export_formats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const settings = AppSettings(
    payFrequency: 'Calendar monthly',
    onboardingCompleted: true,
  );
  final now = DateTime(2026, 7, 18);

  test('resolves current and previous pay periods with shared schedule', () {
    final current = ExportRangeResolver.resolve(
      type: ExportDateRangeType.currentPayPeriod,
      now: now,
      settings: settings,
      entries: const [],
    )!;
    final previous = ExportRangeResolver.resolve(
      type: ExportDateRangeType.previousPayPeriod,
      now: now,
      settings: settings,
      entries: const [],
    )!;
    expect(current.start, DateTime(2026, 7, 1));
    expect(current.end, DateTime(2026, 7, 31));
    expect(previous.start, DateTime(2026, 6, 1));
    expect(previous.end, DateTime(2026, 6, 30));
  });

  test('resolves calendar month and year ranges', () {
    final previousMonth = ExportRangeResolver.resolve(
      type: ExportDateRangeType.previousMonth,
      now: now,
      settings: settings,
      entries: const [],
    )!;
    final year = ExportRangeResolver.resolve(
      type: ExportDateRangeType.currentYear,
      now: now,
      settings: settings,
      entries: const [],
    )!;
    expect(previousMonth.start, DateTime(2026, 6, 1));
    expect(previousMonth.end, DateTime(2026, 6, 30));
    expect(year.start, DateTime(2026));
    expect(year.end, DateTime(2026, 12, 31));
  });

  test('invalid custom range is identified', () {
    final range = ExportRangeResolver.resolve(
      type: ExportDateRangeType.custom,
      now: now,
      settings: settings,
      entries: const [],
      customStart: DateTime(2026, 7, 20),
      customEnd: DateTime(2026, 7, 10),
    )!;
    expect(range.isValid, isFalse);
  });

  test('filename generation sanitisation and duplicate numbering', () {
    final range = ExportDateRange(DateTime(2026, 7), DateTime(2026, 7, 31));
    expect(
      ExportFilenameService.suggested(
        employeeFullName: 'dan beckett',
        rangeType: ExportDateRangeType.currentMonth,
        range: range,
        settings: settings,
        createdAt: now,
        format: ExportFileFormat.pdf,
      ),
      'Dan_Beckett_31_July_2026.pdf',
    );
    expect(
      ExportFilenameService.sanitize('bad:name.pdf', ExportFileFormat.pdf),
      'badname.pdf',
    );
    expect(ExportFilenameService.copyName('report.pdf', 2), 'report_2.pdf');
  });

  group('payday-based export filenames', () {
    String filename({
      required AppSettings settings,
      required DateTime date,
      ExportDateRangeType type = ExportDateRangeType.currentPayPeriod,
      DateTime? createdAt,
      ExportFileFormat format = ExportFileFormat.pdf,
      String name = 'dan beckett',
    }) {
      final range = ExportRangeResolver.resolve(
        type: type,
        now: date,
        settings: settings,
        entries: const [],
      )!;
      return ExportFilenameService.suggested(
        employeeFullName: name,
        rangeType: type,
        range: range,
        settings: settings,
        createdAt: createdAt ?? date,
        format: format,
      );
    }

    test('weekly export uses its configured payday', () {
      const weekly = AppSettings(
        payFrequency: 'Weekly',
        payPeriodAnchorDate: '2026-07-13',
        paydayRule: 'Fixed number of days after period end',
        paydayOffsetDays: 2,
      );
      expect(
        filename(settings: weekly, date: DateTime(2026, 7, 18)),
        'Dan_Beckett_21_July_2026.pdf',
      );
    });

    test('fortnightly export uses its configured payday', () {
      const fortnightly = AppSettings(
        payFrequency: 'Fortnightly',
        payPeriodAnchorDate: '2026-07-06',
        paydayRule: 'Next selected weekday after period end',
        paydaySelectedWeekday: DateTime.monday,
      );
      expect(
        filename(
          settings: fortnightly,
          date: DateTime(2026, 7, 18),
          format: ExportFileFormat.xlsx,
        ),
        'Dan_Beckett_20_July_2026.xlsx',
      );
    });

    test('four-weekly export uses its configured payday', () {
      const fourWeekly = AppSettings(
        payFrequency: 'Four-weekly',
        payPeriodAnchorDate: '2026-07-01',
      );
      expect(
        filename(settings: fourWeekly, date: DateTime(2026, 7, 18)),
        'Dan_Beckett_28_July_2026.pdf',
      );
    });

    test('monthly export supports a payday in the following month', () {
      const monthly = AppSettings(
        payFrequency: 'Calendar monthly',
        paydayRule: 'Fixed calendar day in following month',
        paydayFixedDay: 3,
      );
      expect(
        filename(
          settings: monthly,
          date: DateTime(2026, 7, 18),
          type: ExportDateRangeType.currentMonth,
          format: ExportFileFormat.csv,
        ),
        'Dan_Beckett_03_August_2026.csv',
      );
    });

    test('custom monthly export uses the resolved period payday', () {
      const customMonthly = AppSettings(
        payFrequency: 'Custom monthly',
        customPeriodStartDay: 26,
      );
      expect(
        filename(settings: customMonthly, date: DateTime(2026, 7, 18)),
        'Dan_Beckett_25_July_2026.pdf',
      );
    });

    test('unmatched custom dates use the export creation date', () {
      final range = ExportDateRange(
        DateTime(2026, 7, 4),
        DateTime(2026, 7, 12),
      );
      expect(
        ExportFilenameService.suggested(
          employeeFullName: 'SARAH jones',
          rangeType: ExportDateRangeType.custom,
          range: range,
          settings: settings,
          createdAt: DateTime(2026, 7, 18, 23, 59),
          format: ExportFileFormat.pdf,
        ),
        'Sarah_Jones_18_July_2026.pdf',
      );
    });

    test('sanitizes names and prevents duplicate extensions', () {
      final range = ExportDateRange(DateTime(2026, 7), DateTime(2026, 7, 31));
      final suggested = ExportFilenameService.suggested(
        employeeFullName: '  joHN: smITH  ',
        rangeType: ExportDateRangeType.currentMonth,
        range: range,
        settings: settings,
        createdAt: now,
        format: ExportFileFormat.pdf,
      );
      expect(suggested, 'John_Smith_31_July_2026.pdf');
      expect(
        ExportFilenameService.sanitize('$suggested.pdf', ExportFileFormat.pdf),
        suggested,
      );
      expect(
        ExportFileNamer.buildFileName(
          fullName: 'Ignored',
          companyName: 'Ignored',
          periodLabel: 'Ignored',
          format: ExportFormat.pdfTimesheet,
          fileNameLabel: suggested,
        ),
        suggested,
      );
    });
  });

  test('default templates expose real configurations', () {
    expect(ExportTemplate.defaults, hasLength(4));
    expect(
      ExportTemplate.defaults.first.reportType,
      ExportReportType.timesheet,
    );
  });
}
