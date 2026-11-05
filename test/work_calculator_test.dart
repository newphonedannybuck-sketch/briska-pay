import 'package:flutter_test/flutter_test.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/work_calculator.dart';

void main() {
  test('Primary rate can calculate hours and wages with manual allowance', () {
    final result = WorkCalculator.calculate(
      startTime: '08:00',
      finishTime: '16:30',
      breakMinutes: 30,
      hourlyRate: 20,
      rateType: 'primary',
      dailyAllowance: 25,
      jobUplift: 0,
    );

    expect(result.isValid, isTrue);
    expect(result.totalHours, 8);
    expect(result.wages, 160);
    expect(result.totalPay, 185);
  });

  test('release candidate calculation rules match all entry types', () {
    final home = WorkCalculator.calculate(
      startTime: '08:00',
      finishTime: '16:30',
      breakMinutes: 30,
      hourlyRate: 25,
      rateType: 'primary',
      dailyAllowance: 20,
      jobUplift: 15,
    );
    final away = WorkCalculator.calculate(
      startTime: '08:00',
      finishTime: '17:00',
      breakMinutes: 30,
      hourlyRate: 30,
      rateType: 'secondary',
      dailyAllowance: 25,
      jobUplift: 40,
    );
    final holiday = WorkCalculator.calculate(
      startTime: '',
      finishTime: '',
      breakMinutes: 0,
      hourlyRate: 25,
      workLocation: 'Home',
      dailyAllowance: 25,
      jobUplift: 10,
      entryType: 'Holiday',
      holidayHours: 8,
    );
    final unpaid = WorkCalculator.calculate(
      startTime: '',
      finishTime: '',
      breakMinutes: 0,
      hourlyRate: 25,
      workLocation: 'Away',
      dailyAllowance: 25,
      jobUplift: 5,
      entryType: 'UnpaidDayOff',
    );

    expect(home.totalHours, 8);
    expect(home.wages, 200);
    expect(home.totalPay, 235);
    expect(away.totalHours, 8.5);
    expect(away.wages, 255);
    expect(away.totalPay, 320);
    expect(holiday.totalHours, 8);
    expect(holiday.wages, 200);
    expect(holiday.totalPay, 210);
    expect(unpaid.totalHours, 0);
    expect(unpaid.wages, 0);
    expect(unpaid.totalPay, 5);
  });

  test('Away day calculates hours, wages, allowance and uplift', () {
    final result = WorkCalculator.calculate(
      startTime: '08:00',
      finishTime: '17:00',
      breakMinutes: 30,
      hourlyRate: 20,
      workLocation: 'Away',
      dailyAllowance: 10,
      jobUplift: 150,
    );

    expect(result.isValid, isTrue);
    expect(result.totalHours, 8.5);
    expect(result.wages, 170);
    expect(result.totalPay, 330);
  });

  test('finish before start is treated as an overnight shift', () {
    final result = WorkCalculator.calculate(
      startTime: '17:00',
      finishTime: '08:00',
      breakMinutes: 30,
      hourlyRate: 20,
      workLocation: 'Away',
      dailyAllowance: 10,
      jobUplift: 0,
    );

    expect(result.isValid, isTrue);
    expect(result.totalHours, 14.5);
    expect(result.wages, 290);
    expect(result.totalPay, 300);
  });

  test('normalizes supported colon, dot and compact time formats', () {
    expect(WorkCalculator.normalizeTime('08:00'), '08:00');
    expect(WorkCalculator.normalizeTime('8:00'), '08:00');
    expect(WorkCalculator.normalizeTime('17:00'), '17:00');
    expect(WorkCalculator.normalizeTime('17.00'), '17:00');
    expect(WorkCalculator.normalizeTime('7.30'), '07:30');
    expect(WorkCalculator.normalizeTime('730'), '07:30');
    expect(WorkCalculator.normalizeTime('0730'), '07:30');
    expect(WorkCalculator.normalizeTime('1700'), '17:00');
  });

  test('dot time input calculates immediately through shared parser', () {
    final result = WorkCalculator.calculate(
      startTime: '08:00',
      finishTime: '17.00',
      breakMinutes: 30,
      hourlyRate: 20,
      workLocation: 'Away',
      dailyAllowance: 0,
      jobUplift: 150,
    );

    expect(result.isValid, isTrue);
    expect(result.totalHours, 8.5);
    expect(result.wages, 170);
    expect(result.totalPay, 320);
  });

  test('recalculates a stale Away entry that was stored with zero hours', () {
    final stale = WorkEntry(
      id: 'away-entry',
      date: DateTime(2026, 7, 8),
      siteName: 'Away job',
      startTime: '08:00',
      finishTime: '17:00',
      breakMinutes: 30,
      workLocation: 'Away',
      hourlyRateUsed: 20,
      dailyAllowance: 0,
      jobUplift: 150,
      totalHours: 0,
      wages: 0,
      totalPay: 150,
      notes: '',
    );

    final repaired = WorkCalculator.recalculateEntry(stale);

    expect(repaired.totalHours, 8.5);
    expect(repaired.wages, 170);
    expect(repaired.totalPay, 320);
  });

  test('Holiday uses entered 8 hours, home rate and optional uplift', () {
    final result = WorkCalculator.calculate(
      startTime: '',
      finishTime: '',
      breakMinutes: 0,
      hourlyRate: 20,
      workLocation: 'Home',
      dailyAllowance: 0,
      jobUplift: 50,
      entryType: 'Holiday',
      holidayHours: 8,
    );

    expect(result.isValid, isTrue);
    expect(result.totalHours, 8);
    expect(result.wages, 160);
    expect(result.totalPay, 210);
  });

  test('summary preserves recorded Unpaid Day Off values', () {
    final unpaid = WorkEntry(
      id: 'unpaid',
      entryType: 'UnpaidDayOff',
      date: DateTime(2026, 7, 9),
      siteName: '',
      startTime: '08:00',
      finishTime: '17:00',
      breakMinutes: 30,
      workLocation: 'Away',
      hourlyRateUsed: 20,
      dailyAllowance: 20,
      jobUplift: 150,
      totalHours: 8.5,
      wages: 170,
      totalPay: 340,
      notes: '',
    );

    final summary = WorkCalculator.summarize([unpaid]);

    expect(summary.totalHours, 8.5);
    expect(summary.totalWages, 170);
    expect(summary.totalDailyAllowance, 20);
    expect(summary.totalJobUplift, 150);
    expect(summary.totalExpectedPay, 340);
    expect(summary.unpaidDays, 1);
    expect(summary.holidayDays, 0);
  });

  test('rejects negative money values before saving', () {
    final result = WorkCalculator.calculate(
      startTime: '08:00',
      finishTime: '16:30',
      breakMinutes: 30,
      hourlyRate: 20,
      workLocation: 'Home',
      dailyAllowance: 0,
      jobUplift: -1,
    );

    expect(result.isValid, isFalse);
    expect(result.error, 'Job uplift cannot be negative.');
  });

  test('summaries preserve recorded overnight totals', () {
    final staleInvalid = WorkEntry(
      id: 'bad-time',
      date: DateTime(2026, 7, 9),
      siteName: 'Bad time',
      startTime: '17:00',
      finishTime: '08:00',
      breakMinutes: 30,
      workLocation: 'Away',
      hourlyRateUsed: 20,
      dailyAllowance: 10,
      jobUplift: 50,
      totalHours: 8,
      wages: 160,
      totalPay: 220,
      notes: '',
    );

    final summary = WorkCalculator.summarize([staleInvalid]);

    expect(summary.totalHours, 8);
    expect(summary.totalWages, 160);
    expect(summary.totalDailyAllowance, 10);
    expect(summary.totalJobUplift, 50);
    expect(summary.totalExpectedPay, 220);
  });
}
