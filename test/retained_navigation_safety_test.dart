import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/backup_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/currency.dart';
import 'package:briska/src/display_format.dart';
import 'package:briska/src/export_formats.dart';
import 'package:briska/src/local_storage.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/pay_schedule.dart';
import 'package:briska/src/premium_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const preferences = AppSettings(
  onboardingCompleted: true,
  fullName: 'Original Employee',
  primaryRateValue: 20,
  payFrequency: calendarMonthlyPayFrequency,
);

WorkEntry entry(String id, DateTime date) => WorkEntry(
  id: id,
  date: date,
  siteName: 'Private $id',
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

Future<void> tab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Finder field(String hint) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == hint,
);
Finder search() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'Search site/job name',
);

Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
  // Same bounded, condition-based real-I/O helper as the operation-queue tests.
  await tester.runAsync(() async {
    for (var attempt = 0; attempt < 1000 && !ready(); attempt++) {
      await Future<void>(() {});
      await tester.pump();
    }
  });
  expect(ready(), isTrue);
  await tester.pumpAndSettle();
}

void main() {
  late List<WorkEntry> entries;
  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final today = DateTime.now();
    entries = [
      entry('current', today),
      entry('previous', DateTime(today.year, today.month - 1, 10)),
    ];
    LocalStorage.saveSettingsOverride = null;
    LocalStorage.saveExportRecordsOverride = null;
    LocalStorage.restoreWriteHook = null;
  });
  tearDown(() {
    LocalStorage.saveSettingsOverride = null;
    LocalStorage.saveExportRecordsOverride = null;
    LocalStorage.restoreWriteHook = null;
  });

  Future<void> shell(
    WidgetTester tester, {
    ExportActionOverrides? actions,
    DateTime Function()? clock,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BriskaShell(
          useLocalStorage: false,
          initialSettings: preferences,
          initialEntries: entries,
          exportActionOverrides: actions,
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
    if (clock != null) {
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'unvisited tabs stay lazy; inactive tabs exclude focus and semantics',
    (tester) async {
      await shell(tester);
      expect(find.byType(SettingsScreen, skipOffstage: false), findsNothing);
      await tab(tester, 'Entries');
      await tester.ensureVisible(search());
      await tester.enterText(search(), 'Private');
      await tab(tester, 'Reports');
      final hidden = find.byType(EntriesScreen, skipOffstage: false);
      expect(hidden, findsOneWidget);
      expect(find.byType(EntriesScreen), findsNothing);
      final context = tester.element(hidden);
      expect(TickerMode.valuesOf(context).enabled, isFalse);
      expect(Focus.of(context).descendantsAreFocusable, isFalse);
      expect(
        find.ancestor(
          of: hidden,
          matching: find.byWidgetPredicate(
            (w) => w is ExcludeSemantics && w.excluding,
            skipOffstage: false,
          ),
        ),
        findsOneWidget,
      );
      expect(tester.testTextInput.isVisible, isFalse);
    },
  );

  testWidgets(
    'hidden Settings defers newly required anchor prompt until activated',
    (tester) async {
      await shell(tester);
      await tab(tester, 'Settings');
      final settings = tester.widget<SettingsScreen>(
        find.byType(SettingsScreen),
      );
      await tab(tester, 'Entries');
      await settings.onPreferencesChanged(
        preferences.copyWith(
          payFrequency: weeklyPayFrequency,
          payScheduleAnchorPrompted: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose pay period start'), findsNothing);
      await tab(tester, 'Settings');
      expect(find.text('Choose pay period start'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        4,
      );
    },
  );

  testWidgets(
    'valid Settings draft survives tab switch and existing blur save',
    (tester) async {
      final pending = Completer<void>();
      final writes = <AppSettings>[];
      LocalStorage.saveSettingsOverride = (value) {
        writes.add(value);
        return pending.future;
      };
      await shell(tester);
      await tab(tester, 'Settings');
      await tester.enterText(
        field('Enter employer or company name'),
        'Unfinished Company',
      );
      await tab(tester, 'Entries');
      expect(writes.single.companyName, 'Unfinished Company');
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Personal details updated.'), findsNothing);
      await tab(tester, 'Settings');
      expect(find.text('Unfinished Company'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
    },
  );

  testWidgets(
    'incomplete Settings rate is retained without saving on tab departure',
    (tester) async {
      final writes = <AppSettings>[];
      LocalStorage.saveSettingsOverride = (value) async {
        writes.add(value);
      };
      await shell(tester);
      await tab(tester, 'Settings');
      await tester.ensureVisible(field('e.g. 20.00'));
      await tester.enterText(field('e.g. 20.00'), '-');
      await tab(tester, 'Entries');
      expect(writes, isEmpty);
      await tab(tester, 'Settings');
      expect(find.text('-'), findsOneWidget);
      await tester.ensureVisible(field('e.g. 20.00'));
      await tester.enterText(field('e.g. 20.00'), '20.50');
      await tab(tester, 'Entries');
      expect(writes.single.primaryRateValue, 20.5);
    },
  );

  for (final destination in ['Home', 'Entries']) {
    testWidgets('$destination retains scroll position across tab changes', (
      tester,
    ) async {
      await shell(tester);
      await tab(tester, destination);
      Finder scroll() => find.descendant(
        of: find.byType(destination == 'Home' ? HomeScreen : EntriesScreen),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              w.axisDirection == AxisDirection.down &&
              w.physics is! NeverScrollableScrollPhysics,
        ),
      );
      await tester.drag(scroll(), const Offset(0, -300));
      await tester.pumpAndSettle();
      final offset = tester.state<ScrollableState>(scroll()).position.pixels;
      expect(offset, greaterThan(0));
      await tab(tester, 'Reports');
      await tab(tester, destination);
      expect(tester.state<ScrollableState>(scroll()).position.pixels, offset);
    });
  }

  testWidgets(
    'Export retains custom dates, format, report and filename draft',
    (tester) async {
      await shell(tester);
      await tab(tester, 'Export');
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Custom dates'));
      for (final label in ['From date', 'To date']) {
        await tapVisible(tester, find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
      final dates = tester
          .widgetList<Text>(
            find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  (w.data?.startsWith('From date\n') == true ||
                      w.data?.startsWith('To date\n') == true),
            ),
          )
          .map((w) => w.data!)
          .toList();
      expect(dates, hasLength(2));
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Pay summary'));
      await tapVisible(
        tester,
        find.widgetWithText(ChoiceChip, 'Excel (.xlsx)'),
      );
      await tapVisible(tester, find.text('More options'));
      final filename = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Edit filename',
      );
      await tester.ensureVisible(filename);
      await tester.enterText(filename, 'My retained report');
      await tab(tester, 'Reports');
      await tab(tester, 'Export');
      for (final label in ['Custom dates', 'Pay summary', 'Excel (.xlsx)']) {
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
              .selected,
          isTrue,
        );
      }
      for (final date in dates) {
        expect(find.text(date), findsOneWidget);
      }
      expect(find.text('My retained report'), findsOneWidget);
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'inactive export ${fail ? 'failure' : 'completion'} waits for Export activation',
      (tester) async {
        final pending = Completer<ExportFileResult>();
        final records = <ExportedFileRecord>[];
        LocalStorage.saveExportRecordsOverride = (value) async {
          records
            ..clear()
            ..addAll(value);
        };
        var calls = 0;
        await shell(
          tester,
          actions: ExportActionOverrides(
            create: (items, settings, format) {
              calls++;
              expect(items.single.id, 'current');
              expect(settings.fullName, preferences.fullName);
              return pending.future;
            },
          ),
        );
        await tab(tester, 'Export');
        await tapVisible(tester, find.text('Export report'));
        await tab(tester, 'Reports');
        if (fail) {
          pending.completeError(StateError('controlled failure'));
        } else {
          pending.complete(
            const ExportFileResult(
              fileName: 'snapshot.pdf',
              filePath: 'test/snapshot.pdf',
              fileSize: 32,
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(records, hasLength(fail ? 0 : 1));
        expect(find.byType(ExportCreatedDialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        await tab(tester, 'Export');
        expect(
          find.byType(fail ? SnackBar : ExportCreatedDialog),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'export metadata uses starting selections while hidden settings change',
    (tester) async {
      final pending = Completer<ExportFileResult>();
      final records = <ExportedFileRecord>[];
      LocalStorage.saveExportRecordsOverride = (value) async {
        records
          ..clear()
          ..addAll(value);
      };
      await shell(
        tester,
        actions: ExportActionOverrides(
          create: (_, settings, format) {
            expect(settings.payFrequency, calendarMonthlyPayFrequency);
            expect(settings.currency.code, 'GBP');
            expect(format, ExportFormat.pdfTimesheet);
            return pending.future;
          },
        ),
      );
      await tab(tester, 'Export');
      await tapVisible(tester, find.text('Export report'));
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Last month'));
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Pay summary'));
      await tab(tester, 'Settings');
      final settings = tester.widget<SettingsScreen>(
        find.byType(SettingsScreen),
      );
      await settings.onPreferencesChanged(
        preferences.copyWith(
          fullName: 'Changed Employee',
          currency: CurrencyCatalog.byCode('USD'),
          payFrequency: weeklyPayFrequency,
          payPeriodAnchorDate: DateTime.now().toIso8601String(),
        ),
      );
      await tester.pumpAndSettle();
      pending.complete(
        const ExportFileResult(
          fileName: 'snapshot.pdf',
          filePath: 'test/snapshot.pdf',
          fileSize: 32,
        ),
      );
      await tester.pumpAndSettle();
      expect(records.single.dateRangeType, 'currentMonth');
      expect(records.single.reportType, 'Timesheet');
      expect(records.single.currencyCode, 'GBP');
      expect(records.single.currencySymbol, '£');
      expect(records.single.startDate!.day, 1);
      expect(records.single.startDate!.month, DateTime.now().month);
      expect(find.byType(ExportCreatedDialog), findsNothing);
    },
  );

  for (final beforeBuild in [false, true]) {
    testWidgets(
      'export finishing after App Lock registers without exposing UI: beforeBuild=$beforeBuild',
      (tester) async {
        var now = DateTime.utc(2026, 11, 5);
        final pending = Completer<ExportFileResult>();
        final records = <ExportedFileRecord>[];
        LocalStorage.saveExportRecordsOverride = (value) async {
          records
            ..clear()
            ..addAll(value);
        };
        await shell(
          tester,
          clock: () => now,
          actions: ExportActionOverrides(create: (_, _, _) => pending.future),
        );
        await tab(tester, 'Export');
        await tapVisible(tester, find.text('Export report'));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        now = now.add(const Duration(seconds: 60));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        if (!beforeBuild) {
          await tester.pumpAndSettle();
          expect(find.byType(ExportScreen, skipOffstage: false), findsNothing);
        }
        pending.complete(
          const ExportFileResult(
            fileName: 'private.pdf',
            filePath: 'test/private.pdf',
            fileSize: 32,
          ),
        );
        // Drain the completion before painting the lock branch to exercise the
        // live shell guard, not only the disposed-widget check.
        if (beforeBuild) await tester.idle();
        await tester.pumpAndSettle();
        expect(records, hasLength(1));
        expect(find.byType(AppLockScreen), findsOneWidget);
        expect(
          find.byType(ExportCreatedDialog, skipOffstage: false),
          findsNothing,
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(
          find.textContaining('private.pdf', skipOffstage: false),
          findsNothing,
        );
      },
    );
  }

  testWidgets(
    'deleting entries while Entries is hidden reconciles its month dropdown',
    (tester) async {
      await shell(tester);
      await tab(tester, 'Entries');
      final screen = tester.widget<EntriesScreen>(find.byType(EntriesScreen));
      final month = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == null,
      );
      await tapVisible(tester, month);
      await tester.pumpAndSettle();
      // Choose the month with the one historical fixture via its menu value.
      final date = entries.last.date;
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      await tester.tap(find.text(formatMonthYear(date)).last);
      await tester.pumpAndSettle();
      expect(tester.state<FormFieldState<String>>(month).value, key);
      await tab(tester, 'Reports');
      screen.onDelete(entries.last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();
      await tab(tester, 'Entries');
      expect(tester.state<FormFieldState<String>>(month).value, 'All');
      expect(
        tester
            .widget<EntriesScreen>(find.byType(EntriesScreen))
            .entries
            .map((e) => e.id),
        ['current'],
      );
    },
  );

  for (final outcome in ['success', 'cancel', 'failure']) {
    testWidgets(
      'backup $outcome reconciles retained state and in-flight export',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'briska_retained_',
        );
        final backup = File('${directory.path}/backup.json');
        backup.writeAsStringSync(
          jsonEncode(
            BriskaBackupData(
              createdAt: DateTime(2026),
              settings: preferences.copyWith(fullName: 'Restored Employee'),
              workEntries: [],
              exportRecords: [],
            ).toJson(),
          ),
        );
        const picker = MethodChannel('plugins.flutter.io/file_selector');
        const paths = MethodChannel('plugins.flutter.io/path_provider');
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(picker, (_) async => [backup.path]);
        messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
        addTearDown(() {
          messenger.setMockMethodCallHandler(picker, null);
          messenger.setMockMethodCallHandler(paths, null);
          directory.deleteSync(recursive: true);
        });
        final pending = Completer<ExportFileResult>();
        await shell(
          tester,
          actions: ExportActionOverrides(create: (_, _, _) => pending.future),
        );
        await tab(tester, 'Entries');
        await tester.ensureVisible(search());
        await tester.enterText(search(), 'Private');
        await tab(tester, 'Export');
        await tapVisible(tester, find.text('Export report'));
        await tab(tester, 'Settings');
        final settings = tester.widget<SettingsScreen>(
          find.byType(SettingsScreen),
        );
        if (outcome == 'failure') {
          LocalStorage.restoreWriteHook = (stage, rollback) async {
            if (!rollback && stage == RestoreWriteStage.workEntries) {
              throw StateError('controlled restore failure');
            }
          };
        }
        var done = false;
        final restoring = settings.onRestoreBackup().then((_) => done = true);
        await pumpUntil(
          tester,
          () => find.text('Restore Briska Pay backup?').evaluate().isNotEmpty,
        );
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(outcome == 'cancel' ? 'Cancel' : 'Restore'),
          ),
        );
        await pumpUntil(tester, () => done);
        await restoring;
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          outcome == 'success' ? 0 : 4,
        );
        pending.complete(
          const ExportFileResult(
            fileName: 'old.pdf',
            filePath: 'test/old.pdf',
            fileSize: 32,
          ),
        );
        await tester.pumpAndSettle();
        await tab(tester, 'Entries');
        final text = tester
            .widget<EditableText>(
              find.descendant(
                of: search(),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text;
        expect(text, outcome == 'success' ? '' : 'Private');
        await tab(tester, 'Export');
        expect(
          tester.widget<ExportScreen>(find.byType(ExportScreen)).records,
          hasLength(outcome == 'success' ? 0 : 1),
        );
        if (outcome == 'success') {
          expect(find.byType(ExportCreatedDialog), findsNothing);
        }
      },
    );
  }
}
