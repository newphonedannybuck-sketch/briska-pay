import 'package:briska/src/home_dashboard_summary.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/pay_schedule.dart';
import 'package:briska/src/work_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:briska/src/widgets/home_dashboard_widgets.dart';

void main() {
  final period = PayPeriodRange(
    start: DateTime(2026, 11),
    end: DateTime(2026, 11, 30),
    payday: DateTime(2026, 11, 30),
    periodLabel: 'November',
  );
  WorkEntry entry(
    String id,
    DateTime date, {
    Object type = EntryType.workDay,
    double hours = 0,
    double pay = 0,
    double deduction = 0,
  }) => WorkEntry(
    id: id,
    date: date,
    entryType: type,
    siteName: '',
    startTime: '',
    finishTime: '',
    breakMinutes: 0,
    hourlyRateUsed: 20,
    dailyAllowance: 0,
    jobUplift: 0,
    totalHours: hours,
    wages: pay,
    totalPay: pay,
    deductionAmount: deduction,
    notes: '',
  );

  test(
    'separate holiday types count calendar dates, including blank-hour days',
    () {
      final summary = HomeDashboardSummary([
        entry('h1', DateTime(2026, 11, 2), type: 'Holiday'),
        entry('h2', DateTime(2026, 11, 2, 17), type: 'Holiday'),
        entry('h3', DateTime(2026, 11, 3), type: 'Holiday'),
        entry('b1', DateTime(2026, 11, 2), type: 'bankHoliday'),
        entry('b2', DateTime(2026, 11, 2, 12), type: 'BankHoliday'),
        entry('w1', DateTime(2026, 11, 2), hours: 4),
        entry('w2', DateTime(2026, 11, 2, 14), hours: 3),
        entry('sick', DateTime(2026, 11, 4), type: EntryType.sickDay),
      ], period);
      expect(summary.holidays.days, 2);
      expect(summary.bankHolidays.days, 1);
      expect(summary.daysWorked, 1);
      expect(summary.holidays.hasRecordedHours, isFalse);
      expect(summary.holidays.recordedHours, 0);
    },
  );

  test(
    'mixed hours sum only recorded values and filter selected period inclusively',
    () {
      final entries = [
        entry(
          'start',
          DateTime(2026, 11, 1),
          type: EntryType.holiday,
          hours: 3.5,
        ),
        entry('blank', DateTime(2026, 11, 15), type: EntryType.holiday),
        entry(
          'end',
          DateTime(2026, 11, 30, 23),
          type: EntryType.holiday,
          hours: 2,
        ),
        entry(
          'bank',
          DateTime(2026, 11, 12),
          type: EntryType.bankHoliday,
          hours: 4,
        ),
        entry(
          'before',
          DateTime(2026, 10, 31),
          type: EntryType.holiday,
          hours: 24,
          pay: 100,
        ),
        entry(
          'after',
          DateTime(2026, 12, 1),
          type: EntryType.bankHoliday,
          hours: 24,
          pay: 100,
        ),
      ];
      final summary = HomeDashboardSummary(entries, period);
      expect(summary.holidays.days, 3);
      expect(summary.holidays.recordedHours, 5.5);
      expect(summary.holidays.hasRecordedHours, isTrue);
      expect(summary.bankHolidays.days, 1);
      expect(summary.bankHolidays.recordedHours, 4);
      expect(summary.earnings.map((point) => point.date), [
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 12),
        DateTime(2026, 11, 15),
        DateTime(2026, 11, 30),
      ]);
      final december = HomeDashboardSummary(
        entries,
        PayPeriodRange(
          start: DateTime(2026, 12),
          end: DateTime(2026, 12, 31),
          payday: DateTime(2026, 12, 31),
          periodLabel: 'December',
        ),
      );
      expect(december.holidays.days, 0);
      expect(december.bankHolidays.days, 1);
    },
  );

  test(
    'existing storage collapses missing and explicit zero hours without inventing hours',
    () {
      final json = entry(
        'blank',
        DateTime(2026, 11, 4),
        type: EntryType.holiday,
      ).toJson();
      json.remove('totalHours');
      final blank = WorkEntry.fromJson(json);
      final zero = WorkEntry.fromJson({...json, 'totalHours': 0});
      expect(blank.totalHours, zero.totalHours);
      final summary = HomeTimeOffSummary([blank, zero]);
      expect(summary.days, 1);
      expect(summary.recordedHours, 0);
      expect(summary.hasRecordedHours, isFalse);
    },
  );

  test(
    'chart groups and sorts dates, preserves gross adjustments and downward steps',
    () {
      final entries = [
        entry('later', DateTime(2026, 11, 9), pay: -175),
        entry('first-b', DateTime(2026, 11, 2, 18), pay: 25, deduction: 10),
        entry('first-a', DateTime(2026, 11, 2, 8), pay: 100),
        entry('last', DateTime(2026, 11, 10), pay: 20),
        entry('outside', DateTime(2026, 12, 1), pay: 999),
      ];
      final summary = HomeDashboardSummary(entries, period);
      expect(summary.earnings.map((point) => point.total), [125, -50, -30]);
      expect(summary.earnings.last.date, DateTime(2026, 11, 10));
      expect(summary.earnings.last.total, summary.pay.totalExpectedPay);
      expect(
        summary.pay.totalExpectedPay,
        WorkCalculator.summarize(entries.take(4)).totalExpectedPay,
      );
      expect(summary.pay.totalNetPay, -40);
    },
  );

  test(
    'empty, single, zero and entirely negative earnings remain truthful',
    () {
      expect(HomeDashboardSummary([], period).earnings, isEmpty);
      for (final value in [0.0, -25.0, 30.0]) {
        final summary = HomeDashboardSummary([
          entry('one', DateTime(2026, 11, 8), pay: value),
        ], period);
        expect(summary.earnings.length, 1);
        expect(summary.earnings.single.date, DateTime(2026, 11, 8));
        expect(summary.earnings.single.total, value);
      }
    },
  );
  testWidgets(
    'chart paints empty, single, zero and negative series with accessible data',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        for (final values in <List<double>>[
          [],
          [0],
          [-25],
          [20],
          [100, -20, 0],
        ]) {
          final points = [
            for (var i = 0; i < values.length; i++)
              RecordedEarningsPoint(DateTime(2026, 11, i + 2), values[i]),
          ];
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 288,
                  child: HomeEarningsChart(
                    points: points,
                    start: period.start,
                    end: period.end,
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(
            find.bySemanticsLabel(
              values.isEmpty
                  ? 'No recorded earnings in this pay period.'
                  : RegExp('Cumulative recorded gross earnings.*No forecast.'),
            ),
            findsOneWidget,
          );
        }
      } finally {
        semantics.dispose();
      }
    },
  );
}
