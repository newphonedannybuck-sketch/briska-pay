import 'models.dart';
import 'pay_schedule.dart';
import 'work_calculator.dart';

DateTime homeCalendarDate(DateTime date) =>
    DateTime(date.year, date.month, date.day);

class RecordedEarningsPoint {
  const RecordedEarningsPoint(this.date, this.total);
  final DateTime date;
  final double total;
}

class HomeTimeOffSummary {
  HomeTimeOffSummary(Iterable<WorkEntry> source) {
    final entries = source.toList();
    days = entries.map((entry) => homeCalendarDate(entry.date)).toSet().length;
    recordedHours = entries.fold(0, (sum, entry) => sum + entry.totalHours);
    // WorkEntry persists blank and explicit zero hours as the same double.
    // Do not infer hours or claim coverage that the stored data cannot establish.
    hasRecordedHours = entries.any((entry) => entry.totalHours != 0);
  }
  late final int days;
  late final double recordedHours;
  late final bool hasRecordedHours;
}

class HomeDashboardSummary {
  HomeDashboardSummary(Iterable<WorkEntry> source, PayPeriodRange period) {
    final entries = source
        .where((entry) => period.contains(entry.date))
        .toList();
    pay = WorkCalculator.summarize(entries);
    daysWorked = entries
        .where((entry) => entry.type == EntryType.workDay)
        .map((entry) => homeCalendarDate(entry.date))
        .toSet()
        .length;
    holidays = HomeTimeOffSummary(
      entries.where((entry) => entry.type == EntryType.holiday),
    );
    bankHolidays = HomeTimeOffSummary(
      entries.where((entry) => entry.type == EntryType.bankHoliday),
    );
    final daily = <DateTime, double>{};
    for (final entry in entries) {
      final date = homeCalendarDate(entry.date);
      // grossPay is the same stored total used by WorkCalculator.summarize,
      // including allowance/uplift. Deductions belong to net pay, not this chart.
      daily.update(
        date,
        (value) => value + entry.grossPay,
        ifAbsent: () => entry.grossPay,
      );
    }
    var running = 0.0;
    earnings = [
      for (final date in daily.keys.toList()..sort())
        RecordedEarningsPoint(date, running += daily[date]!),
    ];
  }
  late final WorkSummary pay;
  late final int daysWorked;
  late final HomeTimeOffSummary holidays;
  late final HomeTimeOffSummary bankHolidays;
  late final List<RecordedEarningsPoint> earnings;
}
