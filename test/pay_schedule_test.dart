import 'package:flutter_test/flutter_test.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/pay_schedule.dart';

void main() {
  group('fixed cycle pay periods', () {
    test('weekly uses an anchor in the middle of a month', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2026, 7, 20),
        payFrequency: weeklyPayFrequency,
        payDay: 'Friday',
        payPeriodAnchorDate: '2026-07-06',
      );

      expect(period.start, DateTime(2026, 7, 20));
      expect(period.end, DateTime(2026, 7, 26));
      expect(period.payday, DateTime(2026, 7, 26));
      expect(period.needsAnchor, isFalse);
    });

    test('fortnightly calculates forward from an anchor', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2026, 7, 20),
        payFrequency: fortnightlyPayFrequency,
        payDay: 'Friday',
        payPeriodAnchorDate: '2026-07-06',
      );

      expect(period.start, DateTime(2026, 7, 20));
      expect(period.end, DateTime(2026, 8, 2));
    });

    test('fortnightly calculates backward from an anchor', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2026, 7, 5),
        payFrequency: fortnightlyPayFrequency,
        payDay: 'Friday',
        payPeriodAnchorDate: '2026-07-06',
      );

      expect(period.start, DateTime(2026, 6, 22));
      expect(period.end, DateTime(2026, 7, 5));
    });

    test('four-weekly uses an anchor in the middle of a month', () {
      final first = getCurrentPayPeriod(
        date: DateTime(2026, 7, 6),
        payFrequency: fourWeeklyPayFrequency,
        payDay: 'Friday',
        payPeriodAnchorDate: '2026-07-06',
      );
      final second = getCurrentPayPeriod(
        date: DateTime(2026, 8, 3),
        payFrequency: fourWeeklyPayFrequency,
        payDay: 'Friday',
        payPeriodAnchorDate: '2026-07-06',
      );
      final third = getCurrentPayPeriod(
        date: DateTime(2026, 9, 1),
        payFrequency: fourWeeklyPayFrequency,
        payDay: 'Friday',
        payPeriodAnchorDate: '2026-07-06',
      );

      expect(first.start, DateTime(2026, 7, 6));
      expect(first.end, DateTime(2026, 8, 2));
      expect(second.start, DateTime(2026, 8, 3));
      expect(second.end, DateTime(2026, 8, 30));
      expect(third.start, DateTime(2026, 8, 31));
      expect(third.end, DateTime(2026, 9, 27));
    });

    test('four-weekly crosses month boundaries', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2026, 8, 10),
        payFrequency: fourWeeklyPayFrequency,
        payDay: 'Friday',
        payPeriodAnchorDate: '2026-07-06',
      );

      expect(period.start, DateTime(2026, 8, 3));
      expect(period.end, DateTime(2026, 8, 30));
    });

    test('four-weekly crosses year boundaries', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2027, 1, 10),
        payFrequency: fourWeeklyPayFrequency,
        payDay: 'Friday',
        payPeriodAnchorDate: '2026-12-21',
      );

      expect(period.start, DateTime(2026, 12, 21));
      expect(period.end, DateTime(2027, 1, 17));
    });

    test('legacy fixed-cycle users are flagged for an anchor prompt', () {
      final settings = const AppSettings(payFrequency: weeklyPayFrequency);
      final period = getCurrentPayPeriodForSettings(
        date: DateTime(2026, 7, 9),
        settings: settings,
      );

      expect(requiresPayPeriodAnchor(settings), isTrue);
      expect(period.needsAnchor, isTrue);
      expect(period.start, DateTime(2026, 7, 4));
      expect(period.end, DateTime(2026, 7, 10));
    });
  });

  group('payday rules', () {
    test('supports fixed days after period end', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2026, 7, 20),
        payFrequency: weeklyPayFrequency,
        payDay: 'Friday',
        payPeriodAnchorDate: '2026-07-06',
        paydayRule: paydayDaysAfterPeriodEnd,
        paydayOffsetDays: 5,
      );

      expect(period.end, DateTime(2026, 7, 26));
      expect(period.payday, DateTime(2026, 7, 31));
    });

    test('supports following weekday after period end', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2026, 7, 20),
        payFrequency: weeklyPayFrequency,
        payDay: 'Friday',
        payPeriodAnchorDate: '2026-07-06',
        paydayRule: paydayFollowingWeekday,
        paydayWeekday: 'Friday',
      );

      expect(period.end, DateTime(2026, 7, 26));
      expect(period.payday, DateTime(2026, 7, 31));
    });

    test('supports next selected weekday after period end', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2026, 7, 20),
        payFrequency: weeklyPayFrequency,
        payDay: 'Friday',
        payPeriodAnchorDate: '2026-07-06',
        paydayRule: paydayNextSelectedWeekdayAfterPeriodEnd,
        paydaySelectedWeekday: DateTime.monday,
      );

      expect(period.end, DateTime(2026, 7, 26));
      expect(period.payday, DateTime(2026, 7, 27));
    });

    test('next selected weekday goes from Friday to Monday', () {
      expect(
        getNextWeekdayAfter(DateTime(2026, 7, 31), DateTime.monday),
        DateTime(2026, 8, 3),
      );
    });

    test('next selected weekday goes from Sunday to Tuesday', () {
      expect(
        getNextWeekdayAfter(DateTime(2026, 8, 30), DateTime.tuesday),
        DateTime(2026, 9, 1),
      );
    });

    test('next selected weekday goes from Monday to following Monday', () {
      expect(
        getNextWeekdayAfter(DateTime(2026, 8, 31), DateTime.monday),
        DateTime(2026, 9, 7),
      );
    });

    test('next selected weekday handles month rollover', () {
      expect(
        getNextWeekdayAfter(DateTime(2026, 9, 30), DateTime.friday),
        DateTime(2026, 10, 2),
      );
    });

    test('next selected weekday handles December to January rollover', () {
      expect(
        getNextWeekdayAfter(DateTime(2026, 12, 31), DateTime.monday),
        DateTime(2027, 1, 4),
      );
    });

    test('next selected weekday handles leap year dates', () {
      expect(
        getNextWeekdayAfter(DateTime(2028, 2, 29), DateTime.friday),
        DateTime(2028, 3, 3),
      );
    });
  });

  group('calendar monthly', () {
    test('runs from the first to the last day', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2026, 7, 15),
        payFrequency: calendarMonthlyPayFrequency,
        payDay: 'Friday',
      );

      expect(period.start, DateTime(2026, 7, 1));
      expect(period.end, DateTime(2026, 7, 31));
      expect(period.payday, DateTime(2026, 7, 31));
    });

    test('handles February', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2026, 2, 10),
        payFrequency: calendarMonthlyPayFrequency,
        payDay: 'Friday',
      );

      expect(period.start, DateTime(2026, 2, 1));
      expect(period.end, DateTime(2026, 2, 28));
    });

    test('handles leap-year February', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2028, 2, 10),
        payFrequency: calendarMonthlyPayFrequency,
        payDay: 'Friday',
      );

      expect(period.end, DateTime(2028, 2, 29));
    });

    test('supports payday in the following month', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2026, 7, 15),
        payFrequency: calendarMonthlyPayFrequency,
        payDay: 'Friday',
        paydayRule: paydayFixedDayFollowingMonth,
        paydayFixedDay: 5,
      );

      expect(period.start, DateTime(2026, 7, 1));
      expect(period.end, DateTime(2026, 7, 31));
      expect(period.payday, DateTime(2026, 8, 5));
    });

    test('maps legacy Monthly settings to Calendar monthly', () {
      final settings = AppSettings.fromJson({'payFrequency': 'Monthly'});

      expect(settings.payFrequency, calendarMonthlyPayFrequency);
    });
  });

  group('custom monthly', () {
    test('supports start day 26', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2026, 7, 1),
        payFrequency: customMonthlyPayFrequency,
        payDay: 'Friday',
        customPeriodStartDay: 26,
      );

      expect(period.start, DateTime(2026, 6, 26));
      expect(period.end, DateTime(2026, 7, 25));
    });

    test('handles short months', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2026, 2, 28),
        payFrequency: customMonthlyPayFrequency,
        payDay: 'Friday',
        customPeriodStartDay: 26,
      );

      expect(period.start, DateTime(2026, 2, 26));
      expect(period.end, DateTime(2026, 3, 25));
    });

    test('handles December to January', () {
      final period = getCurrentPayPeriod(
        date: DateTime(2027, 1, 1),
        payFrequency: customMonthlyPayFrequency,
        payDay: 'Friday',
        customPeriodStartDay: 26,
      );

      expect(period.start, DateTime(2026, 12, 26));
      expect(period.end, DateTime(2027, 1, 25));
    });
  });

  group('last Friday of every month', () {
    test('finds the last Friday of a month', () {
      expect(getLastFridayOfMonth(2026, 7), DateTime(2026, 7, 31));
      expect(getLastFridayOfMonth(2026, 8), DateTime(2026, 8, 28));
    });

    test('keeps the existing last-Friday rule', () {
      final period = getLastFridayPayPeriod(DateTime(2026, 7, 9));

      expect(period.start, DateTime(2026, 6, 29));
      expect(period.end, DateTime(2026, 7, 31));
      expect(period.payday, DateTime(2026, 7, 31));
    });

    test('rolls December into January', () {
      final period = getLastFridayPayPeriod(DateTime(2026, 12, 30));

      expect(period.start, DateTime(2026, 12, 28));
      expect(period.end, DateTime(2027, 1, 29));
      expect(period.payday, DateTime(2027, 1, 29));
    });

    test('includes today when today is payday', () {
      final period = getLastFridayPayPeriod(DateTime(2026, 7, 31));

      expect(period.start, DateTime(2026, 6, 29));
      expect(period.end, DateTime(2026, 7, 31));
      expect(period.contains(DateTime(2026, 7, 31)), isTrue);
    });

    test('advances after payday', () {
      final period = getLastFridayPayPeriod(DateTime(2026, 8, 1));

      expect(period.start, DateTime(2026, 8, 3));
      expect(period.end, DateTime(2026, 8, 28));
    });
  });
}
