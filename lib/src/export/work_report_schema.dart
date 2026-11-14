/// Shared report metadata. Renderers retain their own cell types, escaping,
/// rounding and styling. Legacy unknown day-type fallbacks remain selectable.
abstract final class WorkReportSchema {
  static const columns = [
    'Date',
    'Site/job',
    'Day type',
    'Pay status',
    'Rate used',
    'Start time',
    'Finish time',
    'Break minutes',
    'Hours worked',
    'Hourly rate',
    'Base pay',
    'Daily allowance',
    'Job uplift',
    'Gross pay',
    'Deduction',
    'Deduction reason',
    'Net pay',
    'Notes',
  ];

  static String entryTypeLabel(
    String value, {
    bool isPaidSickDay = false,
    String unknownLabel = 'Work day',
  }) {
    return switch (value) {
      'UnpaidDayOff' => 'Unpaid day off',
      'Holiday' => 'Holiday',
      'bankHoliday' || 'BankHoliday' => 'Bank Holiday',
      'SickDay' => isPaidSickDay ? 'Paid Sick Day' : 'Unpaid Sick Day',
      'WorkDay' => 'Work day',
      _ => unknownLabel,
    };
  }

  static List<String> currencyColumns(String code) => [
    ...columns.take(9),
    'Hourly rate ($code)',
    'Base pay ($code)',
    'Daily allowance ($code)',
    'Job uplift ($code)',
    'Gross pay ($code)',
    'Deduction ($code)',
    'Deduction reason',
    'Net pay ($code)',
    columns.last,
  ];
}
