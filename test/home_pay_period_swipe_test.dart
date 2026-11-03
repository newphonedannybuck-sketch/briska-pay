import 'package:briska/src/display_format.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/pay_schedule.dart';
import 'package:briska/src/premium_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WorkEntry entry({
    required String id,
    required DateTime date,
    required String start,
    required String finish,
    int breakMinutes = 0,
    double rate = 10,
    double allowance = 0,
    double uplift = 0,
  }) => WorkEntry(
    id: id,
    date: date,
    siteName: id,
    startTime: start,
    finishTime: finish,
    breakMinutes: breakMinutes,
    hourlyRateUsed: rate,
    dailyAllowance: allowance,
    jobUplift: uplift,
    totalHours: 0,
    wages: 0,
    totalPay: 0,
    notes: '',
  );

  Future<void> pumpHome(
    WidgetTester tester, {
    required AppSettings settings,
    required List<WorkEntry> entries,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            entries: entries,
            settings: settings,
            onViewEntries: () {},
            onAddEntry: () {},
            onOpenCalendar: () {},
            onOpenReports: () {},
            onOpenExport: () {},
            onConfigurePayday: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> swipeRight(WidgetTester tester) async {
    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
  }

  Future<void> swipeLeft(WidgetTester tester) async {
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
  }

  String rangeLabel(PayPeriodRange period) =>
      '${formatCompactDate(period.start)} – ${formatCompactDate(period.end)}';

  Finder pagerText(String value) =>
      find.descendant(of: find.byType(PageView), matching: find.text(value));

  testWidgets('four distinct weekly periods map one-to-one to pager indices', (
    tester,
  ) async {
    final today = DateTime.now();
    final settings = AppSettings(
      onboardingCompleted: true,
      payFrequency: weeklyPayFrequency,
      payPeriodAnchorDate: DateTime(
        today.year,
        today.month,
        today.day,
      ).toIso8601String(),
    );
    final current = getCurrentPayPeriodForSettings(
      date: today,
      settings: settings,
    );
    final previous = getCurrentPayPeriodForSettings(
      date: current.start.subtract(const Duration(days: 1)),
      settings: settings,
    );
    final previousTwo = getCurrentPayPeriodForSettings(
      date: previous.start.subtract(const Duration(days: 1)),
      settings: settings,
    );
    final oldest = getCurrentPayPeriodForSettings(
      date: previousTwo.start.subtract(const Duration(days: 1)),
      settings: settings,
    );
    final entries = [
      entry(
        id: 'current',
        date: current.start,
        start: '08:00',
        finish: '16:00',
      ),
      entry(
        id: 'previous-a',
        date: previous.start,
        start: '08:00',
        finish: '16:00',
        breakMinutes: 30,
        rate: 20,
        allowance: 10,
        uplift: 15,
      ),
      entry(
        id: 'previous-b',
        date: previous.end,
        start: '08:00',
        finish: '12:00',
        rate: 20,
        allowance: 5,
        uplift: 2,
      ),
      entry(
        id: 'previous-two',
        date: previousTwo.start,
        start: '09:00',
        finish: '15:00',
      ),
      entry(
        id: 'oldest',
        date: oldest.start,
        start: '08:00',
        finish: '10:00',
        rate: 15,
      ),
    ];

    await pumpHome(tester, settings: settings, entries: entries);

    final pager = tester.widget<PageView>(find.byType(PageView));
    expect(
      (pager.childrenDelegate as SliverChildBuilderDelegate).childCount,
      4,
    );
    expect(find.text('CURRENT PAY PERIOD'), findsOneWidget);
    expect(find.text(rangeLabel(current)), findsOneWidget);
    expect(pagerText('£80.00'), findsOneWidget);

    // Index zero is the newest period and cannot advance into the future.
    await swipeLeft(tester);
    expect(find.text('CURRENT PAY PERIOD'), findsOneWidget);
    expect(find.text(rangeLabel(current)), findsOneWidget);

    await swipeRight(tester);
    expect(find.text('PREVIOUS PAY PERIOD'), findsOneWidget);
    expect(find.text(rangeLabel(previous)), findsOneWidget);
    expect(pagerText('£262.00'), findsOneWidget);
    expect(pagerText('11.5'), findsOneWidget);
    expect(pagerText('2'), findsOneWidget);
    expect(pagerText('£17.00'), findsOneWidget);

    await swipeRight(tester);
    expect(find.text(rangeLabel(previousTwo)), findsOneWidget);
    expect(pagerText('£60.00'), findsOneWidget);
    expect(pagerText('6'), findsOneWidget);
    expect(pagerText('1'), findsOneWidget);

    await swipeRight(tester);
    expect(find.text(rangeLabel(oldest)), findsOneWidget);
    expect(pagerText('£30.00'), findsOneWidget);
    expect(pagerText('2'), findsOneWidget);
    expect(pagerText('1'), findsOneWidget);

    await swipeRight(tester);
    expect(find.text(rangeLabel(oldest)), findsOneWidget);

    await swipeLeft(tester);
    expect(find.text(rangeLabel(previousTwo)), findsOneWidget);
    await swipeLeft(tester);
    expect(find.text(rangeLabel(previous)), findsOneWidget);
    await swipeLeft(tester);
    expect(find.text('CURRENT PAY PERIOD'), findsOneWidget);
    expect(find.text(rangeLabel(current)), findsOneWidget);
    await swipeLeft(tester);
    expect(find.text(rangeLabel(current)), findsOneWidget);
  });

  test('available periods are data-bounded and unique for Last Friday', () {
    const settings = AppSettings(
      payFrequency: lastFridayPayFrequency,
      onboardingCompleted: true,
    );
    final current = getCurrentPayPeriodForSettings(
      date: DateTime(2026, 9, 1),
      settings: settings,
    );
    final previous = getPreviousPayPeriodForSettings(
      period: current,
      settings: settings,
    );
    final oldest = getPreviousPayPeriodForSettings(
      period: previous,
      settings: settings,
    );
    final periods = getAvailablePayPeriodsForSettings(
      date: DateTime(2026, 9, 1),
      settings: settings,
      entryDates: [oldest.start, previous.start, current.start],
    );

    expect(periods, hasLength(3));
    expect(periods.first.start, oldest.start);
    expect(periods.last.start, current.start);
    final keys = periods
        .map(
          (period) =>
              '${period.start.toIso8601String()}-${period.end.toIso8601String()}',
        )
        .toSet();
    expect(keys.length, periods.length);
  });

  testWidgets('calendar monthly navigation crosses a month boundary', (
    tester,
  ) async {
    final today = DateTime.now();
    const settings = AppSettings(
      onboardingCompleted: true,
      payFrequency: calendarMonthlyPayFrequency,
    );
    final current = getCurrentPayPeriodForSettings(
      date: today,
      settings: settings,
    );
    final previous = getCurrentPayPeriodForSettings(
      date: current.start.subtract(const Duration(days: 1)),
      settings: settings,
    );

    await pumpHome(
      tester,
      settings: settings,
      entries: [
        entry(
          id: 'last-month',
          date: previous.end,
          start: '08:00',
          finish: '13:00',
          rate: 12,
          allowance: 4,
          uplift: 3,
        ),
      ],
    );

    expect(find.text(rangeLabel(current)), findsOneWidget);
    await swipeRight(tester);
    expect(find.text(rangeLabel(previous)), findsOneWidget);
    expect(previous.end.isBefore(current.start), isTrue);
    expect(pagerText('£67.00'), findsOneWidget);
    expect(pagerText('5'), findsOneWidget);
    expect(pagerText('1'), findsOneWidget);
    expect(pagerText('£3.00'), findsOneWidget);
  });

  testWidgets('ordinary Home rebuild keeps the selected historical period', (
    tester,
  ) async {
    final today = DateTime.now();
    final settings = AppSettings(
      onboardingCompleted: true,
      payFrequency: fortnightlyPayFrequency,
      payPeriodAnchorDate: DateTime(
        today.year,
        today.month,
        today.day,
      ).toIso8601String(),
    );
    final current = getCurrentPayPeriodForSettings(
      date: today,
      settings: settings,
    );
    final previous = getCurrentPayPeriodForSettings(
      date: current.start.subtract(const Duration(days: 1)),
      settings: settings,
    );

    final existing = entry(
      id: 'existing-entry',
      date: previous.end,
      start: '08:00',
      finish: '09:00',
    );
    await pumpHome(tester, settings: settings, entries: [existing]);
    await swipeRight(tester);
    expect(find.text(rangeLabel(previous)), findsOneWidget);

    await pumpHome(
      tester,
      settings: settings,
      entries: [
        existing,
        entry(
          id: 'new-entry',
          date: previous.start,
          start: '08:00',
          finish: '09:00',
        ),
      ],
    );
    expect(find.text(rangeLabel(previous)), findsOneWidget);
    expect(pagerText('£20.00'), findsOneWidget);
  });
}
