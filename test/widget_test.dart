import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:briska/main.dart';
import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/currency.dart';
import 'package:briska/src/display_format.dart';
import 'package:briska/src/local_storage.dart';
import 'package:briska/src/pay_schedule.dart';
import 'package:briska/src/premium_home_screen.dart';
import 'package:briska/src/release_info.dart';
import 'package:briska/src/work_calculator.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    LocalStorage.saveEntriesOverride = null;
    LocalStorage.readStringOverride = null;
  });

  final sampleEntries = [
    WorkEntry(
      id: 'home',
      date: DateTime(2026, 7, 10),
      siteName: 'Home Site',
      startTime: '08:00',
      finishTime: '16:30',
      breakMinutes: 30,
      workLocation: 'Home',
      hourlyRateUsed: 20,
      dailyAllowance: 0,
      jobUplift: 0,
      totalHours: 8,
      wages: 160,
      totalPay: 160,
      notes: '',
    ),
    WorkEntry(
      id: 'away',
      date: DateTime(2026, 7, 8),
      siteName: 'Away Site',
      startTime: '08:00',
      finishTime: '17:00',
      breakMinutes: 30,
      workLocation: 'Away',
      hourlyRateUsed: 20,
      dailyAllowance: 10,
      jobUplift: 25,
      totalHours: 8.5,
      wages: 170,
      totalPay: 205,
      notes: 'Crane work',
    ),
    WorkEntry(
      id: 'holiday',
      entryType: 'Holiday',
      date: DateTime(2026, 6, 30),
      siteName: '',
      startTime: '',
      finishTime: '',
      breakMinutes: 0,
      workLocation: 'Home',
      hourlyRateUsed: 20,
      dailyAllowance: 0,
      jobUplift: 0,
      totalHours: 8,
      wages: 160,
      totalPay: 160,
      notes: '',
    ),
  ];

  ExportedFileRecord exportRecord({
    required String path,
    String id = 'export',
    String fileName = 'Briska_July_2026_Timesheet.pdf',
    int? fileSize = 1536,
  }) => ExportedFileRecord(
    id: id,
    fileName: fileName,
    fileType: 'PDF Timesheet',
    filePath: path,
    exportedAt: DateTime(2026, 7, 31),
    periodLabel: 'July 2026',
    workDays: 4,
    totalHours: 32,
    totalPay: 640,
    fileSize: fileSize,
  );

  Future<void> expectNoLayoutOverflow(
    WidgetTester tester,
    Future<void> Function() action,
  ) async {
    final originalOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (details) {
      errors.add(details.toString());
    };
    try {
      await action();
    } finally {
      FlutterError.onError = originalOnError;
    }

    final overflowErrors = errors.where((text) {
      return text.contains('RenderFlex overflowed') ||
          text.contains('A RenderFlex overflowed') ||
          text.contains('BOTTOM OVERFLOWED') ||
          text.contains('RIGHT OVERFLOWED') ||
          text.contains('pixels overflowed');
    }).toList();
    expect(overflowErrors, isEmpty, reason: overflowErrors.join('\n\n'));
  }

  Future<void> pumpResponsiveApp(
    WidgetTester tester, {
    required Size size,
    double textScaleFactor = 1,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      BriskaApp(key: UniqueKey(), initialEntries: sampleEntries),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('first launch shows onboarding', (tester) async {
    await tester.pumpWidget(const BriskaApp(initialSettings: AppSettings()));

    expect(find.text('Welcome to Briska Pay'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Employer / company'), findsOneWidget);
    expect(find.text('Primary rate name'), findsOneWidget);
    expect(find.text('Primary hourly rate'), findsOneWidget);
    expect(find.text('Secondary rate name'), findsOneWidget);
    expect(find.text('Secondary hourly rate'), findsOneWidget);
    expect(find.textContaining('allowance', findRichText: true), findsNothing);
    expect(find.text('Enter your full name'), findsOneWidget);
    expect(find.text('Enter employer or company name'), findsOneWidget);
    expect(find.text('e.g. 20.00'), findsOneWidget);
    expect(find.text('e.g. 25.00'), findsOneWidget);
    expect(find.text('Start Using Briska Pay'), findsOneWidget);
  });

  testWidgets('beta checklist persists progress and confirms bulk actions', (
    tester,
  ) async {
    Future<void> pumpChecklist() async {
      await tester.pumpWidget(const MaterialApp(home: BetaChecklistScreen()));
      await tester.pumpAndSettle();
    }

    await pumpChecklist();
    expect(find.text('0 of 21 tests completed'), findsOneWidget);

    await tester.tap(find.text('Onboarding'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 21 tests completed'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpChecklist();
    expect(find.text('1 of 21 tests completed'), findsOneWidget);

    await tester.tap(find.text('Mark all complete'));
    await tester.pumpAndSettle();
    expect(find.text('Mark all complete?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('21 of 21 tests completed'), findsOneWidget);
    expect(find.text('Briska Pay is ready for release'), findsOneWidget);

    await tester.tap(find.text('Reset checklist'));
    await tester.pumpAndSettle();
    expect(find.text('Reset checklist?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 21 tests completed'), findsOneWidget);
  });

  testWidgets('About keeps public legal and support navigation working', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'Briska Pay',
      packageName: 'com.berkzerker.briskapay',
      version: '9.8.7',
      buildNumber: '654',
      buildSignature: '',
    );
    await tester.pumpWidget(const MaterialApp(home: AboutBriskaScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Release'), findsNothing);
    expect(find.text('9.8.7 (654)'), findsOneWidget);
    expect(find.textContaining('RC'), findsNothing);
    expect(find.textContaining('Beta'), findsNothing);
    expect(find.text('Berkzerker'), findsOneWidget);
    expect(find.text('berkzerkatron@hotmail.com'), findsOneWidget);
    expect(find.text('© 2026 Berkzerker'), findsOneWidget);

    for (final link in ['Privacy Policy', 'Terms of Use', 'Support']) {
      final linkTile = find.widgetWithText(ListTile, link);
      await tester.ensureVisible(linkTile);
      await tester.tap(linkTile);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, link), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    await tester.ensureVisible(find.text('Open Source Licences'));
    await tester.tap(find.text('Open Source Licences'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('onboarding saves trimmed company name', (tester) async {
    AppSettings? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          initialSettings: const AppSettings(),
          onComplete: (settings) => saved = settings,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'Daniel Beckett');
    await tester.enterText(
      find.byType(TextField).at(1),
      '  Example Company Ltd  ',
    );
    await tester.enterText(find.byType(TextField).at(3), '20');
    await tester.enterText(find.byType(TextField).at(5), '20');
    await tester.ensureVisible(find.text('Start Using Briska Pay'));
    await tester.tap(find.text('Start Using Briska Pay'));
    await tester.pump();

    expect(saved?.fullName, 'Daniel Beckett');
    expect(saved?.companyName, 'Example Company Ltd');
  });

  testWidgets('onboarding keyboard actions move focus and dismiss on done', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          initialSettings: const AppSettings(),
          onComplete: (_) {},
        ),
      ),
    );

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(6));

    for (var index = 0; index < 5; index++) {
      await tester.showKeyboard(fields.at(index));
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(fields.at(index + 1)).focusNode?.hasFocus,
        isTrue,
      );
    }

    for (final index in [3, 5]) {
      final keyboardType = tester
          .widget<TextField>(fields.at(index))
          .keyboardType;
      expect(
        keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
    }

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fields.at(5)).focusNode?.hasFocus, isFalse);
  });

  testWidgets('Briska home and navigation render', (tester) async {
    await tester.pumpWidget(const BriskaApp());

    expect(
      find.text('Add your first day to start tracking your pay.'),
      findsOneWidget,
    );
    expect(find.text('Welcome back.'), findsNothing);
    expect(find.text('CURRENT PAY PERIOD'), findsOneWidget);
    expect(find.text('Estimated gross pay'), findsOneWidget);
    expect(find.text('Estimated earnings'), findsNothing);
    expect(find.text('Time through pay period'), findsOneWidget);
    expect(find.text('Period progress'), findsNothing);
    expect(find.text('Next payday'), findsOneWidget);
    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Your work starts here'), findsOneWidget);
    expect(
      find.text('Add your first day to see your earnings and activity.'),
      findsOneWidget,
    );
    expect(find.text('Add Day'), findsWidgets);

    await tester.tap(find.text('Entries'));
    await tester.pumpAndSettle();
    expect(find.text('Entries'), findsNWidgets(2));
    expect(find.text('Your recorded days and earnings.'), findsOneWidget);
    expect(find.text('Work entries'), findsNothing);
  });

  testWidgets('production navigation never reaches legacy screens', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());

    for (final destination in [
      'Home',
      'Entries',
      'Reports',
      'Export',
      'Settings',
    ]) {
      await tester.tap(find.text(destination).last);
      await tester.pumpAndSettle();
      expect(find.byType(LegacyHomeScreen), findsNothing);
      expect(find.byType(ReportsScreen), findsNothing);
    }
  });

  testWidgets('Recent Activity opens exact entry details and existing editor', (
    tester,
  ) async {
    final overnight = WorkEntry(
      id: 'overnight-detail',
      date: DateTime(2026, 8, 30),
      siteName: 'Night Site',
      startTime: '22:00',
      finishTime: '06:00',
      breakMinutes: 0,
      hourlyRateUsed: 20,
      dailyAllowance: 10,
      jobUplift: 5,
      totalHours: 8,
      wages: 160,
      totalPay: 175,
      deductionAmount: 50,
      deductionReason: 'Advance',
      notes: 'Night cover',
    );
    await tester.pumpWidget(BriskaApp(initialEntries: [overnight]));
    await tester.pumpAndSettle();
    final recentWork = find.byKey(
      const ValueKey('recent-activity-overnight-detail'),
    );
    await tester.ensureVisible(recentWork);
    await tester.tap(recentWork);
    await tester.pumpAndSettle();

    expect(find.text('Entry Details'), findsOneWidget);
    expect(find.text('Work Day'), findsOneWidget);
    expect(find.text('Night Site'), findsWidgets);
    expect(find.text('22:00 – 06:00 (+1 day)'), findsOneWidget);
    expect(find.text('Advance'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('entry-details-gross-pay')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('entry-details-net-pay')), findsOneWidget);
    expect(find.text('Night cover'), findsOneWidget);

    final editEntry = find.text('Edit Entry');
    await tester.ensureVisible(editEntry);
    await tester.tap(editEntry);
    await tester.pumpAndSettle();
    expect(find.text('Entry Details'), findsNothing);
    expect(find.text('Edit Day'), findsOneWidget);
    expect(find.text('Update Entry'), findsOneWidget);
  });

  testWidgets('Recent Activity details adapt to every non-work day type', (
    tester,
  ) async {
    final types = <WorkEntry>[
      WorkEntry(
        id: 'detail-holiday',
        entryType: EntryType.holiday,
        date: DateTime(2026, 8, 30),
        siteName: '',
        startTime: '',
        finishTime: '',
        breakMinutes: 0,
        hourlyRateUsed: 20,
        dailyAllowance: 0,
        jobUplift: 5,
        totalHours: 8,
        wages: 160,
        totalPay: 165,
        notes: '',
      ),
      WorkEntry(
        id: 'detail-bank',
        entryType: EntryType.bankHoliday,
        date: DateTime(2026, 8, 29),
        siteName: '',
        startTime: '',
        finishTime: '',
        breakMinutes: 0,
        hourlyRateUsed: 0,
        dailyAllowance: 0,
        jobUplift: 5,
        totalHours: 0,
        wages: 0,
        totalPay: 5,
        notes: '',
        isPaidBankHoliday: false,
      ),
      WorkEntry(
        id: 'detail-sick',
        entryType: EntryType.sickDay,
        date: DateTime(2026, 8, 28),
        siteName: '',
        startTime: '',
        finishTime: '',
        breakMinutes: 0,
        hourlyRateUsed: 20,
        dailyAllowance: 0,
        jobUplift: 0,
        totalHours: 8,
        wages: 160,
        totalPay: 160,
        notes: '',
        isPaidSickDay: true,
      ),
      WorkEntry(
        id: 'detail-off',
        entryType: EntryType.unpaidDayOff,
        date: DateTime(2026, 8, 27),
        siteName: '',
        startTime: '',
        finishTime: '',
        breakMinutes: 0,
        hourlyRateUsed: 0,
        dailyAllowance: 0,
        jobUplift: 0,
        totalHours: 0,
        wages: 0,
        totalPay: 0,
        notes: 'Personal',
      ),
    ];
    await tester.pumpWidget(BriskaApp(initialEntries: types));
    await tester.pumpAndSettle();
    for (final value in types) {
      final recent = find.byKey(ValueKey('recent-activity-${value.id}'));
      await tester.ensureVisible(recent);
      await tester.tap(recent);
      await tester.pumpAndSettle();
      expect(find.text('Entry Details'), findsOneWidget);
      expect(find.text('Site / Job'), findsNothing);
      expect(find.text('Time'), findsNothing);
      expect(find.text('Gross Pay'), findsOneWidget);
      expect(find.text('Net Pay'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Recent Activity details sheet is responsive in dark theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await expectNoLayoutOverflow(tester, () async {
      final value = WorkEntry(
        id: 'detail-small',
        date: DateTime(2026, 8, 30),
        siteName: 'Small screen overnight site',
        startTime: '22:00',
        finishTime: '06:00',
        breakMinutes: 30,
        hourlyRateUsed: 20,
        dailyAllowance: 10,
        jobUplift: 5,
        totalHours: 7.5,
        wages: 150,
        totalPay: 165,
        deductionAmount: 5,
        deductionReason: 'Uniform',
        notes: 'Responsive details',
      );
      await tester.pumpWidget(
        BriskaApp(
          initialEntries: [value],
          initialSettings: const AppSettings(
            onboardingCompleted: true,
            themeMode: 'dark',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final recent = find.byKey(const ValueKey('recent-activity-detail-small'));
      await tester.ensureVisible(recent);
      await tester.tap(recent);
      await tester.pumpAndSettle();
      expect(find.text('Entry Details'), findsOneWidget);
      expect(find.text('22:00 – 06:00 (+1 day)'), findsOneWidget);
    });
  });

  testWidgets('Entries uses singular and plural recorded-day counts', (
    tester,
  ) async {
    for (final entries in [
      [sampleEntries.first],
      sampleEntries,
    ]) {
      await tester.pumpWidget(
        BriskaApp(key: UniqueKey(), initialEntries: entries),
      );
      await tester.tap(find.text('Entries'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          entries.length == 1 ? '1 Day recorded' : '3 Days recorded',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('work days'), findsNothing);
    }
  });

  testWidgets('Home welcomes returning users with saved work days', (
    tester,
  ) async {
    await tester.pumpWidget(BriskaApp(initialEntries: sampleEntries));

    expect(find.text('Welcome back.'), findsOneWidget);
    expect(
      find.text('Add your first day to start tracking your pay.'),
      findsNothing,
    );
  });

  test('Home payday countdown uses clear relative wording', () {
    expect(paydayCountdownLabel(0), 'Today');
    expect(paydayCountdownLabel(1), 'Tomorrow');
    expect(paydayCountdownLabel(5), 'In 5 days');
  });

  testWidgets('Home day count is clear and responsive', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    WorkEntry currentEntry(int index) => WorkEntry(
      id: 'current-$index',
      date: DateTime.now(),
      siteName: 'Site $index',
      startTime: '08:00',
      finishTime: '16:30',
      breakMinutes: 30,
      workLocation: 'Home',
      hourlyRateUsed: 20,
      dailyAllowance: 0,
      jobUplift: 0,
      totalHours: 8,
      wages: 160,
      totalPay: 160,
      notes: '',
    );

    final scenarios = [
      (count: 0, size: const Size(360, 640), textScaleFactor: 1.0),
      (count: 1, size: const Size(360, 640), textScaleFactor: 1.0),
      (count: 3, size: const Size(360, 640), textScaleFactor: 1.0),
      (count: 3, size: const Size(320, 568), textScaleFactor: 1.0),
      (count: 3, size: const Size(360, 640), textScaleFactor: 1.5),
      (count: 3, size: const Size(360, 640), textScaleFactor: 2.0),
    ];

    for (final scenario in scenarios) {
      await expectNoLayoutOverflow(tester, () async {
        tester.view
          ..physicalSize = scenario.size
          ..devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue =
            scenario.textScaleFactor;
        await tester.pumpWidget(
          BriskaApp(
            key: UniqueKey(),
            initialEntries: List.generate(scenario.count, currentEntry),
          ),
        );
        await tester.pumpAndSettle();

        final metric = find.byKey(const ValueKey('home-days-recorded-metric'));
        expect(metric, findsOneWidget);
        expect(
          find.descendant(
            of: metric,
            matching: find.text(scenario.count.toString()),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: metric,
            matching: find.text(
              scenario.count == 1 ? 'Day recorded' : 'Days recorded',
            ),
          ),
          findsOneWidget,
        );
        expect(find.text('Work days'), findsNothing);
      });
    }
  });

  testWidgets('Home hours metric is clear and responsive', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    WorkEntry currentEntry({required String id, required String finishTime}) =>
        WorkCalculator.recalculateEntry(
          WorkEntry(
            id: id,
            date: DateTime.now(),
            siteName: 'Hours test',
            startTime: '08:00',
            finishTime: finishTime,
            breakMinutes: 0,
            workLocation: 'Home',
            hourlyRateUsed: 20,
            dailyAllowance: 0,
            jobUplift: 0,
            totalHours: 0,
            wages: 0,
            totalPay: 0,
            notes: '',
          ),
        );

    final scenarios = [
      (
        entries: const <WorkEntry>[],
        value: '0',
        label: 'Hours',
        size: const Size(360, 640),
        textScaleFactor: 1.0,
      ),
      (
        entries: [currentEntry(id: 'one', finishTime: '09:00')],
        value: '1',
        label: 'Hour',
        size: const Size(360, 640),
        textScaleFactor: 1.0,
      ),
      (
        entries: [currentEntry(id: 'fraction', finishTime: '09:30')],
        value: '1.5',
        label: 'Hours',
        size: const Size(360, 640),
        textScaleFactor: 1.0,
      ),
      (
        entries: [currentEntry(id: 'multiple', finishTime: '16:00')],
        value: '8',
        label: 'Hours',
        size: const Size(320, 568),
        textScaleFactor: 1.0,
      ),
      (
        entries: [currentEntry(id: 'large-text-1', finishTime: '16:00')],
        value: '8',
        label: 'Hours',
        size: const Size(360, 640),
        textScaleFactor: 1.5,
      ),
      (
        entries: [currentEntry(id: 'large-text-2', finishTime: '16:00')],
        value: '8',
        label: 'Hours',
        size: const Size(360, 640),
        textScaleFactor: 2.0,
      ),
    ];

    for (final scenario in scenarios) {
      await expectNoLayoutOverflow(tester, () async {
        tester.view
          ..physicalSize = scenario.size
          ..devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue =
            scenario.textScaleFactor;
        await tester.pumpWidget(
          BriskaApp(key: UniqueKey(), initialEntries: scenario.entries),
        );
        await tester.pumpAndSettle();

        final metric = find.byKey(const ValueKey('home-hours-metric'));
        expect(metric, findsOneWidget);
        expect(
          find.descendant(of: metric, matching: find.text(scenario.value)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: metric, matching: find.text(scenario.label)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: metric,
            matching: find.text('${scenario.value}h'),
          ),
          findsNothing,
        );
      });
    }
  });

  testWidgets('Home Quick actions adapt to accessible text scales', (
    tester,
  ) async {
    for (final scenario in [
      (textScaleFactor: 1.0, usesGrid: false),
      (textScaleFactor: 1.5, usesGrid: true),
      (textScaleFactor: 2.0, usesGrid: true),
    ]) {
      await expectNoLayoutOverflow(tester, () async {
        await pumpResponsiveApp(
          tester,
          size: const Size(360, 640),
          textScaleFactor: scenario.textScaleFactor,
        );

        final row = find.byKey(const ValueKey('quick-actions-row'));
        final grid = find.byKey(const ValueKey('quick-actions-grid'));
        expect(row, scenario.usesGrid ? findsNothing : findsOneWidget);
        expect(grid, scenario.usesGrid ? findsOneWidget : findsNothing);
        final layout = scenario.usesGrid ? grid : row;
        final touchTargets = find.descendant(
          of: layout,
          matching: find.byType(InkWell),
        );
        expect(touchTargets, findsNWidgets(4));
        for (final target in touchTargets.evaluate()) {
          final size = tester.getSize(
            find.byElementPredicate((e) => e == target),
          );
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        for (final label in ['Add Day', 'Calendar', 'Reports', 'Export']) {
          final labelFinder = find.descendant(
            of: layout,
            matching: find.text(label),
          );
          expect(labelFinder, findsOneWidget);
          if (scenario.usesGrid) {
            expect(
              tester
                  .renderObject<RenderParagraph>(labelFinder)
                  .didExceedMaxLines,
              isFalse,
              reason:
                  '$label was truncated at ${scenario.textScaleFactor}x text scale',
            );
          }
        }
      });
    }
  });

  testWidgets('main screens avoid layout overflow across responsive sizes', (
    tester,
  ) async {
    final scenarios = [
      (size: const Size(320, 568), textScaleFactor: 1.0),
      (size: const Size(390, 844), textScaleFactor: 1.0),
      (size: const Size(568, 320), textScaleFactor: 1.0),
      (size: const Size(768, 1024), textScaleFactor: 1.0),
      (size: const Size(360, 640), textScaleFactor: 1.5),
      (size: const Size(360, 640), textScaleFactor: 2.0),
      (size: const Size(320, 568), textScaleFactor: 1.5),
      (size: const Size(320, 568), textScaleFactor: 2.0),
    ];

    for (final scenario in scenarios) {
      await expectNoLayoutOverflow(tester, () async {
        await pumpResponsiveApp(
          tester,
          size: scenario.size,
          textScaleFactor: scenario.textScaleFactor,
        );

        for (final icon in [
          Icons.calendar_view_day_outlined,
          Icons.bar_chart_outlined,
          Icons.file_download_outlined,
          Icons.settings_outlined,
        ]) {
          await tester.tap(find.byIcon(icon).last);
          await tester.pumpAndSettle();
        }

        await pumpResponsiveApp(
          tester,
          size: scenario.size,
          textScaleFactor: scenario.textScaleFactor,
        );
        await tester.tap(find.byTooltip('Add Day'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save Entry'));
        await tester.pumpAndSettle();
      });
    }
  });

  testWidgets('Currency values render with clean GBP symbol', (tester) async {
    await tester.pumpWidget(BriskaApp(initialEntries: sampleEntries));
    await tester.pumpAndSettle();

    expect(find.text('\u00A3205.00'), findsOneWidget);
    expect(find.text('\u00A30.00'), findsWidgets);
    expect(find.textContaining(String.fromCharCode(0x00c2)), findsNothing);
    expect(find.textContaining(String.fromCharCode(0x00e2)), findsNothing);
  });

  testWidgets('Home pay-period metrics end with currency-aware uplift', (
    tester,
  ) async {
    await tester.pumpWidget(
      BriskaApp(
        initialSettings: AppSettings(
          onboardingCompleted: true,
          currency: CurrencyCatalog.byCode('EUR'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final uplift = find.byKey(const ValueKey('home-uplift-metric'));
    final expectedUplift = CurrencyFormatter.format(
      0,
      CurrencyCatalog.byCode('EUR'),
    );
    expect(uplift, findsOneWidget);
    expect(
      find.descendant(of: uplift, matching: find.text(expectedUplift)),
      findsOneWidget,
    );
    expect(find.text('Deductions'), findsNothing);
    expect(find.text('Net pay'), findsNothing);
    expect(find.textContaining('£'), findsNothing);
  });

  testWidgets('Add work day form opens', (tester) async {
    await tester.pumpWidget(const BriskaApp());
    final addButton = find.byTooltip('Add Day');
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.text('Add Day'), findsWidgets);
    expect(find.text('Record your day'), findsOneWidget);
    expect(find.text('Site/job name'), findsOneWidget);
    expect(find.text('Hourly rate for this day'), findsOneWidget);
    expect(find.text('Job uplift'), findsOneWidget);
    expect(find.text('Daily allowance'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Overtime'), findsOneWidget);
    expect(
      find.text('Optional. Leave blank for no allowance.'),
      findsOneWidget,
    );
    final allowanceField = find.widgetWithText(TextFormField, 'e.g. 25.00');
    expect(tester.widget<TextFormField>(allowanceField).initialValue, isEmpty);
    expect(find.text('Save Entry'), findsOneWidget);
  });

  testWidgets('Daily allowance is independent and restored for editing', (
    tester,
  ) async {
    WorkEntry? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: AddWorkDayScreen(
          preferences: const AppSettings(),
          savedEntries: const [],
          onSave: (entry) async {
            saved = entry;
            return false;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Where did you work?',
      ),
      'Away Site',
    );
    final allowanceField = find.widgetWithText(TextFormField, 'e.g. 25.00');
    await tester.ensureVisible(allowanceField);
    expect(tester.widget<TextFormField>(allowanceField).initialValue, isEmpty);
    await tester.enterText(allowanceField, '37.50');
    await tester.tap(find.text('Overtime'));
    await tester.pumpAndSettle();
    final allowanceAfterRateChange = find.widgetWithText(
      TextFormField,
      'e.g. 25.00',
    );
    expect(
      tester.widget<TextFormField>(allowanceAfterRateChange).controller?.text,
      '37.50',
    );
    await tester.ensureVisible(find.text('Save Entry'));
    await tester.tap(find.text('Save Entry'));
    await tester.pumpAndSettle();

    expect(saved?.dailyAllowance, 37.5);

    await tester.pumpWidget(
      MaterialApp(
        home: AddWorkDayScreen(
          preferences: const AppSettings(),
          savedEntries: [saved!],
          initialEntry: saved,
          onSave: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editedAllowance = find.widgetWithText(TextFormField, 'e.g. 25.00');
    await tester.ensureVisible(editedAllowance);
    expect(tester.widget<TextFormField>(editedAllowance).initialValue, '37.50');
  });

  testWidgets('Add work day keeps save visible and validates site inline', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.tap(find.byTooltip('Add Day'));
    await tester.pumpAndSettle();

    expect(find.text('Estimated gross pay'), findsAtLeastNWidgets(2));
    expect(find.text("Today's earnings"), findsNothing);
    expect(find.text("Today's Earnings"), findsNothing);
    expect(find.text('Save Entry'), findsOneWidget);
    expect(tester.getBottomRight(find.text('Save Entry')).dy, lessThan(600));

    await tester.tap(find.text('Save Entry'));
    await tester.pump();

    expect(find.text('Enter a site/job name'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Calendar selection shows entry summary before editing', (
    tester,
  ) async {
    await tester.pumpWidget(BriskaApp(initialEntries: sampleEntries));
    await tester.tap(find.text('Entries'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final monthOffset = ((2026 - now.year) * 12) + (7 - now.month);
    final monthNavigation = monthOffset.isNegative
        ? find.byTooltip('Previous month')
        : find.byTooltip('Next month');
    for (var month = 0; month < monthOffset.abs(); month++) {
      await tester.tap(monthNavigation);
      await tester.pumpAndSettle();
    }

    expect(find.text('2 recorded days'), findsOneWidget);
    expect(find.text('Pay period'), findsOneWidget);
    expect(find.text(formatMonthYear(DateTime(2026, 7))), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp(r'^10 July, Standard')));
    await tester.pumpAndSettle();

    expect(find.text('Home Site'), findsWidgets);
    expect(find.text('10 Jul'), findsOneWidget);
    expect(find.text('Friday, 10 July'), findsOneWidget);
    expect(find.text('8h · Standard'), findsOneWidget);
    expect(find.text('Edit Day'), findsNothing);

    await tester.ensureVisible(find.text('Home Site').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home Site').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit Day'), findsOneWidget);
    expect(find.text('Update Entry'), findsOneWidget);
  });

  testWidgets('day deletion requires confirmation, supports cancel and undo', (
    tester,
  ) async {
    await tester.pumpWidget(BriskaApp(initialEntries: sampleEntries));
    await tester.tap(find.text('Entries'));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('entry-card-home'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: card, matching: find.text('Delete')));
    await tester.pumpAndSettle();

    expect(find.text('Delete day?'), findsOneWidget);
    expect(
      find.textContaining('You can undo this briefly using the Undo action'),
      findsOneWidget,
    );
    expect(find.textContaining('Friday, 10 July'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Home Site'),
      ),
      findsOneWidget,
    );
    expect(card, findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);

    await tester.tap(find.descendant(of: card, matching: find.text('Delete')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();

    expect(card, findsNothing);
    expect(find.text('Day deleted.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);
    final restored = sampleEntries.singleWhere((entry) => entry.id == 'home');
    final stored = await LocalStorage.loadEntries();
    final storedRestored = stored.singleWhere((entry) => entry.id == 'home');
    expect(storedRestored.toJson(), restored.toJson());
  });

  testWidgets('failed day deletion preserves the record and shows no success', (
    tester,
  ) async {
    await tester.pumpWidget(BriskaApp(initialEntries: sampleEntries));
    await tester.pumpAndSettle();
    LocalStorage.saveEntriesOverride = (_) async => throw StateError('failed');
    addTearDown(() => LocalStorage.saveEntriesOverride = null);

    await tester.tap(find.text('Entries'));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('entry-card-home'));
    await tester.ensureVisible(card);
    await tester.tap(find.descendant(of: card, matching: find.text('Delete')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();

    expect(card, findsOneWidget);
    expect(find.text('Could not delete this day.'), findsOneWidget);
    expect(find.text('Day deleted.'), findsNothing);
  });

  testWidgets('day deletion dialog handles narrow width and large text', (
    tester,
  ) async {
    final scenarios = [
      (size: const Size(320, 568), textScaleFactor: 1.0),
      (size: const Size(360, 640), textScaleFactor: 1.5),
      (size: const Size(360, 640), textScaleFactor: 2.0),
    ];
    for (final scenario in scenarios) {
      await expectNoLayoutOverflow(tester, () async {
        await pumpResponsiveApp(
          tester,
          size: scenario.size,
          textScaleFactor: scenario.textScaleFactor,
        );
        await tester.tap(find.text('Entries'));
        await tester.pumpAndSettle();
        final card = find.byKey(const ValueKey('entry-card-home'));
        final deleteAction = find.descendant(
          of: card,
          matching: find.text('Delete'),
        );
        await tester.ensureVisible(deleteAction);
        await tester.pumpAndSettle();
        await tester.tap(deleteAction);
        await tester.pumpAndSettle();
        expect(find.text('Delete day?'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      });
    }
  });

  testWidgets('Add and Edit Day use consistent terminology and feedback', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.tap(find.byTooltip('Add Day'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Add Day'), findsOneWidget);
    expect(find.text('Day Type'), findsOneWidget);
    expect(find.text('Work Day'), findsOneWidget);
    expect(find.text('Holiday'), findsOneWidget);
    expect(find.text('Unpaid Day Off'), findsOneWidget);
    expect(find.text('Unpaid'), findsNothing);
    expect(find.text('Save Entry'), findsOneWidget);
    expect(find.text('Estimated gross pay'), findsAtLeastNWidgets(2));
    expect(find.text(formatFullDate(DateTime.now())), findsOneWidget);

    final siteField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Where did you work?',
    );
    await tester.enterText(siteField, 'Exact Site');
    await tester.tap(find.text('Save Entry'));
    await tester.pumpAndSettle();
    expect(find.text('Day saved.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    await tester.tap(find.text('Entries'));
    await tester.pumpAndSettle();
    final card = find.byType(WorkEntryCard);
    await tester.ensureVisible(card);
    await tester.tap(find.descendant(of: card, matching: find.text('Edit')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Edit Day'), findsOneWidget);
    expect(find.text('Update Entry'), findsOneWidget);
    expect(find.text(formatFullDate(DateTime.now())), findsOneWidget);
    await tester.tap(find.text('Update Entry'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Day updated.'), findsWidgets);
  });

  testWidgets('Calendar date cells remain usable across responsive sizes', (
    tester,
  ) async {
    final scenarios = [
      (size: const Size(320, 568), textScaleFactor: 1.0),
      (size: const Size(360, 640), textScaleFactor: 1.0),
      (size: const Size(400, 800), textScaleFactor: 1.0),
      (size: const Size(568, 320), textScaleFactor: 1.0),
      (size: const Size(360, 640), textScaleFactor: 1.5),
      (size: const Size(360, 640), textScaleFactor: 2.0),
    ];

    for (final scenario in scenarios) {
      await expectNoLayoutOverflow(tester, () async {
        await pumpResponsiveApp(
          tester,
          size: scenario.size,
          textScaleFactor: scenario.textScaleFactor,
        );
        await tester.tap(find.text('Entries'));
        await tester.pumpAndSettle();

        final grid = find.byKey(const ValueKey('calendar-date-grid'));
        final weekdayRow = find.byKey(const ValueKey('calendar-weekday-row'));
        expect(grid, findsOneWidget);
        expect(weekdayRow, findsOneWidget);
        expect(tester.getSize(grid).width, tester.getSize(weekdayRow).width);

        final now = DateTime.now();
        final lastDay = DateTime(now.year, now.month + 1, 0).day;
        for (final day in [1, lastDay]) {
          final cell = find.byKey(ValueKey('calendar-day-$day'));
          expect(cell, findsOneWidget);
          final size = tester.getSize(cell);
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }

        final horizontal = find.byKey(
          const ValueKey('calendar-horizontal-scroll'),
        );
        final scrollable = find.descendant(
          of: horizontal,
          matching: find.byType(Scrollable),
        );
        final position = tester
            .state<ScrollableState>(scrollable.first)
            .position;
        final availableWidth = tester.getSize(horizontal).width;
        if (availableWidth < tester.getSize(grid).width) {
          expect(position.maxScrollExtent, greaterThan(0));
          position.jumpTo(position.maxScrollExtent);
          await tester.pump();
          expect(position.pixels, position.maxScrollExtent);
          expect(
            tester.getBottomRight(grid).dx,
            lessThanOrEqualTo(tester.getTopRight(horizontal).dx + 0.01),
          );
          position.jumpTo(0);
          await tester.pump();
          expect(position.pixels, 0);
          expect(
            tester.getTopLeft(grid).dx,
            greaterThanOrEqualTo(tester.getTopLeft(horizontal).dx - 0.01),
          );
        }
      });
    }
  });

  testWidgets('Calendar narrow scrolling preserves date selection', (
    tester,
  ) async {
    await pumpResponsiveApp(tester, size: const Size(320, 568));
    await tester.tap(find.text('Entries'));
    await tester.pumpAndSettle();

    final horizontal = find.byKey(const ValueKey('calendar-horizontal-scroll'));
    final weekdayRow = find.byKey(const ValueKey('calendar-weekday-row'));
    await tester.ensureVisible(weekdayRow);
    await tester.pumpAndSettle();
    await tester.dragFrom(
      Offset(tester.getCenter(horizontal).dx, tester.getCenter(weekdayRow).dy),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    final lastDay = DateTime(
      DateTime.now().year,
      DateTime.now().month + 1,
      0,
    ).day;
    final lastDayCell = find.byKey(ValueKey('calendar-day-$lastDay'));
    await tester.ensureVisible(lastDayCell);
    await tester.pumpAndSettle();
    await tester.tap(lastDayCell);
    await tester.pumpAndSettle();
    expect(find.text('Nothing recorded yet'), findsOneWidget);
    expect(find.text('Add Day'), findsWidgets);
  });

  testWidgets('Entries empty states use visible calendar guidance', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.tap(find.text('Entries'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing recorded yet'), findsOneWidget);
    expect(find.text('Add Day'), findsOneWidget);
    expect(
      find.text('Select a date above to record your first day.'),
      findsOneWidget,
    );
    expect(find.text('Tap Add Day to record your first shift.'), findsNothing);
  });

  testWidgets('Calendar statuses use distinct ordered shapes and semantics', (
    tester,
  ) async {
    final now = DateTime.now();
    WorkEntry entry({
      required String id,
      required int day,
      String entryType = 'WorkDay',
      String location = 'Home',
    }) => WorkEntry(
      id: id,
      entryType: entryType,
      date: DateTime(now.year, now.month, day),
      siteName: '$id site',
      startTime: '08:00',
      finishTime: '16:00',
      breakMinutes: 0,
      workLocation: location,
      hourlyRateUsed: 20,
      dailyAllowance: 0,
      jobUplift: 0,
      totalHours: 8,
      wages: 160,
      totalPay: 160,
      notes: '',
    );

    final entries = [
      entry(id: 'home', day: 10),
      entry(id: 'away', day: 11, location: 'Away'),
      entry(id: 'holiday', day: 12, entryType: 'Holiday'),
      entry(id: 'unpaid', day: 13, entryType: 'UnpaidDayOff'),
      entry(id: 'mixed-home', day: 14),
      entry(id: 'mixed-away', day: 14, location: 'Away'),
      entry(id: 'mixed-holiday', day: 14, entryType: 'Holiday'),
      entry(id: 'mixed-unpaid', day: 14, entryType: 'UnpaidDayOff'),
    ];

    await tester.pumpWidget(BriskaApp(initialEntries: entries));
    await tester.tap(find.text('Entries'));
    await tester.pumpAndSettle();

    final legend = find.byKey(const ValueKey('calendar-legend'));
    expect(legend, findsOneWidget);
    for (final label in [
      'Standard',
      'Overtime',
      'Holiday',
      'Unpaid',
      'No entry',
      'Pay period',
    ]) {
      expect(
        find.descendant(of: legend, matching: find.text(label)),
        findsOneWidget,
      );
    }

    final home = find.byKey(const ValueKey('calendar-cell-marker-home-10'));
    final away = find.byKey(const ValueKey('calendar-cell-marker-away-11'));
    final holiday = find.byKey(
      const ValueKey('calendar-cell-marker-holiday-12'),
    );
    final unpaid = find.byKey(const ValueKey('calendar-cell-marker-unpaid-13'));
    expect(home, findsOneWidget);
    expect(away, findsOneWidget);
    expect(holiday, findsOneWidget);
    expect(unpaid, findsOneWidget);
    expect(
      find.descendant(of: away, matching: find.byType(Transform)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: home, matching: find.byType(Transform)),
      findsNothing,
    );
    final homeBar = find
        .descendant(of: home, matching: find.byType(Container))
        .first;
    expect(tester.getSize(homeBar), const Size(12, 4));
    final unpaidSquare = find
        .descendant(of: unpaid, matching: find.byType(Container))
        .first;
    expect(tester.getSize(unpaidSquare), const Size(8, 8));
    final holidayCircle = find
        .descendant(of: holiday, matching: find.byType(Container))
        .first;
    expect(tester.getSize(holidayCircle), const Size(8, 8));
    expect(
      tester.widget<Container>(holidayCircle).decoration,
      isA<BoxDecoration>().having(
        (decoration) => decoration.shape,
        'shape',
        BoxShape.circle,
      ),
    );
    expect(tester.getSize(home), const Size(14, 12));
    expect(tester.getSize(away), const Size(14, 12));
    expect(tester.getSize(holiday), const Size(14, 12));
    expect(tester.getSize(unpaid), const Size(14, 12));

    for (final status in ['home', 'away', 'holiday', 'unpaid']) {
      expect(
        find.byKey(ValueKey('calendar-legend-marker-$status')),
        findsOneWidget,
      );
    }
    expect(find.bySemanticsLabel(RegExp(r'^10 .*Standard')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^11 .*Overtime')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^12 .*Holiday')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^13 .*Unpaid day off')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('^${now.day} .*today, selected')),
      findsOneWidget,
    );

    final mixedMarkers = [
      find.byKey(const ValueKey('calendar-cell-marker-home-14')),
      find.byKey(const ValueKey('calendar-cell-marker-away-14')),
      find.byKey(const ValueKey('calendar-cell-marker-holiday-14')),
    ];
    for (final marker in mixedMarkers) {
      expect(marker, findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('calendar-cell-marker-unpaid-14')),
      findsNothing,
    );
    expect(
      tester.getCenter(mixedMarkers[0]).dx,
      lessThan(tester.getCenter(mixedMarkers[1]).dx),
    );
    expect(
      tester.getCenter(mixedMarkers[1]).dx,
      lessThan(tester.getCenter(mixedMarkers[2]).dx),
    );

    await tester.tap(find.byKey(const ValueKey('calendar-day-11')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('calendar-summary-marker-away')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^11 .*Overtime, selected')),
      findsOneWidget,
    );
  });

  testWidgets('Calendar status markers remain unclipped responsively', (
    tester,
  ) async {
    for (final textScaleFactor in [1.0, 1.5, 2.0]) {
      await pumpResponsiveApp(tester, size: const Size(390, 844));
      await tester.tap(find.text('Entries'));
      await tester.pumpAndSettle();

      await expectNoLayoutOverflow(tester, () async {
        tester.view.physicalSize = const Size(320, 568);
        tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
        await tester.pumpAndSettle();

        for (final marker
            in find
                .byKey(const ValueKey('calendar-cell-marker-home-10'))
                .evaluate()) {
          final markerFinder = find.byElementPredicate(
            (element) => element == marker,
          );
          final cell = find.byKey(const ValueKey('calendar-day-10'));
          expect(
            tester.getRect(cell).contains(tester.getCenter(markerFinder)),
            isTrue,
          );
        }
      });
    }
  });

  testWidgets('Reports period selector updates the professional summary', (
    tester,
  ) async {
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1);
    final previousMonthEntries = sampleEntries.take(2).map((entry) {
      return WorkEntry.fromJson({
        ...entry.toJson(),
        'date': DateTime(
          previousMonth.year,
          previousMonth.month,
          entry.date.day,
        ).toIso8601String(),
      });
    }).toList();
    await tester.pumpWidget(BriskaApp(initialEntries: previousMonthEntries));
    await tester.tap(find.text('Reports').last);
    await tester.pumpAndSettle();

    expect(find.text('ESTIMATED GROSS PAY'), findsOneWidget);
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Last month'), findsOneWidget);
    expect(find.text('Pay period'), findsOneWidget);
    expect(
      find.text(
        formatFullDateRange(
          DateTime(now.year, now.month),
          DateTime(now.year, now.month + 1, 0),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Last month'));
    await tester.pumpAndSettle();
    expect(find.text('£365.00'), findsOneWidget);
    expect(find.text('16.5h'), findsOneWidget);
    expect(find.text('£182.50'), findsOneWidget);
    expect(find.text('Holidays'), findsOneWidget);
  });

  testWidgets('Reports shows guidance when the period has no activity', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.tap(find.text('Reports').last);
    await tester.pumpAndSettle();

    expect(find.text('No activity in this period'), findsOneWidget);
    expect(
      find.text('Try another reporting period, or record a work day.'),
      findsOneWidget,
    );
  });

  testWidgets('Theme controls update MaterialApp and selected setting', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Dark'));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    var segmented = tester.widget<SegmentedButton<ThemeMode>>(
      find.byType(SegmentedButton<ThemeMode>).last,
    );
    expect(segmented.selected, {ThemeMode.dark});

    await tester.ensureVisible(find.text('Light'));
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );

    expect(find.text('System'), findsNothing);
  });

  testWidgets('Settings shows and saves edited company name', (tester) async {
    AppSettings latest = const AppSettings(
      onboardingCompleted: true,
      fullName: 'Daniel Beckett',
      companyName: 'Old Company',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            preferences: latest,
            lockConfig: const AppLockConfig(),
            onCreateBackup: () async {},
            onRestoreBackup: () async {},
            onLockConfigChanged: (_) async {},
            onSetLockPin: (_) async {},
            onShowAbout: () {},
            onPreferencesChanged: (settings) => latest = settings,
            onThemeModeChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Employer / company'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Primary rate'), findsOneWidget);
    expect(find.text('Secondary rate'), findsOneWidget);
    expect(find.textContaining('allowance'), findsNothing);
    expect(find.text('Old Company'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), '  New Company  ');
    await tester.pump();
    expect(latest.companyName, 'Old Company');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(latest.companyName, 'New Company');
  });

  testWidgets('Settings confirms completed personal and pay-rate edits', (
    tester,
  ) async {
    AppSettings latest = const AppSettings(
      onboardingCompleted: true,
      fullName: 'Daniel Beckett',
      companyName: 'Old Company',
      homeHourlyRate: 20,
      awayHourlyRate: 25,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            preferences: latest,
            lockConfig: const AppLockConfig(),
            onCreateBackup: () async {},
            onRestoreBackup: () async {},
            onLockConfigChanged: (_) async {},
            onSetLockPin: (_) async {},
            onShowAbout: () {},
            onPreferencesChanged: (settings) => latest = settings,
            onThemeModeChanged: (_) {},
          ),
        ),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), '  New Company  ');
    await tester.pump();
    expect(find.text('Personal details updated.'), findsNothing);
    expect(latest.companyName, 'Old Company');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Personal details updated.'), findsOneWidget);
    expect(latest.companyName, 'New Company');

    final primaryRateField = find.byKey(const ValueKey('homeRate-0'));
    await tester.enterText(primaryRateField, '21.50');
    await tester.pump();
    expect(find.text('Pay rates updated.'), findsNothing);
    expect(latest.primaryRateValue, 20);

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(find.text('Pay rates updated.'), findsOneWidget);
    expect(latest.primaryRateValue, 21.5);
  });

  testWidgets('Settings confirms currency and pay schedule changes', (
    tester,
  ) async {
    AppSettings latest = const AppSettings(
      onboardingCompleted: true,
      payFrequency: lastFridayPayFrequency,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            preferences: latest,
            lockConfig: const AppLockConfig(),
            onCreateBackup: () async {},
            onRestoreBackup: () async {},
            onLockConfigChanged: (_) async {},
            onSetLockPin: (_) async {},
            onShowAbout: () {},
            onPreferencesChanged: (settings) => latest = settings,
            onThemeModeChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('British Pound').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Euro').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change currency'));
    await tester.pump();
    expect(latest.currency.code, 'EUR');
    expect(find.text('Currency updated.'), findsOneWidget);

    await tester.ensureVisible(find.text('Pay period type'));
    await tester.tap(find.text(lastFridayPayFrequency).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(calendarMonthlyPayFrequency).last);
    await tester.pumpAndSettle();
    expect(latest.payFrequency, calendarMonthlyPayFrequency);
    expect(find.text('Pay schedule updated.'), findsOneWidget);
  });

  testWidgets('Settings confirms app-lock and PIN actions', (tester) async {
    AppLockConfig? changedLock;
    String? savedPin;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            preferences: const AppSettings(onboardingCompleted: true),
            lockConfig: const AppLockConfig(enabled: true, hasPin: true),
            onCreateBackup: () async {},
            onRestoreBackup: () async {},
            onLockConfigChanged: (config) async => changedLock = config,
            onSetLockPin: (pin) async => savedPin = pin,
            onShowAbout: () {},
            onPreferencesChanged: (_) {},
            onThemeModeChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Set PIN fallback'));
    await tester.tap(find.text('Set PIN fallback'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'PIN'), '4321');
    await tester.tap(find.text('Save PIN'));
    await tester.pump();
    expect(savedPin, '4321');
    expect(find.text('PIN updated.'), findsOneWidget);

    final lockTile = find.widgetWithText(SwitchListTile, 'App lock');
    await tester.ensureVisible(lockTile);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: lockTile, matching: find.byType(Switch)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(changedLock?.enabled, isFalse);
    expect(find.text('App lock disabled.'), findsOneWidget);
  });

  testWidgets('Settings uses unhyphenated pay period terminology', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          preferences: const AppSettings(
            onboardingCompleted: true,
            payFrequency: weeklyPayFrequency,
          ),
          lockConfig: const AppLockConfig(),
          onCreateBackup: () async {},
          onRestoreBackup: () async {},
          onLockConfigChanged: (_) async {},
          onSetLockPin: (_) async {},
          onShowAbout: () {},
          onPreferencesChanged: (_) {},
          onThemeModeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Known pay period start date'));
    expect(find.text('Known pay period start date'), findsOneWidget);
    expect(find.textContaining('pay-period'), findsNothing);
  });

  testWidgets('production Settings hides tester and RC UI by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          preferences: const AppSettings(onboardingCompleted: true),
          lockConfig: const AppLockConfig(),
          onCreateBackup: () async {},
          onRestoreBackup: () async {},
          onLockConfigChanged: (_) async {},
          onSetLockPin: (_) async {},
          onShowAbout: () {},
          onPreferencesChanged: (_) {},
          onThemeModeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(showBetaTools, isFalse);
    expect(find.text('Beta feedback'), findsNothing);
    expect(find.text('View beta checklist'), findsNothing);
    expect(find.textContaining('RC'), findsNothing);
    expect(find.text('About Briska Pay'), findsOneWidget);
  });

  testWidgets('explicit beta configuration exposes tester UI', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          preferences: const AppSettings(onboardingCompleted: true),
          lockConfig: const AppLockConfig(),
          onCreateBackup: () async {},
          onRestoreBackup: () async {},
          onLockConfigChanged: (_) async {},
          onSetLockPin: (_) async {},
          onShowAbout: () {},
          onPreferencesChanged: (_) {},
          onThemeModeChanged: (_) {},
          showTesterTools: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View beta checklist'));

    expect(find.text('Beta feedback'), findsOneWidget);
    expect(find.text('View beta checklist'), findsOneWidget);
    expect(find.text('Tester release checklist.'), findsOneWidget);
    expect(find.textContaining('Current RC version'), findsNothing);
  });

  testWidgets('Settings shows selected weekday for next weekday payday rule', (
    tester,
  ) async {
    AppSettings latest = const AppSettings(
      onboardingCompleted: true,
      paydayRule: paydayNextSelectedWeekdayAfterPeriodEnd,
      paydaySelectedWeekday: DateTime.friday,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          preferences: latest,
          lockConfig: const AppLockConfig(),
          onCreateBackup: () async {},
          onRestoreBackup: () async {},
          onLockConfigChanged: (_) async {},
          onSetLockPin: (_) async {},
          onShowAbout: () {},
          onPreferencesChanged: (settings) => latest = settings,
          onThemeModeChanged: (_) {},
        ),
      ),
    );

    await tester.ensureVisible(find.text('Payday weekday'));
    expect(find.text('Payday weekday'), findsOneWidget);
    expect(find.text('Friday'), findsWidgets);

    await tester.tap(find.text('Friday').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tuesday').last);
    await tester.pumpAndSettle();

    expect(latest.paydaySelectedWeekday, DateTime.tuesday);
  });

  testWidgets('Onboarding does not collect a default away allowance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          initialSettings: const AppSettings(),
          onComplete: (_) {},
        ),
      ),
    );

    expect(find.textContaining('allowance'), findsNothing);
  });

  testWidgets('Legacy System theme migrates to explicit Light', (tester) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );

    await tester.pumpWidget(
      const BriskaApp(
        initialSettings: AppSettings(
          onboardingCompleted: true,
          themeMode: 'system',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scaffoldContext = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(scaffoldContext).brightness, Brightness.light);
  });

  testWidgets('Site field shows recent pinned suggestions and filters', (
    tester,
  ) async {
    final entries = [
      WorkEntry(
        id: 'station',
        date: DateTime(2026, 7, 6),
        siteName: 'Station Road Depot',
        startTime: '08:00',
        finishTime: '17:00',
        breakMinutes: 30,
        workLocation: 'Home',
        hourlyRateUsed: 20,
        dailyAllowance: 0,
        jobUplift: 0,
        totalHours: 8.5,
        wages: 170,
        totalPay: 170,
        notes: '',
      ),
      WorkEntry(
        id: 'mary',
        date: DateTime(2026, 7, 7),
        siteName: 'St Marys School',
        startTime: '08:00',
        finishTime: '17:00',
        breakMinutes: 30,
        workLocation: 'Home',
        hourlyRateUsed: 20,
        dailyAllowance: 0,
        jobUplift: 0,
        totalHours: 8.5,
        wages: 170,
        totalPay: 170,
        notes: '',
      ),
      WorkEntry(
        id: 'joseph',
        date: DateTime(2026, 7, 8),
        siteName: 'St Josephs',
        startTime: '08:00',
        finishTime: '17:00',
        breakMinutes: 30,
        workLocation: 'Home',
        hourlyRateUsed: 20,
        dailyAllowance: 0,
        jobUplift: 0,
        totalHours: 8.5,
        wages: 170,
        totalPay: 170,
        notes: '',
      ),
    ];

    await tester.pumpWidget(BriskaApp(initialEntries: entries));
    await tester.tap(find.byTooltip('Add Day'));
    await tester.pumpAndSettle();

    final siteField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Where did you work?',
    );
    await tester.ensureVisible(siteField);
    await tester.pumpAndSettle();
    await tester.tap(siteField);
    await tester.pumpAndSettle();

    expect(find.text('St Josephs'), findsOneWidget);
    expect(find.text('St Marys School'), findsOneWidget);
    expect(find.byIcon(Icons.location_on_outlined), findsWidgets);

    await tester.enterText(siteField, 'road');
    await tester.pumpAndSettle();
    expect(find.text('Station Road Depot'), findsOneWidget);
    expect(find.text('St Josephs'), findsNothing);

    await tester.enterText(siteField, 'New Site Name');
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(siteField);
    expect(field.controller!.text, 'New Site Name');
  });

  testWidgets('Export is disabled until work entries exist', (tester) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.tap(find.text('Export').last);
    await tester.pumpAndSettle();

    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Last month'), findsOneWidget);
    expect(find.text('Custom dates'), findsOneWidget);
    expect(find.text('Timesheet'), findsOneWidget);
    expect(find.text('Pay summary'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Excel (.xlsx)'), findsOneWidget);
    expect(find.text('CSV (.csv)'), findsNothing);
    expect(find.text('More options'), findsOneWidget);
    expect(find.text('Include notes'), findsNothing);
    expect(find.text('Export Library'), findsOneWidget);
    await tester.ensureVisible(find.text('More options'));
    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    expect(find.text('CSV (.csv)'), findsOneWidget);
    expect(find.text('Include notes'), findsOneWidget);
    expect(find.text('No days recorded to export'), findsOneWidget);
    expect(find.text('Record a day before creating a report.'), findsOneWidget);
    expect(find.text('Edit filename'), findsOneWidget);
    expect(find.text('Export report'), findsOneWidget);
    expect(find.text('Edit Filename'), findsNothing);
  });

  testWidgets('custom export controls use full textual dates', (tester) async {
    await tester.pumpWidget(BriskaApp(initialEntries: sampleEntries));
    await tester.tap(find.text('Export').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom dates'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('From date'));
    await tester.pumpAndSettle();
    final picker = find.byType(DatePickerDialog);
    await tester.tap(
      find.descendant(of: picker, matching: find.text('1')).last,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(
      find.text(
        'From date\n${formatFullDate(DateTime(now.year, now.month, 1))}',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('To date'));
    await tester.pumpAndSettle();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    await tester.tap(
      find
          .descendant(
            of: find.byType(DatePickerDialog),
            matching: find.text(lastDay.toString()),
          )
          .last,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'To date\n${formatFullDate(DateTime(now.year, now.month, lastDay))}',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        formatFullDateRange(
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month, lastDay),
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp(r'\d{1,2}/\d{1,2}/\d{4}')), findsNothing);
  });

  testWidgets('Export Library displays all supported file formats', (
    tester,
  ) async {
    final exportedAt = DateTime(2026, 7, 31);
    final records = [
      ExportedFileRecord(
        id: 'excel',
        fileName: 'Briska_Danny_Buck_July_2026.xlsx',
        fileType: 'Excel',
        filePath: '',
        exportedAt: exportedAt,
        periodLabel: 'July 2026',
        workDays: 4,
        totalHours: 32,
        totalPay: 640,
      ),
      ExportedFileRecord(
        id: 'timesheet',
        fileName: 'Briska_Danny_Buck_July_2026_Timesheet.pdf',
        fileType: 'PDF Timesheet',
        filePath: '',
        exportedAt: exportedAt,
        periodLabel: 'July 2026',
        workDays: 4,
        totalHours: 32,
        totalPay: 640,
      ),
      ExportedFileRecord(
        id: 'summary',
        fileName: 'Briska_Danny_Buck_July_2026_Summary.pdf',
        fileType: 'PDF Summary',
        filePath: '',
        exportedAt: exportedAt,
        periodLabel: 'July 2026',
        workDays: 4,
        totalHours: 32,
        totalPay: 640,
      ),
      ExportedFileRecord(
        id: 'csv',
        fileName: 'Briska_Danny_Buck_July_2026.csv',
        fileType: 'CSV',
        filePath: '',
        exportedAt: exportedAt,
        periodLabel: 'July 2026',
        workDays: 4,
        totalHours: 32,
        totalPay: 640,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: ExportScreen(
          entries: const [],
          fullName: 'Danny Buck',
          companyName: '',
          settings: const AppSettings(onboardingCompleted: true),
          records: records,
          onPreferencesChanged: (_) {},
          onAdd: (_) {},
          onDelete: (_) {},
          onUpdate: (_) {},
          libraryOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Briska_Danny_Buck_July_2026.xlsx'), findsOneWidget);
    expect(
      find.text('Briska_Danny_Buck_July_2026_Timesheet.pdf'),
      findsOneWidget,
    );
    expect(
      find.text('Briska_Danny_Buck_July_2026_Summary.pdf'),
      findsOneWidget,
    );
    expect(find.text('Briska_Danny_Buck_July_2026.csv'), findsOneWidget);
    expect(find.textContaining('31 Jul 2026'), findsAtLeastNWidgets(4));
    expect(find.textContaining('PDF Timesheet -'), findsOneWidget);
    expect(find.textContaining('PDF Summary -'), findsOneWidget);
    expect(find.textContaining('CSV -'), findsOneWidget);
    expect(find.text('Open'), findsWidgets);
    expect(find.text('Share'), findsWidgets);
    expect(find.text('Rename'), findsWidgets);
    expect(find.text('Delete'), findsWidgets);
    expect(find.text('Print'), findsNWidgets(2));
  });

  testWidgets('export success dialog is user-focused and responsive', (
    tester,
  ) async {
    final record = exportRecord(
      path: r'C:\Users\person\Documents\private-export.pdf',
      fileName:
          'Briska_An_Exceptionally_Long_Employee_Name_July_2026_Timesheet.pdf',
    );
    final scenarios = [
      (size: const Size(320, 568), textScaleFactor: 1.0),
      (size: const Size(360, 640), textScaleFactor: 1.5),
      (size: const Size(360, 640), textScaleFactor: 2.0),
    ];
    for (final scenario in scenarios) {
      await expectNoLayoutOverflow(tester, () async {
        tester.view
          ..physicalSize = scenario.size
          ..devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue =
            scenario.textScaleFactor;
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ExportCreatedDialog(
                      record: record,
                      onDone: () => Navigator.of(context).pop(),
                      onShare: () {},
                      onPrint: () {},
                      onOpen: () {},
                    ),
                  ),
                  child: const Text('Show'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Show'));
        await tester.pumpAndSettle();
        expect(find.text('Export created'), findsOneWidget);
        expect(find.text('1.5 KB'), findsOneWidget);
        expect(find.textContaining(record.filePath), findsNothing);
        expect(find.textContaining('1536 bytes'), findsNothing);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      });
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  test('export file failures use stable user-safe messages', () {
    const rawError = 'FileSystemException: SECRET_PATH platform failure';
    expect(
      exportFileActionFailureMessage(ExportFileAction.share),
      'Could not share this export.',
    );
    expect(
      exportFileActionFailureMessage(ExportFileAction.rename),
      'Could not rename this export.',
    );
    expect(
      exportFileActionFailureMessage(ExportFileAction.print),
      'Could not print this export.',
    );
    expect(
      exportFileActionFailureMessage(ExportFileAction.delete),
      'Could not delete this export.',
    );
    expect(
      ExportFileAction.values.map(exportFileActionFailureMessage).join(' '),
      isNot(contains(rawError)),
    );
  });

  test('export creation errors distinguish generation from saving', () {
    expect(
      exportCreationFailureMessage(Exception('generation failed')),
      'Could not generate the report.',
    );
    expect(
      exportCreationFailureMessage(
        const FileSystemException('save failed', '/private/export.pdf'),
      ),
      'The report was generated, but the file could not be saved.',
    );
    expect(
      exportCreationFailureMessage(
        const FileSystemException('save failed', '/private/export.pdf'),
      ),
      isNot(contains('storage space')),
    );
  });

  testWidgets(
    'export deletion distinguishes cancel, library and file removal',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('briska-delete-');
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final file = File('${directory.path}${Platform.pathSeparator}report.pdf');
      file.writeAsBytesSync([1, 2, 3]);
      final record = exportRecord(path: file.path);
      var removed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            entries: const [],
            fullName: '',
            companyName: '',
            settings: const AppSettings(onboardingCompleted: true),
            records: [record],
            onPreferencesChanged: (_) {},
            onAdd: (_) {},
            onDelete: (_) => removed = true,
            onUpdate: (_) {},
            libraryOnly: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete export?'), findsOneWidget);
      expect(find.text('Choose what you want to delete.'), findsOneWidget);
      expect(find.text('Remove from library'), findsOneWidget);
      expect(find.text('Delete file and remove from library'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(removed, isFalse);
      expect(file.existsSync(), isTrue);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from library'));
      await tester.pump();
      expect(removed, isTrue);
      expect(file.existsSync(), isTrue);
      expect(find.text('Export removed from library.'), findsOneWidget);
    },
  );

  testWidgets('successful export rename gives concise feedback', (
    tester,
  ) async {
    final record = exportRecord(path: 'missing-source.pdf');
    ExportedFileRecord? updated;
    await tester.pumpWidget(
      MaterialApp(
        home: ExportScreen(
          entries: const [],
          fullName: '',
          companyName: '',
          settings: const AppSettings(onboardingCompleted: true),
          records: [record],
          onPreferencesChanged: (_) {},
          onAdd: (_) {},
          onDelete: (_) {},
          onUpdate: (value) => updated = value,
          libraryOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'renamed-export');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Rename'),
      ),
    );
    await tester.pump();
    expect(updated?.fileName, 'renamed-export.pdf');
    expect(find.text('Export renamed.'), findsOneWidget);
  });

  testWidgets('physical export deletion requires confirmation and succeeds', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('briska-delete-');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final file = File('${directory.path}${Platform.pathSeparator}report.pdf');
    file.writeAsBytesSync([1, 2, 3]);
    final record = exportRecord(path: file.path);
    var removed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ExportScreen(
          entries: const [],
          fullName: '',
          companyName: '',
          settings: const AppSettings(onboardingCompleted: true),
          records: [record],
          onPreferencesChanged: (_) {},
          onAdd: (_) {},
          onDelete: (_) => removed = true,
          onUpdate: (_) {},
          libraryOnly: true,
          actionOverrides: ExportActionOverrides(
            deleteFile: (target) async => target.deleteSync(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete file and remove from library'));
    await tester.pumpAndSettle();
    expect(find.text('Delete file from device?'), findsOneWidget);
    expect(find.textContaining("This can't be undone."), findsOneWidget);
    await tester.tap(find.text('Delete file'));
    await tester.pumpAndSettle();
    expect(removed, isTrue);
    expect(file.existsSync(), isFalse);
    expect(find.text('Export deleted.'), findsOneWidget);
  });

  testWidgets('missing export files use one consistent phrase', (tester) async {
    final record = exportRecord(path: 'definitely-not-present.pdf');
    await tester.pumpWidget(
      MaterialApp(
        home: ExportScreen(
          entries: const [],
          fullName: '',
          companyName: '',
          settings: const AppSettings(onboardingCompleted: true),
          records: [record],
          onPreferencesChanged: (_) {},
          onAdd: (_) {},
          onDelete: (_) {},
          onUpdate: (_) {},
          libraryOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Export file not found.'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(find.text('Export file not found.'), findsWidgets);
    expect(find.text('File missing'), findsNothing);
    expect(find.text('This exported file could not be found.'), findsNothing);
  });

  testWidgets('Export shows only five recent exports and opens full library', (
    tester,
  ) async {
    final records = List.generate(
      6,
      (index) => ExportedFileRecord(
        id: '$index',
        fileName: 'report_$index.pdf',
        fileType: 'PDF Timesheet',
        filePath: '',
        exportedAt: DateTime(2026, 7, 18 - index),
        periodLabel: 'July 2026',
        workDays: 1,
        totalHours: 8,
        totalPay: 160,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ExportScreen(
          entries: sampleEntries,
          fullName: 'Danny Buck',
          companyName: '',
          settings: const AppSettings(onboardingCompleted: true),
          records: records,
          onPreferencesChanged: (_) {},
          onAdd: (_) {},
          onDelete: (_) {},
          onUpdate: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent exports'), findsOneWidget);
    expect(find.text('report_0.pdf'), findsOneWidget);
    expect(find.text('report_4.pdf'), findsOneWidget);
    expect(find.text('report_5.pdf'), findsNothing);

    await tester.ensureVisible(find.text('View all exports'));
    await tester.tap(find.text('View all exports'));
    await tester.pumpAndSettle();
    expect(find.text('Export Library'), findsOneWidget);
    expect(find.text('report_5.pdf'), findsOneWidget);
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
  });

  testWidgets('Day Type selector adapts fields for every entry type', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.tap(find.byTooltip('Add Day'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Holiday'));
    await tester.pumpAndSettle();
    expect(find.text('Site/job name'), findsNothing);
    expect(find.text('Start time'), findsNothing);
    expect(find.text('Job uplift'), findsOneWidget);
    expect(find.text('Holiday hours'), findsOneWidget);
    expect(find.text('Rate used'), findsNothing);

    await tester.tap(find.text('Sick Day'));
    await tester.pumpAndSettle();
    expect(find.text('Sick Pay'), findsOneWidget);
    expect(find.text('Paid at Primary Rate'), findsOneWidget);
    expect(find.text('Site/job name'), findsNothing);
    expect(find.text('Start time'), findsNothing);
    expect(find.text('Rate used'), findsNothing);

    await tester.tap(find.text('Unpaid Day Off'));
    await tester.pumpAndSettle();
    expect(find.text('Site/job name'), findsNothing);
    expect(find.text('Start time'), findsNothing);
    expect(find.text('Job uplift'), findsOneWidget);
    expect(find.text('Rate used'), findsNothing);

    await tester.tap(find.text('Work Day'));
    await tester.pumpAndSettle();
    expect(find.text('Site/job name'), findsOneWidget);
    expect(find.text('Start time'), findsOneWidget);
    expect(find.text('Rate used'), findsOneWidget);
    expect(find.text('Daily allowance'), findsOneWidget);
  });

  testWidgets('time fields display normalized HH:mm values', (tester) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.tap(find.byTooltip('Add Day'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(2), '730');
    await tester.enterText(fields.at(3), '17.00');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('07:30'), findsOneWidget);
    expect(find.text('17:00'), findsOneWidget);
  });

  testWidgets('Job uplift starts empty and formats after editing', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.tap(find.byTooltip('Add Day'));
    await tester.pumpAndSettle();

    final upliftField = find.descendant(
      of: find.byKey(const ValueKey('job-uplift-field')),
      matching: find.byType(TextField),
    );
    final initialField = tester.widget<TextField>(upliftField);
    expect(initialField.controller!.text, isEmpty);

    await tester.enterText(upliftField, '250.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final formattedField = tester.widget<TextField>(upliftField);
    expect(formattedField.controller!.text, '250.50');
  });

  testWidgets('Entries search, filters and sorting work', (tester) async {
    await tester.pumpWidget(BriskaApp(initialEntries: sampleEntries));
    await tester.tap(find.text('Entries'));
    await tester.pumpAndSettle();

    expect(find.text('Home Site'), findsOneWidget);
    expect(find.text('Away Site'), findsOneWidget);
    expect(find.byType(WorkEntryCard), findsNWidgets(3));

    await tester.enterText(find.byType(TextField).first, 'holiday');
    await tester.pumpAndSettle();
    expect(find.byType(WorkEntryCard), findsOneWidget);
    expect(find.text('Home Site'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('entries-filter-secondary')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entries-filter-secondary')));
    await tester.pumpAndSettle();
    expect(find.text('Away Site'), findsOneWidget);
    expect(find.text('Home Site'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('entries-filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entries-filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Newest first'));
    await tester.pumpAndSettle();
    final holidayTop = tester
        .getTopLeft(find.byKey(const ValueKey('entry-card-holiday')))
        .dy;
    final homeTop = tester
        .getTopLeft(find.byKey(const ValueKey('entry-card-home')))
        .dy;
    expect(holidayTop, lessThan(homeTop));
  });

  testWidgets('Add work day uses configured default break minutes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const BriskaApp(
        initialSettings: AppSettings(
          onboardingCompleted: true,
          defaultBreakMinutes: 45,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add Day'));
    await tester.pumpAndSettle();

    expect(find.text('45'), findsOneWidget);
  });
}
