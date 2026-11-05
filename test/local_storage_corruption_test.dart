import 'dart:convert';

import 'package:briska/main.dart';
import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/local_storage.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/premium_home_screen.dart';
import 'package:briska/src/work_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUpAll(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  setUp(() async {
    await SharedPreferencesAsync().clear();
    LocalStorage.readStringOverride = null;
    LocalStorage.saveEntriesOverride = null;
  });

  tearDown(() {
    LocalStorage.readStringOverride = null;
    LocalStorage.saveEntriesOverride = null;
  });

  test('missing local datasets use normal defaults', () async {
    LocalStorage.readStringOverride = (_) async => null;

    expect((await LocalStorage.loadSettings()).onboardingCompleted, isFalse);
    expect(await LocalStorage.loadEntries(), isEmpty);
    expect(await LocalStorage.loadExportRecords(), isEmpty);
  });

  test('valid settings and entries load normally', () async {
    final settings = const AppSettings(
      onboardingCompleted: true,
      fullName: 'Saved User',
      companyName: 'Saved Employer',
    );
    final entry = WorkEntry(
      id: 'saved-entry',
      date: DateTime(2026, 7, 24),
      siteName: 'Saved Site',
      startTime: '08:00',
      finishTime: '16:00',
      breakMinutes: 30,
      workLocation: 'Home',
      hourlyRateUsed: 20,
      dailyAllowance: 0,
      jobUplift: 0,
      totalHours: 7.5,
      wages: 150,
      totalPay: 150,
      notes: '',
    );
    LocalStorage.readStringOverride = (key) async {
      if (key == 'app_settings_v1') return jsonEncode(settings.toJson());
      if (key == 'work_entries_v1') return jsonEncode([entry.toJson()]);
      return null;
    };

    expect((await LocalStorage.loadSettings()).companyName, 'Saved Employer');
    expect((await LocalStorage.loadEntries()).single.siteName, 'Saved Site');
  });

  Map<String, dynamic> historicalEntry(String id, String date) => {
    'id': id,
    'date': date,
    'entryType': 'WorkDay',
    'startTime': '08:00',
    'finishTime': '16:00',
    'breakMinutes': 30,
    'workLocation': 'Home',
    'hourlyRateUsed': 20,
    'totalHours': 6.25,
    'wages': 123.45,
    'totalPay': 140.75,
  };

  test(
    'loading preserves historical totals and sorts without saving',
    () async {
      final preferences = SharedPreferencesAsync();
      final records = [
        historicalEntry('oldest', '2024-01-01'),
        historicalEntry('newest', '2024-03-01'),
        historicalEntry('middle', '2024-02-01'),
      ];
      final storedJson = jsonEncode(records);
      await preferences.setString('work_entries_v1', storedJson);
      var saveCalls = 0;
      LocalStorage.saveEntriesOverride = (_) async {
        saveCalls++;
      };

      final fresh = WorkCalculator.recalculateEntry(
        WorkEntry.fromJson(records.first),
      );
      expect(fresh.totalHours, isNot(6.25));
      expect(fresh.wages, isNot(123.45));
      expect(fresh.totalPay, isNot(140.75));

      final entries = await LocalStorage.loadEntries();

      expect(entries.map((entry) => entry.id), ['newest', 'middle', 'oldest']);
      for (final entry in entries) {
        expect(entry.totalHours, 6.25);
        expect(entry.wages, 123.45);
        expect(entry.totalPay, 140.75);
      }
      expect(saveCalls, 0);
      expect(await preferences.getString('work_entries_v1'), storedJson);
    },
  );

  test('valid entries load even when saving would throw', () async {
    await SharedPreferencesAsync().setString(
      'work_entries_v1',
      jsonEncode([historicalEntry('saved', '2024-01-01')]),
    );
    LocalStorage.saveEntriesOverride = (_) async =>
        throw StateError('Storage writes unavailable');

    expect((await LocalStorage.loadEntries()).single.id, 'saved');
  });

  test('loading does not create or update the data-version marker', () async {
    final preferences = SharedPreferencesAsync();
    await preferences.setString(
      'work_entries_v1',
      jsonEncode([historicalEntry('saved', '2024-01-01')]),
    );

    await LocalStorage.loadEntries();
    expect(await preferences.getInt('briska_data_version'), isNull);

    await preferences.setInt('briska_data_version', 1);
    await LocalStorage.loadEntries();
    expect(await LocalStorage.loadDataVersion(), 1);
  });

  test('invalid entry records still report corruption', () async {
    for (final value in [
      '{}',
      '[null]',
      jsonEncode([historicalEntry('invalid-date', 'not-a-date')]),
      jsonEncode([
        {
          ...historicalEntry('invalid-hours', '2024-01-01'),
          'totalHours': 'bad',
        },
      ]),
    ]) {
      LocalStorage.readStringOverride = (_) async => value;
      await expectLater(
        LocalStorage.loadEntries(),
        throwsA(
          isA<LocalDataCorruptionException>().having(
            (error) => error.dataSet,
            'dataset',
            LocalDataSet.workEntries,
          ),
        ),
      );
    }
  });

  test('malformed datasets are distinguished from missing data', () async {
    for (final testCase in <({String key, LocalDataSet dataSet})>[
      (key: 'app_settings_v1', dataSet: LocalDataSet.settings),
      (key: 'work_entries_v1', dataSet: LocalDataSet.workEntries),
      (key: 'export_records_v1', dataSet: LocalDataSet.exportLibrary),
    ]) {
      LocalStorage.readStringOverride = (key) async =>
          key == testCase.key ? '{damaged json' : null;

      final load = switch (testCase.dataSet) {
        LocalDataSet.settings => LocalStorage.loadSettings(),
        LocalDataSet.workEntries => LocalStorage.loadEntries(),
        LocalDataSet.exportLibrary => LocalStorage.loadExportRecords(),
      };
      await expectLater(
        load,
        throwsA(
          isA<LocalDataCorruptionException>().having(
            (error) => error.dataSet,
            'dataset',
            testCase.dataSet,
          ),
        ),
      );
    }
  });

  test('corrupt entries are not automatically overwritten', () async {
    var saveCalled = false;
    LocalStorage.readStringOverride = (key) async =>
        key == 'work_entries_v1' ? '[damaged' : null;
    LocalStorage.saveEntriesOverride = (_) async => saveCalled = true;

    await expectLater(
      LocalStorage.loadEntries(),
      throwsA(isA<LocalDataCorruptionException>()),
    );
    expect(saveCalled, isFalse);
  });

  test('storage read failure has a distinct safe result', () async {
    LocalStorage.readStringOverride = (_) async =>
        throw StateError('platform path and payload');

    await expectLater(
      LocalStorage.loadSettings(),
      throwsA(
        isA<LocalDataReadException>().having(
          (error) => error.dataSet,
          'dataset',
          LocalDataSet.settings,
        ),
      ),
    );
  });

  testWidgets('corruption shows recovery and Retry performs a real reread', (
    tester,
  ) async {
    var settingsCorrupt = true;
    var settingsReads = 0;
    final validSettings = const AppSettings(
      onboardingCompleted: true,
      fullName: 'Recovered User',
    );
    LocalStorage.readStringOverride = (key) async {
      if (key != 'app_settings_v1') return null;
      settingsReads++;
      return settingsCorrupt ? '{damaged' : jsonEncode(validSettings.toJson());
    };

    await tester.pumpWidget(
      BriskaApp(
        useLocalStorage: true,
        appLockConfigLoader: () async => const AppLockConfig(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("Briska Pay couldn't load your saved data"),
      findsOneWidget,
    );
    expect(find.text('Welcome to Briska Pay'), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.textContaining('{damaged'), findsNothing);

    settingsCorrupt = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(settingsReads, 2);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Welcome to Briska Pay'), findsNothing);
  });

  testWidgets('app lock remains ahead of corrupt-data recovery', (
    tester,
  ) async {
    LocalStorage.readStringOverride = (key) async =>
        key == 'app_settings_v1' ? '{damaged' : null;

    await tester.pumpWidget(
      BriskaApp(
        useLocalStorage: true,
        appLockConfigLoader: () async =>
            const AppLockConfig(enabled: true, hasPin: true),
        pinVerifier: (_) async => true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppLockScreen), findsOneWidget);
    expect(find.text("Briska Pay couldn't load your saved data"), findsNothing);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(
      find.text("Briska Pay couldn't load your saved data"),
      findsOneWidget,
    );
  });

  testWidgets('recovery screen is responsive and overflow-free', (
    tester,
  ) async {
    LocalStorage.readStringOverride = (key) async =>
        key == 'app_settings_v1' ? '{damaged' : null;
    for (final testCase in <({Size size, double scale})>[
      (size: const Size(320, 568), scale: 1.5),
      (size: const Size(568, 320), scale: 2),
    ]) {
      tester.view.physicalSize = testCase.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = testCase.scale;
      await tester.pumpWidget(
        BriskaApp(
          key: UniqueKey(),
          useLocalStorage: true,
          appLockConfigLoader: () async => const AppLockConfig(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text("Briska Pay couldn't load your saved data"),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}
