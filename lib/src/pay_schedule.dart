import 'models.dart';

class PayPeriodRange {
  const PayPeriodRange({
    required this.start,
    required this.end,
    required this.payday,
    required this.periodLabel,
    this.needsAnchor = false,
  });

  final DateTime start;
  final DateTime end;
  final DateTime payday;
  final String periodLabel;
  final bool needsAnchor;

  bool get hasSeparatePayday => payday != end;

  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }
}

const weeklyPayFrequency = 'Weekly';
const fortnightlyPayFrequency = 'Fortnightly';
const fourWeeklyPayFrequency = 'Four-weekly';
const calendarMonthlyPayFrequency = 'Calendar monthly';
const customMonthlyPayFrequency = 'Custom monthly';
const legacyMonthlyPayFrequency = 'Monthly';
const lastFridayPayFrequency = 'Last Friday of every month';

const paydayOnPeriodEnd = 'On period end date';
const paydayDaysAfterPeriodEnd = 'Fixed number of days after period end';
const paydayNextSelectedWeekdayAfterPeriodEnd =
    'Next selected weekday after period end';
const paydayFollowingWeekday = 'Following weekday';
const paydayFixedDaySameMonth = 'Fixed calendar day in same month';
const paydayFixedDayFollowingMonth = 'Fixed calendar day in following month';
const paydayLastWorkingDaySameMonth = 'Last working day of same month';
const paydayLastFridayOfMonth = 'Last Friday of month';

const fixedCyclePayFrequencies = {
  weeklyPayFrequency,
  fortnightlyPayFrequency,
  fourWeeklyPayFrequency,
};

String normalisePayFrequency(String value) {
  return switch (value) {
    legacyMonthlyPayFrequency => calendarMonthlyPayFrequency,
    weeklyPayFrequency ||
    fortnightlyPayFrequency ||
    fourWeeklyPayFrequency ||
    calendarMonthlyPayFrequency ||
    customMonthlyPayFrequency ||
    lastFridayPayFrequency => value,
    _ => fortnightlyPayFrequency,
  };
}

bool usesLastFridayPaySchedule(String payFrequency) =>
    normalisePayFrequency(payFrequency) == lastFridayPayFrequency;

bool requiresPayPeriodAnchor(AppSettings settings) =>
    fixedCyclePayFrequencies.contains(
      normalisePayFrequency(settings.payFrequency),
    ) &&
    _parseDate(settings.payPeriodAnchorDate) == null;

PayPeriodRange getCurrentPayPeriod({
  required DateTime date,
  required String payFrequency,
  required String payDay,
  String payPeriodAnchorDate = '',
  String paydayRule = paydayOnPeriodEnd,
  int paydayOffsetDays = 0,
  int paydayFixedDay = 1,
  int paydaySelectedWeekday = DateTime.friday,
  String paydayWeekday = 'Friday',
  int customPeriodStartDay = 1,
}) {
  final type = normalisePayFrequency(payFrequency);
  final today = _dateOnly(date);
  if (type == lastFridayPayFrequency) {
    return getLastFridayPayPeriod(today);
  }

  final (DateTime start, DateTime end, bool needsAnchor) = switch (type) {
    weeklyPayFrequency ||
    fortnightlyPayFrequency ||
    fourWeeklyPayFrequency => _fixedCyclePeriod(
      date: today,
      cycleDays: _cycleDays(type),
      anchor: _parseDate(payPeriodAnchorDate),
      legacyPayDay: payDay,
    ),
    customMonthlyPayFrequency => _customMonthlyPeriod(
      today,
      customPeriodStartDay.clamp(1, 31),
    ),
    _ => (
      DateTime(today.year, today.month, 1),
      DateTime(today.year, today.month + 1, 0),
      false,
    ),
  };

  final payday = _calculatePayday(
    periodStart: start,
    periodEnd: end,
    rule: _normalisePaydayRule(paydayRule),
    offsetDays: paydayOffsetDays,
    fixedDay: paydayFixedDay,
    selectedWeekday: _normaliseWeekday(
      paydaySelectedWeekday,
      fallback: _weekdayForPayDay(paydayWeekday),
    ),
  );

  return PayPeriodRange(
    start: start,
    end: end,
    payday: payday,
    periodLabel: _periodLabel(start, end),
    needsAnchor: needsAnchor,
  );
}

PayPeriodRange getCurrentPayPeriodForSettings({
  required DateTime date,
  required AppSettings settings,
}) {
  return getCurrentPayPeriod(
    date: date,
    payFrequency: settings.payFrequency,
    payDay: settings.payDay,
    payPeriodAnchorDate: settings.payPeriodAnchorDate,
    paydayRule: settings.paydayRule,
    paydayOffsetDays: settings.paydayOffsetDays,
    paydayFixedDay: settings.paydayFixedDay,
    paydaySelectedWeekday: settings.paydaySelectedWeekday,
    paydayWeekday: settings.paydayWeekday,
    customPeriodStartDay: settings.customPeriodStartDay,
  );
}

PayPeriodRange getPreviousPayPeriodForSettings({
  required PayPeriodRange period,
  required AppSettings settings,
}) {
  var candidateDate = period.start.subtract(const Duration(days: 1));
  while (true) {
    final candidate = getCurrentPayPeriodForSettings(
      date: candidateDate,
      settings: settings,
    );
    if (candidate.start.isBefore(period.start)) return candidate;
    candidateDate = candidateDate.subtract(const Duration(days: 1));
  }
}

List<PayPeriodRange> getAvailablePayPeriodsForSettings({
  required DateTime date,
  required AppSettings settings,
  required Iterable<DateTime> entryDates,
}) {
  final current = getCurrentPayPeriodForSettings(
    date: date,
    settings: settings,
  );
  if (entryDates.isEmpty) return [current];

  final earliestEntry = entryDates.reduce(
    (earliest, value) => value.isBefore(earliest) ? value : earliest,
  );
  final newestFirst = <PayPeriodRange>[current];
  var period = current;
  while (earliestEntry.isBefore(period.start)) {
    final previous = getPreviousPayPeriodForSettings(
      period: period,
      settings: settings,
    );
    final duplicatesExisting = newestFirst.any(
      (existing) =>
          existing.start == previous.start && existing.end == previous.end,
    );
    if (duplicatesExisting || !previous.start.isBefore(period.start)) {
      throw StateError('Pay schedule did not produce a distinct older period.');
    }
    newestFirst.add(previous);
    period = previous;
  }
  return newestFirst.reversed.toList(growable: false);
}

DateTime getLastFridayOfMonth(int year, int month) {
  final lastDay = DateTime(year, month + 1, 0);
  final daysBack = (lastDay.weekday - DateTime.friday) % 7;
  return lastDay.subtract(Duration(days: daysBack));
}

DateTime getFirstMondayAfter(DateTime date) {
  final day = _dateOnly(date);
  final daysUntilMonday = DateTime.daysPerWeek - day.weekday + 1;
  return day.add(Duration(days: daysUntilMonday));
}

DateTime getNextWeekdayAfter(DateTime periodEnd, int selectedWeekday) {
  final end = _dateOnly(periodEnd);
  var daysUntilSelected =
      (selectedWeekday - end.weekday + DateTime.daysPerWeek) %
      DateTime.daysPerWeek;
  if (daysUntilSelected == 0) {
    daysUntilSelected = DateTime.daysPerWeek;
  }
  return end.add(Duration(days: daysUntilSelected));
}

PayPeriodRange getLastFridayPayPeriod(DateTime date) {
  final today = _dateOnly(date);
  var end = getLastFridayOfMonth(today.year, today.month);
  if (today.isAfter(end)) {
    end = getLastFridayOfMonth(today.year, today.month + 1);
  }
  final previousEnd = getLastFridayOfMonth(end.year, end.month - 1);
  final start = getFirstMondayAfter(previousEnd);
  return PayPeriodRange(
    start: start,
    end: end,
    payday: end,
    periodLabel: _periodLabel(start, end),
  );
}

(DateTime, DateTime, bool) _fixedCyclePeriod({
  required DateTime date,
  required int cycleDays,
  required DateTime? anchor,
  required String legacyPayDay,
}) {
  final actualAnchor =
      anchor ?? _legacyAnchorForWeekday(_weekdayForPayDay(legacyPayDay));
  final anchorDay = _dayNumber(actualAnchor);
  final todayDay = _dayNumber(date);
  final offset = todayDay - anchorDay;
  final cycles = offset >= 0
      ? offset ~/ cycleDays
      : -(((-offset - 1) ~/ cycleDays) + 1);
  final startDay = anchorDay + cycles * cycleDays;
  final start = _dateFromDayNumber(startDay);
  return (start, _dateFromDayNumber(startDay + cycleDays - 1), anchor == null);
}

(DateTime, DateTime, bool) _customMonthlyPeriod(DateTime date, int startDay) {
  final currentStart = _dateInMonth(date.year, date.month, startDay);
  final start = date.isBefore(currentStart)
      ? _dateInMonth(date.year, date.month - 1, startDay)
      : currentStart;
  final nextStart = _dateInMonth(start.year, start.month + 1, startDay);
  return (start, nextStart.subtract(const Duration(days: 1)), false);
}

DateTime _calculatePayday({
  required DateTime periodStart,
  required DateTime periodEnd,
  required String rule,
  required int offsetDays,
  required int fixedDay,
  required int selectedWeekday,
}) {
  return switch (rule) {
    paydayDaysAfterPeriodEnd => periodEnd.add(
      Duration(days: offsetDays.clamp(0, 366)),
    ),
    paydayNextSelectedWeekdayAfterPeriodEnd => getNextWeekdayAfter(
      periodEnd,
      selectedWeekday,
    ),
    paydayFixedDaySameMonth => _dateInMonth(
      periodEnd.year,
      periodEnd.month,
      fixedDay,
    ),
    paydayFixedDayFollowingMonth => _dateInMonth(
      periodEnd.year,
      periodEnd.month + 1,
      fixedDay,
    ),
    paydayLastWorkingDaySameMonth => _lastWorkingDayOfMonth(
      periodEnd.year,
      periodEnd.month,
    ),
    paydayLastFridayOfMonth => getLastFridayOfMonth(
      periodEnd.year,
      periodEnd.month,
    ),
    _ => periodEnd,
  };
}

String _normalisePaydayRule(String value) {
  return switch (value) {
    paydayOnPeriodEnd ||
    paydayDaysAfterPeriodEnd ||
    paydayNextSelectedWeekdayAfterPeriodEnd ||
    paydayFollowingWeekday ||
    paydayFixedDaySameMonth ||
    paydayFixedDayFollowingMonth ||
    paydayLastWorkingDaySameMonth ||
    paydayLastFridayOfMonth =>
      value == paydayFollowingWeekday
          ? paydayNextSelectedWeekdayAfterPeriodEnd
          : value,
    _ => paydayOnPeriodEnd,
  };
}

int _cycleDays(String type) {
  return switch (type) {
    weeklyPayFrequency => 7,
    fortnightlyPayFrequency => 14,
    fourWeeklyPayFrequency => 28,
    _ => 14,
  };
}

DateTime _lastWorkingDayOfMonth(int year, int month) {
  var day = DateTime(year, month + 1, 0);
  while (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
    day = day.subtract(const Duration(days: 1));
  }
  return day;
}

DateTime _dateInMonth(int year, int month, int preferredDay) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, preferredDay.clamp(1, lastDay));
}

DateTime _legacyAnchorForWeekday(int weekday) {
  final fridayAnchor = DateTime(1970, 1, 2);
  return fridayAnchor.add(Duration(days: weekday - DateTime.friday + 1));
}

int _weekdayForPayDay(String payDay) => switch (payDay) {
  'Monday' => DateTime.monday,
  'Tuesday' => DateTime.tuesday,
  'Wednesday' => DateTime.wednesday,
  'Thursday' => DateTime.thursday,
  'Friday' => DateTime.friday,
  'Saturday' => DateTime.saturday,
  'Sunday' => DateTime.sunday,
  _ => DateTime.friday,
};

int _normaliseWeekday(int weekday, {int fallback = DateTime.friday}) {
  if (weekday >= DateTime.monday && weekday <= DateTime.sunday) {
    return weekday;
  }
  return fallback;
}

DateTime? _parseDate(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null ? null : _dateOnly(parsed);
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

int _dayNumber(DateTime date) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).difference(DateTime.utc(1970)).inDays;

DateTime _dateFromDayNumber(int dayNumber) {
  final date = DateTime.utc(1970).add(Duration(days: dayNumber));
  return DateTime(date.year, date.month, date.day);
}

String _periodLabel(DateTime start, DateTime end) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final startYear = start.year == end.year ? '' : ' ${start.year}';
  return '${start.day} ${months[start.month - 1]}$startYear - '
      '${end.day} ${months[end.month - 1]} ${end.year}';
}
