import '../../../src/models.dart';
import '../../../src/pay_schedule.dart';

enum ExportDateRangeType {
  currentPayPeriod('Current pay period'),
  previousPayPeriod('Previous pay period'),
  custom('Custom date range'),
  currentMonth('Current month'),
  previousMonth('Previous month'),
  currentYear('Current year'),
  allRecords('All records');

  const ExportDateRangeType(this.label);
  final String label;
}

enum ExportReportType {
  timesheet('Timesheet'),
  paySummary('Pay summary'),
  monthlyReport('Monthly report'),
  annualSummary('Annual summary');

  const ExportReportType(this.label);
  final String label;
}

enum ExportFileFormat {
  pdf('PDF', 'pdf'),
  xlsx('Excel (.xlsx)', 'xlsx'),
  csv('CSV (.csv)', 'csv');

  const ExportFileFormat(this.label, this.extension);
  final String label;
  final String extension;
}

enum ExportDestination {
  downloads('Downloads'),
  documents('Documents'),
  exportLibrary('Export Library'),
  chooseEveryTime('Choose Every Time');

  const ExportDestination(this.label);
  final String label;
}

class ExportDateRange {
  const ExportDateRange(this.start, this.end);
  final DateTime start;
  final DateTime end;

  bool get isValid => !start.isAfter(end);
  bool contains(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    return !date.isBefore(start) && !date.isAfter(end);
  }
}

abstract final class ExportRangeResolver {
  static ExportDateRange? resolve({
    required ExportDateRangeType type,
    required DateTime now,
    required AppSettings settings,
    required List<WorkEntry> entries,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    switch (type) {
      case ExportDateRangeType.currentPayPeriod:
        final period = getCurrentPayPeriodForSettings(
          date: today,
          settings: settings,
        );
        return ExportDateRange(period.start, period.end);
      case ExportDateRangeType.previousPayPeriod:
        final current = getCurrentPayPeriodForSettings(
          date: today,
          settings: settings,
        );
        final previous = getCurrentPayPeriodForSettings(
          date: current.start.subtract(const Duration(days: 1)),
          settings: settings,
        );
        return ExportDateRange(previous.start, previous.end);
      case ExportDateRangeType.custom:
        if (customStart == null || customEnd == null) return null;
        return ExportDateRange(customStart, customEnd);
      case ExportDateRangeType.currentMonth:
        return ExportDateRange(
          DateTime(today.year, today.month),
          DateTime(today.year, today.month + 1, 0),
        );
      case ExportDateRangeType.previousMonth:
        return ExportDateRange(
          DateTime(today.year, today.month - 1),
          DateTime(today.year, today.month, 0),
        );
      case ExportDateRangeType.currentYear:
        return ExportDateRange(
          DateTime(today.year),
          DateTime(today.year, 12, 31),
        );
      case ExportDateRangeType.allRecords:
        if (entries.isEmpty) return null;
        final dates = entries.map((entry) => entry.date).toList()..sort();
        return ExportDateRange(dates.first, dates.last);
    }
  }
}

class ExportOptions {
  const ExportOptions({
    this.includeCompanyName = true,
    this.includeEmployeeName = true,
    this.includeBranding = true,
    this.includeSignatureLine = false,
    this.includeNotes = false,
  });
  final bool includeCompanyName;
  final bool includeEmployeeName;
  final bool includeBranding;
  final bool includeSignatureLine;
  final bool includeNotes;

  ExportOptions copyWith({
    bool? includeCompanyName,
    bool? includeEmployeeName,
    bool? includeBranding,
    bool? includeSignatureLine,
    bool? includeNotes,
  }) => ExportOptions(
    includeCompanyName: includeCompanyName ?? this.includeCompanyName,
    includeEmployeeName: includeEmployeeName ?? this.includeEmployeeName,
    includeBranding: includeBranding ?? this.includeBranding,
    includeSignatureLine: includeSignatureLine ?? this.includeSignatureLine,
    includeNotes: includeNotes ?? this.includeNotes,
  );
}

class ExportTemplate {
  const ExportTemplate({
    required this.id,
    required this.name,
    required this.reportType,
    required this.format,
    required this.options,
  });
  final String id;
  final String name;
  final ExportReportType reportType;
  final ExportFileFormat format;
  final ExportOptions options;

  static const defaults = [
    ExportTemplate(
      id: 'employer-timesheet',
      name: 'Employer Timesheet',
      reportType: ExportReportType.timesheet,
      format: ExportFileFormat.pdf,
      options: ExportOptions(),
    ),
    ExportTemplate(
      id: 'personal-records',
      name: 'Personal Records',
      reportType: ExportReportType.timesheet,
      format: ExportFileFormat.xlsx,
      options: ExportOptions(includeNotes: true),
    ),
    ExportTemplate(
      id: 'monthly-summary',
      name: 'Monthly Summary',
      reportType: ExportReportType.monthlyReport,
      format: ExportFileFormat.pdf,
      options: ExportOptions(),
    ),
    ExportTemplate(
      id: 'annual-overview',
      name: 'Annual Overview',
      reportType: ExportReportType.annualSummary,
      format: ExportFileFormat.pdf,
      options: ExportOptions(),
    ),
  ];
}
