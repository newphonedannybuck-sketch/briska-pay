import 'models.dart';
import 'display_format.dart';

class WorkCalculation {
  const WorkCalculation({
    required this.totalHours,
    required this.wages,
    required this.totalPay,
    this.error,
  });

  final double totalHours;
  final double wages;
  final double totalPay;
  final String? error;

  bool get isValid => error == null;
}

class WorkSummary {
  const WorkSummary({
    required this.entries,
    required this.totalHours,
    required this.totalWages,
    required this.totalDailyAllowance,
    required this.totalJobUplift,
    required this.totalExpectedPay,
    required this.totalDeductions,
    required this.totalNetPay,
    required this.unpaidDays,
    required this.holidayDays,
    required this.bankHolidayDays,
    required this.paidBankHolidayDays,
    required this.unpaidBankHolidayDays,
    required this.sickDays,
    required this.paidSickDays,
    required this.unpaidSickDays,
  });

  final List<WorkEntry> entries;
  final double totalHours;
  final double totalWages;
  final double totalDailyAllowance;
  final double totalJobUplift;
  final double totalExpectedPay;
  final double totalDeductions;
  final double totalNetPay;
  final int unpaidDays;
  final int holidayDays;
  final int bankHolidayDays;
  final int paidBankHolidayDays;
  final int unpaidBankHolidayDays;
  final int sickDays;
  final int paidSickDays;
  final int unpaidSickDays;

  int get totalDays => entries.length;
}

abstract final class WorkCalculator {
  static WorkCalculation calculate({
    required String startTime,
    required String finishTime,
    required int breakMinutes,
    required double hourlyRate,
    String rateType = 'primary',
    @Deprecated('Use rateType') String? workLocation,
    required double dailyAllowance,
    required double jobUplift,
    String entryType = 'WorkDay',
    bool isPaidSickDay = false,
    bool isPaidBankHoliday = true,
    double deductionAmount = 0,
  }) {
    if (hourlyRate < 0) {
      return const WorkCalculation(
        totalHours: 0,
        wages: 0,
        totalPay: 0,
        error: 'Hourly rate cannot be negative.',
      );
    }
    if (dailyAllowance < 0) {
      return const WorkCalculation(
        totalHours: 0,
        wages: 0,
        totalPay: 0,
        error: 'Daily allowance cannot be negative.',
      );
    }
    if (jobUplift < 0) {
      return const WorkCalculation(
        totalHours: 0,
        wages: 0,
        totalPay: 0,
        error: 'Job uplift cannot be negative.',
      );
    }
    if (deductionAmount < 0) {
      return const WorkCalculation(
        totalHours: 0,
        wages: 0,
        totalPay: 0,
        error: 'Deduction amount cannot be negative.',
      );
    }
    if (entryType == 'UnpaidDayOff') {
      return WorkCalculation(totalHours: 0, wages: 0, totalPay: jobUplift);
    }
    if (entryType == 'SickDay') {
      if (!isPaidSickDay) {
        return WorkCalculation(totalHours: 0, wages: 0, totalPay: jobUplift);
      }
      const totalHours = 8.0;
      final wages = totalHours * hourlyRate;
      return WorkCalculation(
        totalHours: totalHours,
        wages: wages,
        totalPay: wages + jobUplift,
      );
    }
    if (entryType == 'bankHoliday' || entryType == 'BankHoliday') {
      if (!isPaidBankHoliday) {
        return WorkCalculation(totalHours: 0, wages: 0, totalPay: jobUplift);
      }
      const totalHours = 8.0;
      final wages = totalHours * hourlyRate;
      return WorkCalculation(
        totalHours: totalHours,
        wages: wages,
        totalPay: wages + jobUplift,
      );
    }
    if (entryType == 'Holiday') {
      const totalHours = 8.0;
      final wages = totalHours * hourlyRate;
      return WorkCalculation(
        totalHours: totalHours,
        wages: wages,
        totalPay: wages + jobUplift,
      );
    }
    final start = _minutesSinceMidnight(startTime);
    final finish = _minutesSinceMidnight(finishTime);

    if (start == null || finish == null) {
      return const WorkCalculation(
        totalHours: 0,
        wages: 0,
        totalPay: 0,
        error: 'Enter time like 08:00, 17:30 or 0730',
      );
    }
    if (finish == start) {
      return const WorkCalculation(
        totalHours: 0,
        wages: 0,
        totalPay: 0,
        error: 'Start and finish time must be different.',
      );
    }
    if (breakMinutes < 0) {
      return const WorkCalculation(
        totalHours: 0,
        wages: 0,
        totalPay: 0,
        error: 'Break minutes cannot be negative.',
      );
    }

    final durationMinutes = finish < start
        ? finish + 1440 - start
        : finish - start;
    if (durationMinutes > 16 * 60) {
      return const WorkCalculation(
        totalHours: 0,
        wages: 0,
        totalPay: 0,
        error: 'A work period cannot exceed 16 hours.',
      );
    }
    final workedMinutes = durationMinutes - breakMinutes;
    if (workedMinutes <= 0) {
      return const WorkCalculation(
        totalHours: 0,
        wages: 0,
        totalPay: 0,
        error: 'Break must be shorter than the work period.',
      );
    }

    final totalHours = workedMinutes / 60;
    final wages = totalHours * hourlyRate;
    return WorkCalculation(
      totalHours: totalHours,
      wages: wages,
      totalPay: wages + dailyAllowance + jobUplift,
    );
  }

  static int? _minutesSinceMidnight(String value) {
    final normalized = normalizeTime(value);
    if (normalized == null) return null;
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(normalized);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  static String? normalizeTime(String value) {
    return normaliseTimeInput(value);
  }

  static WorkEntry recalculateEntry(WorkEntry entry) {
    final startTime = entry.entryType == 'WorkDay'
        ? normalizeTime(entry.startTime)
        : '';
    final finishTime = entry.entryType == 'WorkDay'
        ? normalizeTime(entry.finishTime)
        : '';
    if (entry.entryType == 'WorkDay' &&
        (startTime == null || finishTime == null)) {
      return entry;
    }
    final result = calculate(
      startTime: startTime ?? '',
      finishTime: finishTime ?? '',
      breakMinutes: entry.entryType == 'WorkDay' ? entry.breakMinutes : 0,
      hourlyRate: entry.hourlyRateUsed,
      rateType: entry.rateType,
      dailyAllowance: entry.dailyAllowance,
      jobUplift: entry.jobUplift,
      entryType: entry.entryType,
      isPaidSickDay: entry.isPaidSickDay,
      isPaidBankHoliday: entry.isPaidBankHoliday,
      deductionAmount: entry.deductionAmount,
    );
    if (!result.isValid) return _zeroInvalidEntry(entry);
    return WorkEntry(
      id: entry.id,
      entryType: entry.entryType,
      date: entry.date,
      siteName: entry.siteName,
      startTime: startTime ?? '',
      finishTime: finishTime ?? '',
      breakMinutes: entry.entryType == 'WorkDay' ? entry.breakMinutes : 0,
      rateType: entry.entryType == 'WorkDay' ? entry.rateType : 'primary',
      hourlyRateUsed: entry.hourlyRateUsed,
      dailyAllowance: entry.entryType == 'WorkDay' ? entry.dailyAllowance : 0,
      jobUplift: entry.jobUplift,
      totalHours: result.totalHours,
      wages: result.wages,
      totalPay: result.totalPay,
      notes: entry.notes,
      isPaidSickDay: entry.isPaidSickDay,
      isPaidBankHoliday: entry.isPaidBankHoliday,
      deductionAmount: entry.deductionAmount,
      deductionReason: entry.deductionReason,
    );
  }

  static WorkEntry _zeroInvalidEntry(WorkEntry entry) {
    return WorkEntry(
      id: entry.id,
      entryType: entry.entryType,
      date: entry.date,
      siteName: entry.siteName,
      startTime: entry.entryType == 'WorkDay'
          ? (normalizeTime(entry.startTime) ?? entry.startTime)
          : '',
      finishTime: entry.entryType == 'WorkDay'
          ? (normalizeTime(entry.finishTime) ?? entry.finishTime)
          : '',
      breakMinutes: entry.entryType == 'WorkDay' ? entry.breakMinutes : 0,
      rateType: entry.entryType == 'WorkDay' ? entry.rateType : 'primary',
      hourlyRateUsed: entry.hourlyRateUsed < 0 ? 0 : entry.hourlyRateUsed,
      dailyAllowance: 0,
      jobUplift: 0,
      totalHours: 0,
      wages: 0,
      totalPay: 0,
      notes: entry.notes,
      isPaidSickDay: entry.isPaidSickDay,
      isPaidBankHoliday: entry.isPaidBankHoliday,
      deductionAmount: entry.deductionAmount < 0 ? 0 : entry.deductionAmount,
      deductionReason: entry.deductionReason,
    );
  }

  static WorkSummary summarize(Iterable<WorkEntry> source) {
    final entries = source.map(recalculateEntry).toList();
    return WorkSummary(
      entries: entries,
      totalHours: entries.fold(0, (sum, entry) => sum + entry.totalHours),
      totalWages: entries.fold(0, (sum, entry) => sum + entry.wages),
      totalDailyAllowance: entries.fold(
        0,
        (sum, entry) => sum + entry.dailyAllowance,
      ),
      totalJobUplift: entries.fold(0, (sum, entry) => sum + entry.jobUplift),
      totalExpectedPay: entries.fold(0, (sum, entry) => sum + entry.totalPay),
      totalDeductions: entries.fold(
        0,
        (sum, entry) => sum + entry.deductionAmount,
      ),
      totalNetPay: entries.fold(0, (sum, entry) => sum + entry.netPay),
      unpaidDays: entries
          .where((entry) => entry.entryType == 'UnpaidDayOff')
          .length,
      holidayDays: entries
          .where((entry) => entry.entryType == 'Holiday')
          .length,
      bankHolidayDays: entries
          .where((entry) => entry.type == EntryType.bankHoliday)
          .length,
      paidBankHolidayDays: entries
          .where(
            (entry) =>
                entry.type == EntryType.bankHoliday && entry.isPaidBankHoliday,
          )
          .length,
      unpaidBankHolidayDays: entries
          .where(
            (entry) =>
                entry.type == EntryType.bankHoliday && !entry.isPaidBankHoliday,
          )
          .length,
      sickDays: entries.where((entry) => entry.entryType == 'SickDay').length,
      paidSickDays: entries
          .where((entry) => entry.entryType == 'SickDay' && entry.isPaidSickDay)
          .length,
      unpaidSickDays: entries
          .where(
            (entry) => entry.entryType == 'SickDay' && !entry.isPaidSickDay,
          )
          .length,
    );
  }
}
