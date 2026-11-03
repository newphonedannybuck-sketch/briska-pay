import 'package:briska/src/premium_home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CalendarPeriodProgress calculate(
    DateTime start,
    DateTime end,
    DateTime today,
  ) => calculateCalendarPeriodProgress(
    periodStart: start,
    periodEnd: end,
    today: today,
  );

  test('handles before, first, midpoint, final and after-period dates', () {
    final start = DateTime(2026, 7, 1);
    final end = DateTime(2026, 7, 10);

    final before = calculate(start, end, DateTime(2026, 6, 30));
    expect(before.displayText, '0 of 10 days');
    expect(before.progress, 0);

    final first = calculate(start, end, start);
    expect(first.displayText, '1 of 10 days');
    expect(first.progress, .1);

    final midpoint = calculate(start, end, DateTime(2026, 7, 5));
    expect(midpoint.displayText, '5 of 10 days');
    expect(midpoint.progress, .5);

    final finalDay = calculate(start, end, end);
    expect(finalDay.displayText, '10 of 10 days');
    expect(finalDay.progress, 1);

    final after = calculate(start, end, DateTime(2026, 7, 11));
    expect(after.displayText, '10 of 10 days');
    expect(after.progress, 1);
  });

  test('handles a single-day period', () {
    final day = DateTime(2026, 7, 23);
    final result = calculate(day, day, day);

    expect(result.totalDays, 1);
    expect(result.completedDays, 1);
    expect(result.displayText, '1 of 1 days');
    expect(result.progress, 1);
  });

  test('reversed ranges return a safe unavailable state', () {
    final result = calculate(
      DateTime(2026, 7, 10),
      DateTime(2026, 7, 1),
      DateTime(2026, 7, 5),
    );

    expect(result.isAvailable, isFalse);
    expect(result.totalDays, 0);
    expect(result.completedDays, 0);
    expect(result.progress, 0);
    expect(result.displayText, 'Unavailable');
  });

  test('counts UK spring and autumn DST transition dates safely', () {
    final spring = calculate(
      DateTime(2026, 3, 28),
      DateTime(2026, 3, 30),
      DateTime(2026, 3, 29),
    );
    final autumn = calculate(
      DateTime(2026, 10, 24),
      DateTime(2026, 10, 26),
      DateTime(2026, 10, 25),
    );

    for (final result in [spring, autumn]) {
      expect(result.totalDays, 3);
      expect(result.completedDays, 2);
      expect(result.progress, closeTo(2 / 3, .000001));
    }
  });

  test('counts leap-year and non-leap February correctly', () {
    final leap = calculate(
      DateTime(2028, 2, 1),
      DateTime(2028, 2, 29),
      DateTime(2028, 2, 29),
    );
    final nonLeap = calculate(
      DateTime(2026, 2, 1),
      DateTime(2026, 2, 28),
      DateTime(2026, 2, 28),
    );

    expect(leap.totalDays, 29);
    expect(nonLeap.totalDays, 28);
  });

  test('counts 28, 29, 30 and 31-day monthly periods', () {
    final periods = [
      (DateTime(2026, 2, 1), DateTime(2026, 2, 28), 28),
      (DateTime(2028, 2, 1), DateTime(2028, 2, 29), 29),
      (DateTime(2026, 4, 1), DateTime(2026, 4, 30), 30),
      (DateTime(2026, 7, 1), DateTime(2026, 7, 31), 31),
    ];

    for (final period in periods) {
      expect(calculate(period.$1, period.$2, period.$2).totalDays, period.$3);
    }
  });

  test('counts weekly, fortnightly and four-week periods', () {
    final periods = [
      (DateTime(2026, 7, 1), DateTime(2026, 7, 7), 7),
      (DateTime(2026, 7, 1), DateTime(2026, 7, 14), 14),
      (DateTime(2026, 7, 1), DateTime(2026, 7, 28), 28),
    ];

    for (final period in periods) {
      expect(calculate(period.$1, period.$2, period.$2).totalDays, period.$3);
    }
  });

  test('handles cross-month and cross-year periods', () {
    final crossMonth = calculate(
      DateTime(2026, 6, 26),
      DateTime(2026, 7, 25),
      DateTime(2026, 7, 25),
    );
    final crossYear = calculate(
      DateTime(2026, 12, 21),
      DateTime(2027, 1, 17),
      DateTime(2027, 1, 17),
    );

    expect(crossMonth.totalDays, 30);
    expect(crossYear.totalDays, 28);
  });

  test('ignores non-midnight time values', () {
    final result = calculate(
      DateTime(2026, 7, 1, 23, 59),
      DateTime(2026, 7, 7, 0, 1),
      DateTime(2026, 7, 3, 18, 30),
    );

    expect(result.totalDays, 7);
    expect(result.elapsedDays, 3);
    expect(result.completedDays, 3);
  });

  test('progress always remains between zero and one', () {
    final start = DateTime(2026, 7, 1);
    final end = DateTime(2026, 7, 31);
    final dates = [
      DateTime(1900, 1, 1),
      start,
      DateTime(2026, 7, 16),
      end,
      DateTime(2100, 1, 1),
    ];

    for (final date in dates) {
      final progress = calculate(start, end, date).progress;
      expect(progress, inInclusiveRange(0, 1));
      expect(progress.isFinite, isTrue);
    }
  });
}
