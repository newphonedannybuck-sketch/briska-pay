import 'package:briska/features/export/models/export_config.dart';
import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/display_format.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/pay_schedule.dart';
import 'package:briska/src/premium_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// These contracts failed at 0a05832 after a tab round trip or platform Back.
// Keep them alongside the security/Phase 8A controls as navigation regressions.
void main() {
  late DateTime previousMonth;
  late AppSettings settings;
  late List<WorkEntry> entries;

  WorkEntry entry(String id, int monthOffset, int day, String rate) =>
      WorkEntry(
        id: id,
        date: DateTime(
          previousMonth.year,
          previousMonth.month + monthOffset,
          day,
        ),
        siteName: 'Private site $id',
        rateType: rate,
        startTime: '08:00',
        finishTime: '16:00',
        breakMinutes: 0,
        hourlyRateUsed: 20,
        dailyAllowance: 0,
        jobUplift: 0,
        totalHours: 8,
        wages: 160,
        totalPay: 160,
        notes: '',
      );

  setUp(() {
    // Follow the existing Home tests: derive historical fixtures from the
    // production calendar's current month, rather than a date that ages out.
    final now = DateTime.now();
    previousMonth = DateTime(now.year, now.month - 1);
    settings = const AppSettings(
      onboardingCompleted: true,
      payFrequency: calendarMonthlyPayFrequency,
      payScheduleAnchorPrompted: true,
    );
    entries = [
      entry('older', 0, 10, 'secondary'),
      entry('newer', 0, 14, 'secondary'),
      entry('primary', 0, 12, 'primary'),
      entry('current', 1, 1, 'secondary'),
    ];
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    DateTime Function()? clock,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: BriskaShell(
          useLocalStorage: false,
          initialEntries: entries,
          initialSettings: settings,
          lockClock: clock,
          appLockConfigLoader: clock == null
              ? null
              : () async => const AppLockConfig(
                  enabled: true,
                  hasPin: true,
                  lockAfterSeconds: 60,
                ),
          pinVerifier: (_) async => true,
          deviceAuthenticationAvailabilityChecker: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder search() => find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Search site/job name',
  );
  Finder dropdown(bool month) => find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        (month
            ? widget.decoration.labelText == null
            : widget.decoration.labelText == 'Entry type'),
  );
  String? dropdownValue(WidgetTester tester, bool month) =>
      tester.state<FormFieldState<String>>(dropdown(month)).value;

  Future<void> choose(WidgetTester tester, Finder control, String label) async {
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.tap(control);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> configureEntries(WidgetTester tester) async {
    await tab(tester, 'Entries');
    await tester.ensureVisible(search());
    await tester.enterText(search(), 'Private site');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final rate = find.byKey(const Key('entries-filter-secondary'));
    await tester.ensureVisible(rate);
    await tester.tap(rate);
    await tester.pumpAndSettle();
    await choose(tester, dropdown(false), 'Work Days');
    await choose(tester, dropdown(true), formatMonthYear(previousMonth));
    await tester.ensureVisible(find.byTooltip('Newest first'));
    await tester.tap(find.byTooltip('Newest first'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(search()).controller?.text ??
          tester
              .widget<EditableText>(
                find.descendant(
                  of: search(),
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text,
      'Private site',
    );
    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected,
      {'secondary'},
    );
    expect(dropdownValue(tester, false), 'WorkDay');
    expect(
      dropdownValue(tester, true),
      '${previousMonth.year}-${previousMonth.month.toString().padLeft(2, '0')}',
    );
    expect(find.byTooltip('Oldest first'), findsOneWidget);
    expect(
      tester
          .widgetList<WorkEntryCard>(find.byType(WorkEntryCard))
          .map((w) => w.entry.id),
      ['older', 'newer'],
    );
  }

  group('Tab state and root Back contracts', () {
    for (final property in ['search', 'rate', 'entry type', 'month', 'sort']) {
      testWidgets('Entries preserves $property across tab round trip', (
        tester,
      ) async {
        await pumpShell(tester);
        await configureEntries(tester);
        await tab(tester, 'Reports');
        await tab(tester, 'Entries');
        switch (property) {
          case 'search':
            expect(
              tester
                  .widget<EditableText>(
                    find.descendant(
                      of: search(),
                      matching: find.byType(EditableText),
                    ),
                  )
                  .controller
                  .text,
              'Private site',
            );
          case 'rate':
            expect(
              tester
                  .widget<SegmentedButton<String>>(
                    find.byType(SegmentedButton<String>),
                  )
                  .selected,
              {'secondary'},
            );
          case 'entry type':
            expect(dropdownValue(tester, false), 'WorkDay');
          case 'month':
            expect(
              dropdownValue(tester, true),
              '${previousMonth.year}-${previousMonth.month.toString().padLeft(2, '0')}',
            );
          case 'sort':
            expect(find.byTooltip('Oldest first'), findsOneWidget);
            expect(
              tester
                  .widgetList<WorkEntryCard>(find.byType(WorkEntryCard))
                  .map((w) => w.entry.id),
              ['older', 'newer'],
            );
        }
      });
    }

    for (final selectedDay in [false, true]) {
      testWidgets(
        'Calendar preserves ${selectedDay ? 'selected day' : 'historical month'} across tabs',
        (tester) async {
          await pumpShell(tester);
          await tab(tester, 'Entries');
          await tester.tap(find.byTooltip('Previous month'));
          await tester.pumpAndSettle();
          final day = find.byKey(const ValueKey('calendar-day-10'));
          await tester.ensureVisible(day);
          await tester.tap(day);
          await tester.pumpAndSettle();
          final expected = selectedDay
              ? formatWeekdayDate(
                  DateTime(previousMonth.year, previousMonth.month, 10),
                )
              : formatMonthYear(previousMonth);
          Finder label() => find.descendant(
            of: find.byType(MonthlyCalendarSection),
            matching: find.text(expected),
          );
          expect(label(), findsOneWidget);
          await tab(tester, 'Reports');
          await tab(tester, 'Entries');
          expect(label(), findsOneWidget);
        },
      );
    }

    testWidgets('Home preserves historical pay period across Reports visit', (
      tester,
    ) async {
      await pumpShell(tester);
      final pager = find.byType(PageView);
      final initial = tester.widget<PageView>(pager).controller!.page!;
      await tester.ensureVisible(pager);
      await tester.drag(pager, const Offset(500, 0));
      await tester.pumpAndSettle();
      final selected = tester.widget<PageView>(pager).controller!.page!;
      expect(selected, initial - 1);
      final period = getCurrentPayPeriodForSettings(
        date: previousMonth,
        settings: settings,
      );
      final label =
          '${formatCompactDate(period.start)} – ${formatCompactDate(period.end)}';
      Finder periodLabel() =>
          find.descendant(of: pager, matching: find.text(label));
      expect(periodLabel(), findsOneWidget);
      await tab(tester, 'Reports');
      await tab(tester, 'Home');
      expect(tester.widget<PageView>(pager).controller!.page, selected);
      expect(periodLabel(), findsOneWidget);
    });

    testWidgets('Reports preserves non-default period across Entries visit', (
      tester,
    ) async {
      await pumpShell(tester);
      await tab(tester, 'Reports');
      await tester.tap(find.text('Last month'));
      await tester.pumpAndSettle();
      Set<ExportDateRangeType> selection() => tester
          .widget<SegmentedButton<ExportDateRangeType>>(
            find.byType(SegmentedButton<ExportDateRangeType>),
          )
          .selected;
      expect(selection(), {ExportDateRangeType.previousMonth});
      await tab(tester, 'Entries');
      await tab(tester, 'Reports');
      expect(selection(), {ExportDateRangeType.previousMonth});
    });

    for (final destination in ['Entries', 'Reports', 'Export', 'Settings']) {
      testWidgets('Android Back from $destination selects Home', (
        tester,
      ) async {
        await pumpShell(tester);
        await tab(tester, destination);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          isNot(0),
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          0,
        );
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    }
  });

  group('Existing navigation and security controls', () {
    testWidgets('Android Back from Home requests normal platform exit', (
      tester,
    ) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpShell(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        calls.where((method) => method == 'SystemNavigator.pop'),
        hasLength(1),
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
    });

    for (final editing in [false, true]) {
      for (final dirty in [false, true]) {
        testWidgets(
          'Android Back respects ${dirty ? 'modified' : 'clean'} ${editing ? 'Edit' : 'Add'} Day route',
          (tester) async {
            await pumpShell(tester);
            if (editing) {
              await tab(tester, 'Entries');
              final edit = find.descendant(
                of: find.byKey(const ValueKey('entry-card-older')),
                matching: find.text('Edit'),
              );
              await tester.ensureVisible(edit);
              await tester.pumpAndSettle();
              await tester.tap(edit);
            } else {
              await tester.tap(find.byTooltip('Add Day'));
            }
            await tester.pumpAndSettle();
            if (dirty) {
              final site = find.byWidgetPredicate(
                (w) =>
                    w is TextField &&
                    w.decoration?.hintText == 'Where did you work?',
              );
              await tester.enterText(site, 'Unfinished private site');
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
            }
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            if (dirty) {
              expect(find.text('Discard unsaved changes?'), findsOneWidget);
              await tester.binding.handlePopRoute();
              await tester.pumpAndSettle();
              expect(find.text('Discard unsaved changes?'), findsNothing);
              expect(find.byType(AddWorkDayScreen), findsOneWidget);
              expect(find.text('Unfinished private site'), findsOneWidget);
            } else {
              expect(find.byType(AddWorkDayScreen), findsNothing);
              expect(find.text('Discard unsaved changes?'), findsNothing);
              expect(
                find.byType(editing ? EntriesScreen : HomeScreen),
                findsOneWidget,
              );
            }
          },
        );
      }
    }

    testWidgets(
      'timeout after multiple tab visits hides all sensitive tab state',
      (tester) async {
        var now = DateTime.utc(2026, 11, 5, 12);
        await pumpShell(tester, clock: () => now);
        await tester.enterText(find.byType(TextField), '1234');
        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();
        await tab(tester, 'Reports');
        await tab(tester, 'Export');
        await tab(tester, 'Settings');
        await configureEntries(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        now = now.add(const Duration(seconds: 60));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppLockScreen), findsOneWidget);
        for (final type in [
          HomeScreen,
          EntriesScreen,
          ProfessionalReportsScreen,
          ExportScreen,
          SettingsScreen,
          NavigationBar,
        ]) {
          expect(find.byType(type, skipOffstage: false), findsNothing);
        }
        expect(
          find.textContaining('Private site', skipOffstage: false),
          findsNothing,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(AppLockScreen), findsOneWidget);
        expect(find.byType(EntriesScreen, skipOffstage: false), findsNothing);
      },
    );
  });
}
