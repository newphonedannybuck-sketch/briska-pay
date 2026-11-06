import 'dart:async';

import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/ads/ads_configuration.dart';
import 'package:briska/src/ads/ads_consent_coordinator.dart';
import 'package:briska/src/ads/ads_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/local_storage.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/pay_schedule.dart';
import 'package:briska/features/export/models/export_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'retained_navigation_safety_test.dart' as fixtures;

const settings = AppSettings(
  onboardingCompleted: true,
  primaryRateValue: 20,
  secondaryRateValue: 25,
  payFrequency: calendarMonthlyPayFrequency,
);

void main() {
  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await LocalStorage.saveSettings(settings);
  });
  tearDown(() {
    LocalStorage.saveSettingsOverride = null;
    LocalStorage.readStringOverride = null;
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BriskaShell(useLocalStorage: false, initialSettings: settings),
      ),
    );
    await tester.pumpAndSettle();
    await fixtures.tab(tester, 'Settings');
  }

  Future<void> input(WidgetTester tester, String hint, String text) async {
    final control = fixtures.field(hint);
    await tester.ensureVisible(control);
    await tester.enterText(control, text);
    await tester.pump();
  }

  Future<void> returnToSettings(WidgetTester tester) async {
    await fixtures.tab(tester, 'Entries');
    await fixtures.tab(tester, 'Settings');
  }

  String text(WidgetTester tester, String hint) =>
      tester.widget<TextField>(fixtures.field(hint)).controller!.text;

  for (final primary in [true, false]) {
    final label = primary ? 'Standard' : 'Overtime';
    final hint = primary ? 'e.g. 20.00' : 'e.g. 25.00';
    final original = primary ? 20.0 : 25.0;
    double rate(AppSettings value) =>
        primary ? value.primaryRateValue : value.secondaryRateValue;

    for (final invalid in ['-', '-5', 'NaN', 'Infinity']) {
      testWidgets(
        '$label rejects $invalid across tabs and saves corrected rate',
        (tester) async {
          final writes = <AppSettings>[];
          LocalStorage.saveSettingsOverride = (value) async {
            writes.add(value);
          };
          await open(tester);
          await input(tester, hint, invalid);
          await returnToSettings(tester);
          expect(writes, isEmpty);
          expect(text(tester, hint), invalid);
          expect(rate(await LocalStorage.loadSettings()), original);
          await input(tester, hint, '31.50');
          await returnToSettings(tester);
          expect(rate(writes.single), 31.5);
          expect(
            primary
                ? writes.single.secondaryRateValue
                : writes.single.primaryRateValue,
            primary ? 25 : 20,
          );
          expect(text(tester, hint), '31.50');
        },
      );
    }

    testWidgets(
      '$label corrected-rate save failure rolls back and permits unrelated save and retry',
      (tester) async {
        await open(tester);
        await input(tester, hint, '-');
        await returnToSettings(tester);
        final pending = Completer<void>();
        LocalStorage.saveSettingsOverride = (_) => pending.future;
        await input(tester, hint, '31.50');
        await fixtures.tab(tester, 'Entries');
        pending.completeError(StateError('controlled write failure'));
        await tester.pumpAndSettle();
        LocalStorage.saveSettingsOverride = null;
        await fixtures.tab(tester, 'Settings');
        expect(text(tester, hint), original.toStringAsFixed(2));
        expect(rate(await LocalStorage.loadSettings()), original);
        await input(tester, 'Enter employer or company name', 'After failure');
        await returnToSettings(tester);
        final saved = await LocalStorage.loadSettings();
        expect(saved.companyName, 'After failure');
        expect(saved.primaryRateValue, 20);
        expect(saved.secondaryRateValue, 25);
        await input(tester, hint, '32');
        await returnToSettings(tester);
        expect(rate(await LocalStorage.loadSettings()), 32);
      },
    );

    testWidgets(
      '$label invalid draft survives unrelated theme failure and can be corrected',
      (tester) async {
        await open(tester);
        await input(tester, hint, '-');
        await returnToSettings(tester);
        LocalStorage.saveSettingsOverride = (_) async =>
            throw StateError('controlled theme failure');
        await fixtures.tapVisible(tester, find.text('Dark'));
        await tester.pumpAndSettle();
        expect(text(tester, hint), '-');
        expect(rate(await LocalStorage.loadSettings()), original);
        LocalStorage.saveSettingsOverride = null;
        await input(tester, hint, '33');
        await returnToSettings(tester);
        expect(rate(await LocalStorage.loadSettings()), 33);
      },
    );

    testWidgets(
      '$label newer invalid draft survives pending write failure and unrelated edits cannot save it',
      (tester) async {
        await open(tester);
        final pending = Completer<void>();
        LocalStorage.saveSettingsOverride = (_) => pending.future;
        await input(tester, hint, '30');
        await fixtures.tab(tester, 'Entries');
        await fixtures.tab(tester, 'Settings');
        await input(tester, hint, '-');
        pending.completeError(StateError('controlled write failure'));
        await tester.pumpAndSettle();
        final writes = <AppSettings>[];
        LocalStorage.saveSettingsOverride = (value) async {
          writes.add(value);
        };
        await input(tester, 'Enter employer or company name', 'Other edit');
        await returnToSettings(tester);
        expect(writes, isEmpty);
        expect(text(tester, hint), '-');
        expect(rate(await LocalStorage.loadSettings()), original);
        LocalStorage.saveSettingsOverride = null;
        await input(tester, hint, '34');
        await returnToSettings(tester);
        final saved = await LocalStorage.loadSettings();
        expect(rate(saved), 34);
        expect(saved.companyName, 'Other edit');
      },
    );
  }

  testWidgets(
    'ordinary Add Edit Delete refresh data without resetting retained tabs',
    (tester) async {
      final now = DateTime.now();
      final original = fixtures.entry(
        'original',
        now.subtract(const Duration(days: 1)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BriskaShell(
            useLocalStorage: false,
            initialSettings: settings,
            initialEntries: [original],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await fixtures.tab(tester, 'Reports');
      await tester.tap(find.text('Last month'));
      await tester.pumpAndSettle();
      final reportsState = tester.state(find.byType(ProfessionalReportsScreen));
      await fixtures.tab(tester, 'Entries');
      await tester.ensureVisible(fixtures.search());
      await tester.enterText(fixtures.search(), 'Private');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final entriesState = tester.state(find.byType(EntriesScreen));
      await fixtures.tapVisible(tester, find.byTooltip('Newest first'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Oldest first'), findsOneWidget);

      Future<void> check(int count) async {
        await fixtures.tab(tester, 'Entries');
        expect(tester.state(find.byType(EntriesScreen)), same(entriesState));
        expect(
          tester.widget<EntriesScreen>(find.byType(EntriesScreen)).entries,
          hasLength(count),
        );
        expect(find.text('Private'), findsOneWidget);
        expect(find.byTooltip('Oldest first'), findsOneWidget);
        await fixtures.tab(tester, 'Reports');
        expect(
          tester.state(find.byType(ProfessionalReportsScreen)),
          same(reportsState),
        );
        expect(
          tester
              .widget<SegmentedButton<ExportDateRangeType>>(
                find.byType(SegmentedButton<ExportDateRangeType>),
              )
              .selected,
          {ExportDateRangeType.previousMonth},
        );
      }

      await fixtures.tab(tester, 'Home');
      await tester.tap(find.byTooltip('Add Day'));
      await tester.pumpAndSettle();
      await tester.enterText(
        fixtures.field('Where did you work?'),
        'Private added',
      );
      await fixtures.tapVisible(tester, find.text('Save Entry'));
      await tester.pumpAndSettle();
      expect(find.byType(AddWorkDayScreen), findsNothing);
      await check(2);

      await fixtures.tab(tester, 'Entries');
      tester.widget<EntriesScreen>(find.byType(EntriesScreen)).onEdit(original);
      await tester.pumpAndSettle();
      await tester.enterText(
        fixtures.field('Where did you work?'),
        'Private edited',
      );
      await fixtures.tapVisible(tester, find.text('Update Entry'));
      await tester.pumpAndSettle();
      expect(find.byType(AddWorkDayScreen), findsNothing);
      await check(2);
      expect(
        (await LocalStorage.loadEntries())
            .singleWhere((e) => e.id == original.id)
            .siteName,
        'Private edited',
      );

      await fixtures.tab(tester, 'Entries');
      final ui = tester.widget<EntriesScreen>(find.byType(EntriesScreen));
      ui.onDelete(ui.entries.singleWhere((e) => e.id == original.id));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();
      await check(1);
    },
  );

  for (final cancel in [false, true]) {
    testWidgets('reset clears retained UI only on success: cancel=$cancel', (
      tester,
    ) async {
      // Reuse the recovery callback pattern in settings_operation_queue_test.
      LocalStorage.readStringOverride = (_) async =>
          throw StateError('controlled load failure');
      await tester.pumpWidget(
        MaterialApp(
          home: BriskaShell(
            useLocalStorage: true,
            adsConsentCoordinator: const InactiveAdsConsentCoordinator(),
            adsService: DisabledAdsService(AdsConfiguration.current()),
            appLockConfigLoader: () async => const AppLockConfig(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final recovery = tester.widget<StartupRecoveryScreen>(
        find.byType(StartupRecoveryScreen),
      );
      LocalStorage.readStringOverride = null;
      await recovery.onRetry();
      await tester.pumpAndSettle();
      await fixtures.tab(tester, 'Entries');
      await tester.ensureVisible(fixtures.search());
      await tester.enterText(fixtures.search(), 'Retained query');
      await fixtures.tab(tester, 'Settings');
      final resetting = recovery.onResetLocalData();
      await tester.pumpAndSettle();
      await tester.tap(find.text(cancel ? 'Cancel' : 'Reset data'));
      await tester.pumpAndSettle();
      await resetting;
      if (cancel) {
        await fixtures.tab(tester, 'Entries');
        expect(find.text('Retained query'), findsOneWidget);
      } else {
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(find.byType(EntriesScreen, skipOffstage: false), findsNothing);
        expect(find.byType(SettingsScreen, skipOffstage: false), findsNothing);
        expect(find.text('Retained query', skipOffstage: false), findsNothing);
      }
    });
  }
}
