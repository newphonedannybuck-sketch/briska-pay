import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:briska/main.dart';
import 'package:briska/src/ads/ads_configuration.dart';
import 'package:briska/src/ads/ads_consent_coordinator.dart';
import 'package:briska/src/ads/ads_service.dart';
import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/backup_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/local_storage.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/premium_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

WorkEntry entry(String id, int day, {double rate = 20}) => WorkEntry(
  id: id,
  date: DateTime(2026, 7, day),
  siteName: id,
  startTime: '08:00',
  finishTime: '16:00',
  breakMinutes: 0,
  hourlyRateUsed: rate,
  dailyAllowance: 0,
  jobUplift: 0,
  totalHours: 8,
  wages: rate * 8,
  totalPay: rate * 8,
  notes: '',
);

class ControlledWrites {
  final snapshots = <List<WorkEntry>>[];
  final completions = <Completer<void>>[];

  Future<void> save(List<WorkEntry> entries) async {
    snapshots.add(List.of(entries));
    final completion = Completer<void>();
    completions.add(completion);
    await completion.future;
    await SharedPreferencesAsync().setString(
      'work_entries_v1',
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }
}

void main() {
  setUpAll(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  setUp(() async {
    await SharedPreferencesAsync().clear();
    LocalStorage.saveEntriesOverride = null;
    LocalStorage.readStringOverride = null;
    LocalStorage.restoreWriteHook = null;
  });
  tearDown(() {
    LocalStorage.saveEntriesOverride = null;
    LocalStorage.readStringOverride = null;
    LocalStorage.restoreWriteHook = null;
  });

  Future<Future<bool> Function(WorkEntry)> saveCallback(
    WidgetTester tester,
  ) async {
    tester.widget<HomeScreen>(find.byType(HomeScreen)).onAddEntry();
    await tester.pumpAndSettle();
    final save = tester
        .widget<AddWorkDayScreen>(find.byType(AddWorkDayScreen))
        .onSave;
    Navigator.of(tester.element(find.byType(AddWorkDayScreen))).pop();
    await tester.pumpAndSettle();
    return save;
  }

  List<WorkEntry> visibleEntries(WidgetTester tester) =>
      tester.widget<HomeScreen>(find.byType(HomeScreen)).entries;

  Future<void> confirmDelete(WidgetTester tester, WorkEntry value) async {
    await tester.tap(find.text('Entries').last);
    await tester.pumpAndSettle();
    tester.widget<EntriesScreen>(find.byType(EntriesScreen)).onDelete(value);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Allow real backup file I/O to finish, stopping on an observed condition.
  // Entry-write overlap itself is controlled exclusively by Completers.
  Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 1000 && !ready(); attempt++) {
        await Future<void>(() {});
        await tester.pump();
      }
    });
    expect(ready(), isTrue);
    await tester.pumpAndSettle();
  }

  testWidgets('restore waits for pending save and replaces its committed data', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'briska_queue_restore_',
    );
    final backup = File('${directory.path}/input.json');
    backup.writeAsStringSync(
      jsonEncode(
        BriskaBackupData(
          createdAt: DateTime(2026, 7, 1),
          settings: const AppSettings(onboardingCompleted: true),
          workEntries: [entry('restored', 5)],
          exportRecords: [],
        ).toJson(),
      ),
    );
    const picker = MethodChannel('plugins.flutter.io/file_selector');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var pickerCalls = 0;
    messenger.setMockMethodCallHandler(picker, (_) async {
      pickerCalls++;
      return [backup.path];
    });
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    addTearDown(() {
      messenger.setMockMethodCallHandler(picker, null);
      messenger.setMockMethodCallHandler(paths, null);
      directory.deleteSync(recursive: true);
    });

    await tester.pumpWidget(BriskaApp(initialEntries: [entry('original', 1)]));
    await tester.pumpAndSettle();
    final save = await saveCallback(tester);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final restore = tester
        .widget<SettingsScreen>(find.byType(SettingsScreen))
        .onRestoreBackup;
    final writes = ControlledWrites();
    LocalStorage.saveEntriesOverride = writes.save;
    final pendingSave = save(entry('pending', 2));
    await tester.pump();
    var restored = false;
    final restoring = restore().then((_) => restored = true);
    final staleSave = save(entry('queued-during-restore', 6));
    await tester.pump();
    expect(pickerCalls, 0);
    expect(restored, isFalse);
    // The first write already captured the override; restoration uses real storage.
    LocalStorage.saveEntriesOverride = null;
    writes.completions.single.complete();
    expect(await pendingSave, isTrue);
    await pumpUntil(
      tester,
      () => find.text('Restore Briska Pay backup?').evaluate().isNotEmpty,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Restore'),
      ),
    );
    await pumpUntil(tester, () => restored);
    await restoring;
    expect(await staleSave, isFalse);
    expect(visibleEntries(tester).map((e) => e.id), ['restored']);
    expect((await LocalStorage.loadEntries()).map((e) => e.id), ['restored']);
    final safetyFile =
        Directory('${directory.path}/backups').listSync().single as File;
    final safetyEntries =
        (jsonDecode(safetyFile.readAsStringSync()) as Map)['workEntries']
            as List;
    expect(safetyEntries.map((e) => e['id']), ['pending', 'original']);
  });

  testWidgets('reset waits for pending save and cannot be repopulated by it', (
    tester,
  ) async {
    await LocalStorage.saveSettings(
      const AppSettings(onboardingCompleted: true),
    );
    await LocalStorage.saveEntries([entry('original', 1)]);
    LocalStorage.readStringOverride = (_) async =>
        throw StateError('read failure');
    await tester.pumpWidget(
      BriskaApp(
        useLocalStorage: true,
        appLockConfigLoader: () async => const AppLockConfig(),
        adsConsentCoordinator: const InactiveAdsConsentCoordinator(),
        adsService: DisabledAdsService(AdsConfiguration.current()),
      ),
    );
    await tester.pumpAndSettle();
    final recovery = tester.widget<StartupRecoveryScreen>(
      find.byType(StartupRecoveryScreen),
    );
    final reset = recovery.onResetLocalData;
    LocalStorage.readStringOverride = null;
    await recovery.onRetry();
    await tester.pumpAndSettle();
    final save = await saveCallback(tester);
    await confirmDelete(tester, entry('original', 1));
    final oldUndo = tester
        .widget<SnackBar>(find.byType(SnackBar))
        .action!
        .onPressed;
    final writes = ControlledWrites();
    LocalStorage.saveEntriesOverride = writes.save;
    final pendingSave = save(entry('pending', 2));
    await tester.pump();
    final resetting = reset();
    final staleSave = save(entry('queued-during-reset', 6));
    await tester.pump();
    expect(find.text('Reset local Briska Pay data?'), findsNothing);
    writes.completions.single.complete();
    expect(await pendingSave, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Reset local Briska Pay data?'), findsOneWidget);
    await tester.tap(find.text('Reset data'));
    await tester.pumpAndSettle();
    await resetting;
    expect(await staleSave, isFalse);
    oldUndo();
    await tester.pumpAndSettle();
    expect(await SharedPreferencesAsync().getString('work_entries_v1'), isNull);
    expect(await LocalStorage.loadEntries(), isEmpty);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(writes.snapshots, hasLength(1));
  });

  testWidgets('overlapping saves commit sequentially, preserve both and sort', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.pumpAndSettle();
    final save = await saveCallback(tester);
    final writes = ControlledWrites();
    LocalStorage.saveEntriesOverride = writes.save;
    final first = save(entry('old', 1));
    final second = save(entry('new', 3));
    await tester.pump();
    expect(writes.snapshots, hasLength(1));
    expect(visibleEntries(tester), isEmpty);
    writes.completions[0].complete();
    expect(await first, isTrue);
    await tester.pump();
    expect(visibleEntries(tester).map((e) => e.id), ['old']);
    expect(writes.snapshots[1].map((e) => e.id), ['new', 'old']);
    writes.completions[1].complete();
    expect(await second, isTrue);
    await tester.pump();
    expect(visibleEntries(tester).map((e) => e.id), ['new', 'old']);
    expect((await LocalStorage.loadEntries()).map((e) => e.id), ['new', 'old']);
  });

  testWidgets('overlapping edit and save replace IDs without losing changes', (
    tester,
  ) async {
    await tester.pumpWidget(BriskaApp(initialEntries: [entry('edited', 1)]));
    await tester.pumpAndSettle();
    final save = await saveCallback(tester);
    final writes = ControlledWrites();
    LocalStorage.saveEntriesOverride = writes.save;
    final edit = save(entry('edited', 2, rate: 30));
    final add = save(entry('added', 3));
    await tester.pump();
    writes.completions[0].complete();
    expect(await edit, isTrue);
    await tester.pump();
    expect(writes.snapshots[1].map((e) => e.id), ['added', 'edited']);
    expect(writes.snapshots[1].last.wages, 240);
    writes.completions[1].complete();
    expect(await add, isTrue);
    await tester.pump();
    expect(visibleEntries(tester), hasLength(2));
    expect(visibleEntries(tester).last.wages, 240);
  });

  testWidgets('failed save leaves UI unchanged and next save still commits', (
    tester,
  ) async {
    await tester.pumpWidget(BriskaApp(initialEntries: [entry('existing', 1)]));
    await tester.pumpAndSettle();
    final save = await saveCallback(tester);
    final writes = ControlledWrites();
    LocalStorage.saveEntriesOverride = writes.save;
    final failed = save(entry('failed', 2));
    final succeeding = save(entry('success', 3));
    await tester.pump();
    writes.completions[0].completeError(StateError('write failed'));
    expect(await failed, isFalse);
    await tester.pump();
    expect(visibleEntries(tester).map((e) => e.id), ['existing']);
    expect(find.text('Could not save this day.'), findsOneWidget);
    expect(writes.snapshots[1].map((e) => e.id), ['success', 'existing']);
    writes.completions[1].complete();
    expect(await succeeding, isTrue);
    await tester.pump();
    expect(visibleEntries(tester).map((e) => e.id), ['success', 'existing']);
  });

  testWidgets('delete and Undo use latest committed entries during saves', (
    tester,
  ) async {
    final removed = entry('removed', 1);
    await tester.pumpWidget(BriskaApp(initialEntries: [removed]));
    await tester.pumpAndSettle();
    final save = await saveCallback(tester);
    final writes = ControlledWrites();
    LocalStorage.saveEntriesOverride = writes.save;
    final adding = save(entry('added', 3));
    await tester.pump();
    await confirmDelete(tester, removed);
    expect(writes.snapshots, hasLength(1));
    writes.completions[0].complete();
    expect(await adding, isTrue);
    await tester.pump();
    expect(writes.snapshots[1].map((e) => e.id), ['added']);
    writes.completions[1].complete();
    await tester.pumpAndSettle();
    expect(find.text('Day deleted.'), findsOneWidget);
    final another = save(entry('another', 2));
    await tester.pump();
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(writes.snapshots, hasLength(3));
    writes.completions[2].complete();
    expect(await another, isTrue);
    await tester.pump();
    expect(writes.snapshots[3].map((e) => e.id), [
      'added',
      'another',
      'removed',
    ]);
    writes.completions[3].complete();
    await tester.pumpAndSettle();
    expect((await LocalStorage.loadEntries()).map((e) => e.id), [
      'added',
      'another',
      'removed',
    ]);
    expect(
      tester.widget<EntriesScreen>(find.byType(EntriesScreen)).entries,
      hasLength(3),
    );
  });
  testWidgets('invalid recalculation cannot overwrite historical earnings', (
    tester,
  ) async {
    final historical = WorkEntry(
      id: 'historical-holiday',
      entryType: 'Holiday',
      date: DateTime(2026, 7, 10),
      siteName: '',
      startTime: '',
      finishTime: '',
      breakMinutes: 0,
      hourlyRateUsed: 20,
      dailyAllowance: 0,
      jobUplift: 0,
      totalHours: 25,
      wages: 500,
      totalPay: 500,
      notes: '',
    );

    await tester.pumpWidget(BriskaApp(initialEntries: [historical]));
    await tester.pumpAndSettle();

    final save = await saveCallback(tester);
    var writes = 0;
    LocalStorage.saveEntriesOverride = (_) async {
      writes++;
    };

    final result = await save(historical);
    await tester.pump();

    expect(result, isFalse);
    expect(writes, 0);
    expect(visibleEntries(tester).single.toJson(), historical.toJson());
  });
}
