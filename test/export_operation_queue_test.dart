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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

ExportedFileRecord entry(String id, int day, {double rate = 20}) =>
    ExportedFileRecord(
      id: id,
      fileName: '$id.pdf',
      fileType: 'PDF',
      filePath: 'missing/$id.pdf',
      exportedAt: DateTime(2026, 7, day),
      periodLabel: 'July',
      workDays: 1,
      totalHours: 8,
      totalPay: rate * 8,
    );

class ControlledWrites {
  final snapshots = <List<ExportedFileRecord>>[];
  final completions = <Completer<void>>[];

  Future<void> save(List<ExportedFileRecord> entries) async {
    snapshots.add(List.of(entries));
    final completion = Completer<void>();
    completions.add(completion);
    await completion.future;
    await SharedPreferencesAsync().setString(
      'export_records_v1',
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
    LocalStorage.saveExportRecordsOverride = null;
    LocalStorage.readStringOverride = null;
    LocalStorage.restoreWriteHook = null;
  });
  tearDown(() {
    LocalStorage.saveExportRecordsOverride = null;
    LocalStorage.readStringOverride = null;
    LocalStorage.restoreWriteHook = null;
  });

  Future<Future<bool> Function(ExportedFileRecord)> saveCallback(
    WidgetTester tester,
  ) async {
    await tester.tap(find.text('Export').last);
    await tester.pumpAndSettle();
    return tester.widget<ExportScreen>(find.byType(ExportScreen)).onAdd;
  }

  List<ExportedFileRecord> visibleEntries(WidgetTester tester) =>
      tester.widget<ExportScreen>(find.byType(ExportScreen)).records;

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
      'briska_export_queue_restore_',
    );
    final backup = File('${directory.path}/input.json');
    backup.writeAsStringSync(
      jsonEncode(
        BriskaBackupData(
          createdAt: DateTime(2026, 7, 1),
          settings: const AppSettings(onboardingCompleted: true),
          workEntries: [],
          exportRecords: [entry('restored', 5)],
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

    await tester.pumpWidget(BriskaApp(initialExports: [entry('original', 1)]));
    await tester.pumpAndSettle();
    final save = await saveCallback(tester);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final restore = tester
        .widget<SettingsScreen>(find.byType(SettingsScreen))
        .onRestoreBackup;
    final writes = ControlledWrites();
    LocalStorage.saveExportRecordsOverride = writes.save;
    final pendingSave = save(entry('pending', 2));
    await tester.pump();
    var restored = false;
    final restoring = restore().then((_) => restored = true);
    final staleSave = save(entry('queued-during-restore', 6));
    await tester.pump();
    expect(pickerCalls, 0);
    expect(restored, isFalse);
    // The first write already captured the override; restoration uses real storage.
    LocalStorage.saveExportRecordsOverride = null;
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
    expect(await save(entry('late-stale', 7)), isFalse);
    await tester.tap(find.text('Export').last);
    await tester.pumpAndSettle();
    expect(visibleEntries(tester).map((e) => e.id), ['restored']);
    expect((await LocalStorage.loadExportRecords()).map((e) => e.id), [
      'restored',
    ]);
    final safetyFile =
        Directory('${directory.path}/backups').listSync().single as File;
    final safetyEntries =
        (jsonDecode(safetyFile.readAsStringSync()) as Map)['exportRecords']
            as List;
    expect(safetyEntries.map((e) => e['id']), ['pending', 'original']);
  });

  testWidgets('failed restore rolls back and allows queued export writes', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'briska_export_queue_restore_',
    );
    final backup = File('${directory.path}/input.json');
    backup.writeAsStringSync(
      jsonEncode(
        BriskaBackupData(
          createdAt: DateTime(2026, 7, 1),
          settings: const AppSettings(onboardingCompleted: true),
          workEntries: [],
          exportRecords: [entry('restored', 5)],
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

    await tester.pumpWidget(BriskaApp(initialExports: [entry('original', 1)]));
    await tester.pumpAndSettle();
    final save = await saveCallback(tester);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final restore = tester
        .widget<SettingsScreen>(find.byType(SettingsScreen))
        .onRestoreBackup;
    final writes = ControlledWrites();
    LocalStorage.saveExportRecordsOverride = writes.save;
    final pendingSave = save(entry('pending', 2));
    await tester.pump();
    var restored = false;
    LocalStorage.restoreWriteHook = (stage, rollback) async {
      if (!rollback && stage == RestoreWriteStage.exportLibrary) {
        throw StateError('restore failure');
      }
    };
    final restoring = restore().then((_) => restored = true);
    final staleSave = save(entry('queued-during-restore', 6));
    await tester.pump();
    expect(pickerCalls, 0);
    expect(restored, isFalse);
    // The first write already captured the override; restoration uses real storage.
    LocalStorage.saveExportRecordsOverride = null;
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
    expect(await staleSave, isTrue);

    await tester.tap(find.text('Export').last);
    await tester.pumpAndSettle();
    expect(visibleEntries(tester).map((e) => e.id), [
      'queued-during-restore',
      'pending',
      'original',
    ]);
    expect((await LocalStorage.loadExportRecords()).map((e) => e.id), [
      'queued-during-restore',
      'pending',
      'original',
    ]);
    final safetyFile =
        Directory('${directory.path}/backups').listSync().single as File;
    final safetyEntries =
        (jsonDecode(safetyFile.readAsStringSync()) as Map)['exportRecords']
            as List;
    expect(safetyEntries.map((e) => e['id']), ['pending', 'original']);
  });

  testWidgets('reset waits for pending save and cannot be repopulated by it', (
    tester,
  ) async {
    await LocalStorage.saveSettings(
      const AppSettings(onboardingCompleted: true),
    );
    await LocalStorage.saveExportRecords([entry('original', 1)]);
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
    final writes = ControlledWrites();
    LocalStorage.saveExportRecordsOverride = writes.save;
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
    expect(await save(entry('late-stale', 7)), isFalse);
    await tester.pumpAndSettle();
    expect(
      await SharedPreferencesAsync().getString('export_records_v1'),
      isNull,
    );
    expect(await LocalStorage.loadExportRecords(), isEmpty);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(writes.snapshots, hasLength(1));
  });

  testWidgets('rapid adds, updates and delete use latest committed snapshots', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.pumpAndSettle();
    final add = await saveCallback(tester);
    final screen = tester.widget<ExportScreen>(find.byType(ExportScreen));
    final writes = ControlledWrites();
    LocalStorage.saveExportRecordsOverride = writes.save;
    final a = entry('a', 1);
    final b = entry('b', 2);
    final operations = [
      add(a),
      add(b),
      screen.onUpdate(a.copyWith(isFavourite: true)),
      screen.onUpdate(a.copyWith(isFavourite: false, fileName: 'renamed.pdf')),
      screen.onDelete(b),
    ];
    await tester.pump();
    expect(writes.snapshots, hasLength(1));
    expect(visibleEntries(tester), isEmpty);
    for (var i = 0; i < operations.length; i++) {
      expect(writes.snapshots, hasLength(i + 1));
      writes.completions[i].complete();
      expect(await operations[i], isTrue);
      await tester.pump();
    }
    expect(writes.snapshots[1].map((e) => e.id), ['b', 'a']);
    expect(writes.snapshots[2].last.isFavourite, isTrue);
    expect(visibleEntries(tester).single.fileName, 'renamed.pdf');
    expect(visibleEntries(tester).single.isFavourite, isFalse);
    expect((await LocalStorage.loadExportRecords()).single.id, 'a');
  });
  testWidgets('failed export persistence preserves UI and queue recovers', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.pumpAndSettle();
    final add = await saveCallback(tester);
    final writes = ControlledWrites();
    LocalStorage.saveExportRecordsOverride = writes.save;
    final failed = add(entry('failed', 1));
    final next = add(entry('next', 2));
    await tester.pump();
    writes.completions.first.completeError(StateError('disk failed'));
    expect(await failed, isFalse);
    await tester.pump();
    expect(visibleEntries(tester), isEmpty);
    expect(writes.snapshots.last.map((e) => e.id), ['next']);
    writes.completions.last.complete();
    expect(await next, isTrue);
    await tester.pump();
    expect(visibleEntries(tester).single.id, 'next');
  });
  testWidgets('open library reflects committed favourite and removal updates', (
    tester,
  ) async {
    await tester.pumpWidget(BriskaApp(initialExports: [entry('live', 1)]));
    await tester.pumpAndSettle();
    await saveCallback(tester);
    await tester.ensureVisible(find.text('View all exports'));
    await tester.tap(find.text('View all exports'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favourite'));
    await tester.pumpAndSettle();
    expect(find.text('Favourited'), findsOneWidget);
    expect((await LocalStorage.loadExportRecords()).single.isFavourite, isTrue);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from library'));
    await tester.pumpAndSettle();
    expect(find.text('live.pdf'), findsNothing);
    expect(await LocalStorage.loadExportRecords(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('export and entry persistence share one operation queue', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add Day'));
    await tester.pumpAndSettle();
    final saveEntry = tester
        .widget<AddWorkDayScreen>(find.byType(AddWorkDayScreen))
        .onSave;
    Navigator.of(tester.element(find.byType(AddWorkDayScreen))).pop();
    await tester.pumpAndSettle();
    final addExport = await saveCallback(tester);
    final writes = ControlledWrites();
    LocalStorage.saveExportRecordsOverride = writes.save;
    var entryWrites = 0;
    LocalStorage.saveEntriesOverride = (_) async {
      entryWrites++;
    };
    addTearDown(() => LocalStorage.saveEntriesOverride = null);
    final export = addExport(entry('export', 1));
    final work = saveEntry(
      WorkEntry(
        id: 'work',
        date: DateTime(2026, 7, 1),
        siteName: 'Site',
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
      ),
    );
    await tester.pump();
    expect(entryWrites, 0);
    writes.completions.single.complete();
    expect(await export, isTrue);
    expect(await work, isTrue);
    expect(entryWrites, 1);
  });
}
