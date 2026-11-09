import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/backup_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/local_storage.dart';
import 'package:briska/src/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'backup_lock_security_test.dart' show pumpUntil;
import 'retained_navigation_safety_test.dart' as fixtures;
import 'restore_journal_failure_test.dart' as storage;

void main() {
  final platform = storage.JournalFailurePlatform();
  const picker = MethodChannel('plugins.flutter.io/file_selector');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final original = fixtures.entry('original', DateTime(2026, 7, 14));
  final replacement = fixtures.entry('replacement', DateTime(2026, 7, 15));
  final originalSettings = fixtures.preferences.copyWith(
    fullName: 'Alex Original',
    companyName: 'Original Construction',
    primaryRateValue: 20,
    secondaryRateValue: 30,
    defaultBreakMinutes: 30,
  );
  final replacementSettings = fixtures.preferences.copyWith(
    fullName: 'Sam Restored',
    companyName: 'Restored Electrical',
    primaryRateValue: 28,
    secondaryRateValue: 42,
    defaultBreakMinutes: 45,
  );
  ExportedFileRecord record(String id, double pay) => ExportedFileRecord(
    id: id,
    fileName: '$id.pdf',
    fileType: 'PDF',
    filePath: '',
    exportedAt: DateTime(2026, 7, 16),
    periodLabel: 'July 2026 $id',
    workDays: 1,
    totalHours: 8,
    totalPay: pay,
  );
  final originalExport = record('original-export', 160);
  final replacementExport = record('replacement-export', 224);
  final staleExport = record('stale-export', 999);
  late Directory directory;
  late String originalRaw;
  Future<Map<String, Object?>> rawDatasets() async {
    final prefs = SharedPreferencesAsync();
    return {
      storage.settingsKey: await prefs.getString(storage.settingsKey),
      storage.entriesKey: await prefs.getString(storage.entriesKey),
      storage.exportsKey: await prefs.getString(storage.exportsKey),
      storage.versionKey: await prefs.getInt(storage.versionKey),
    };
  }

  setUp(() async {
    platform.store = storage.JournalFailureStore({});
    SharedPreferencesAsyncPlatform.instance = platform;
    LocalStorage.restoreWriteHook = null;
    LocalStorage.readStringOverride = null;
    await LocalStorage.saveSettings(originalSettings);
    // Preserve formatting and historical amounts through recovery.
    originalRaw = ' ${jsonEncode([original.toJson()])}\n';
    await SharedPreferencesAsync().setString(storage.entriesKey, originalRaw);
    await LocalStorage.saveExportRecords([originalExport]);
    directory = Directory.systemTemp.createTempSync('briska_recovery_shell_');
    final file = File('${directory.path}/input.json')
      ..writeAsStringSync(
        jsonEncode(
          BriskaBackupData(
            createdAt: DateTime(2026, 7, 15),
            settings: replacementSettings,
            workEntries: [replacement],
            exportRecords: [replacementExport],
          ).toJson(),
        ),
      );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(picker, (_) async => [file.path]);
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
  });
  tearDown(() {
    LocalStorage.restoreWriteHook = null;
    LocalStorage.readStringOverride = null;
    LocalStorage.saveSettingsOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(picker, null);
    messenger.setMockMethodCallHandler(paths, null);
    directory.deleteSync(recursive: true);
  });

  Future<void> seedJournal() async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(
      storage.journalKey,
      LocalStorage.encodeRestoreJournalForTesting(
        settings: await prefs.getString(storage.settingsKey),
        workEntries: await prefs.getString(storage.entriesKey),
        exportRecords: await prefs.getString(storage.exportsKey),
        dataVersion: await prefs.getInt(storage.versionKey),
      ),
    );
  }

  Future<StartupRecoveryScreen> requireRecovery(WidgetTester tester) async {
    await fixtures.tab(tester, 'Settings');
    final settings = tester.widget<SettingsScreen>(find.byType(SettingsScreen));
    var done = false;
    final operation = settings.onRestoreBackup().whenComplete(
      () => done = true,
    );
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
    await pumpUntil(tester, () => done);
    await operation;
    return tester.widget<StartupRecoveryScreen>(
      find.byType(StartupRecoveryScreen),
    );
  }

  Future<void> openShell(
    WidgetTester tester, {
    List<WorkEntry>? entries,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BriskaShell(
          useLocalStorage: false,
          initialSettings: originalSettings,
          initialEntries: entries ?? [original],
          initialExports: [originalExport],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'concurrent Retry shares recovery and blocks saves through loading',
    (tester) async {
      await openShell(tester);
      await fixtures.tab(tester, 'Entries');
      tester.widget<EntriesScreen>(find.byType(EntriesScreen)).onEdit(original);
      await tester.pumpAndSettle();
      final save = tester
          .widget<AddWorkDayScreen>(find.byType(AddWorkDayScreen))
          .onSave;
      await tester.pageBack();
      await tester.pumpAndSettle();
      await seedJournal();
      final recovery = await requireRecovery(tester);
      final entered = Completer<void>();
      final release = Completer<void>();
      final loading = Completer<void>();
      final finishLoading = Completer<void>();
      final stages = <RestoreWriteStage>[];
      LocalStorage.restoreWriteHook = (stage, rollback) async {
        expect(rollback, isTrue);
        stages.add(stage);
        if (stage == RestoreWriteStage.dataVersion) {
          entered.complete();
          await release.future;
        }
      };
      var reads = 0;
      LocalStorage.readStringOverride = (key) async {
        reads++;
        if (key == storage.settingsKey) {
          loading.complete();
          await finishLoading.future;
        }
        return SharedPreferencesAsync().getString(key);
      };
      final first = recovery.onRetry();
      await entered.future;
      final second = recovery.onRetry();
      final third = recovery.onRetry();
      expect(identical(first, second), isTrue);
      expect(identical(first, third), isTrue);
      var saveFinished = false;
      final saving = save(original).then((value) {
        saveFinished = true;
        return value;
      });
      final before = await rawDatasets();
      await tester.pump();
      expect(saveFinished, isFalse);
      expect(stages, [RestoreWriteStage.dataVersion]);
      expect(await rawDatasets(), before);
      release.complete();
      await loading.future;
      expect(
        await SharedPreferencesAsync().getString(storage.journalKey),
        isNull,
      );
      await tester.pump();
      expect(saveFinished, isFalse);
      expect(
        tester
            .widget<StartupRecoveryScreen>(find.byType(StartupRecoveryScreen))
            .restoreRecoveryRequired,
        isTrue,
      );
      finishLoading.complete();
      await Future.wait([first, second, third]);
      expect(await saving, isFalse);
      expect(stages, RestoreWriteStage.values.reversed.toList());
      expect(reads, 3);
      await tester.pumpAndSettle();
      expect(find.byType(StartupRecoveryScreen), findsNothing);
    },
  );

  for (final failRecovery in [false, true]) {
    testWidgets(
      'legacy migration follows completed recovery, failure=$failRecovery',
      (tester) async {
        final prefs = SharedPreferencesAsync();
        final legacy = jsonEncode({
          'fullName': 'Legacy Employee',
          'onboardingCompleted': true,
          'homeHourlyRate': 19.5,
          'awayHourlyRate': 29.25,
          'themeMode': 'light',
          'currency': originalSettings.toJson()['currency'],
        });
        await prefs.setString(storage.settingsKey, legacy);
        await seedJournal();
        final snapshot = await rawDatasets();
        final entered = Completer<void>();
        final release = Completer<void>();
        var migrations = 0;
        LocalStorage.restoreWriteHook = (stage, rollback) async {
          if (stage == RestoreWriteStage.dataVersion) {
            entered.complete();
            await release.future;
            if (failRecovery) throw StateError('Recovery failed');
          }
        };
        LocalStorage.saveSettingsOverride = (settings) async {
          migrations++;
          expect(await prefs.getString(storage.journalKey), isNull);
          expect(await prefs.getString(storage.settingsKey), legacy);
          await prefs.setString(
            storage.settingsKey,
            jsonEncode(settings.toJson()),
          );
        };
        await tester.pumpWidget(
          MaterialApp(
            home: BriskaShell(
              appLockConfigLoader: () async => const AppLockConfig(),
            ),
          ),
        );
        await entered.future;
        expect(migrations, 0);
        expect(await rawDatasets(), snapshot);
        release.complete();
        await tester.pumpAndSettle();
        if (failRecovery) {
          expect(migrations, 0);
          expect(await rawDatasets(), snapshot);
          expect(await prefs.getString(storage.journalKey), isNotNull);
          expect(find.byType(StartupRecoveryScreen), findsOneWidget);
        } else {
          expect(migrations, 1);
          await fixtures.tab(tester, 'Settings');
          final settings = tester
              .widget<SettingsScreen>(find.byType(SettingsScreen))
              .preferences;
          expect(settings.fullName, 'Legacy Employee');
          expect(settings.primaryRateValue, 19.5);
          expect(settings.secondaryRateValue, 29.25);
          final stored =
              jsonDecode((await prefs.getString(storage.settingsKey))!) as Map;
          expect(stored.containsKey('homeHourlyRate'), isFalse);
          expect(stored, settings.toJson());
        }
      },
    );
  }

  testWidgets('delete and undo callbacks stay invalid across recovery', (
    tester,
  ) async {
    final deleted = fixtures.entry('undo-only', DateTime(2026, 7, 13));
    await LocalStorage.saveEntries([original, deleted]);
    await openShell(tester, entries: [original, deleted]);
    await fixtures.tab(tester, 'Entries');
    final staleDelete = tester
        .widget<EntriesScreen>(find.byType(EntriesScreen))
        .onDelete;
    Future<VoidCallback> deleteAndCaptureUndo(
      ValueChanged<WorkEntry> delete,
      WorkEntry target,
    ) async {
      ScaffoldMessenger.of(
        tester.element(find.byType(EntriesScreen)),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      delete(target);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        (await LocalStorage.loadEntries()).map((e) => e.id),
        isNot(contains(target.id)),
      );
      return tester.widget<SnackBar>(find.byType(SnackBar)).action!.onPressed;
    }

    final staleUndo = await deleteAndCaptureUndo(staleDelete, deleted);
    // Recover a dataset containing the same id, to detect a stale delete.
    await SharedPreferencesAsync().setString(storage.entriesKey, originalRaw);
    await seedJournal();
    final recovery = await requireRecovery(tester);
    final before = await rawDatasets();
    staleDelete(original);
    staleUndo();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(await rawDatasets(), before);
    await recovery.onRetry();
    await tester.pumpAndSettle();
    staleUndo();
    staleDelete(original);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(await rawDatasets(), before);
    await fixtures.tab(tester, 'Entries');
    final freshDelete = tester
        .widget<EntriesScreen>(find.byType(EntriesScreen))
        .onDelete;
    final freshUndo = await deleteAndCaptureUndo(freshDelete, original);
    freshUndo();
    await tester.pumpAndSettle();
    expect(
      (await LocalStorage.loadEntries()).single.toJson(),
      original.toJson(),
    );
  });

  for (final malformed in [false, true]) {
    testWidgets(
      'startup resolves journal before loading, malformed=$malformed',
      (tester) async {
        final prefs = SharedPreferencesAsync();
        final journal = malformed
            ? '{invalid'
            : LocalStorage.encodeRestoreJournalForTesting(
                settings: await prefs.getString(storage.settingsKey),
                workEntries: originalRaw,
                exportRecords: await prefs.getString(storage.exportsKey),
                dataVersion: null,
              );
        await prefs.setString(storage.journalKey, journal);
        await LocalStorage.saveSettings(replacementSettings);
        await LocalStorage.saveEntries([replacement]);
        await LocalStorage.saveExportRecords([replacementExport]);
        await tester.pumpWidget(
          MaterialApp(
            home: BriskaShell(
              appLockConfigLoader: () async => const AppLockConfig(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (malformed) {
          final recovery = tester.widget<StartupRecoveryScreen>(
            find.byType(StartupRecoveryScreen),
          );
          expect(recovery.restoreRecoveryRequired, isTrue);
          await recovery.onRetry();
          await tester.pumpAndSettle();
          expect(find.byType(StartupRecoveryScreen), findsOneWidget);
          expect(await prefs.getString(storage.journalKey), journal);
          expect((await LocalStorage.loadEntries()).single.id, replacement.id);
          expect(
            (await LocalStorage.loadSettings()).toJson(),
            replacementSettings.toJson(),
          );
          expect(
            (await LocalStorage.loadExportRecords()).single.toJson(),
            replacementExport.toJson(),
          );
        } else {
          expect(await prefs.getString(storage.entriesKey), originalRaw);
          expect(await prefs.getString(storage.journalKey), isNull);
          expect(find.byType(StartupRecoveryScreen), findsNothing);
          expect(
            (await LocalStorage.loadSettings()).toJson(),
            originalSettings.toJson(),
          );
          expect(
            (await LocalStorage.loadExportRecords()).single.toJson(),
            originalExport.toJson(),
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final mode in ['before', 'after', 'silent', 'success']) {
    for (final lockDuringCommit in [false, true]) {
      if (mode == 'success' && !lockDuringCommit) continue;
      for (final failedLoad in <String?>[
        null,
        if (!lockDuringCommit && (mode == 'before' || mode == 'after')) ...[
          storage.settingsKey,
          storage.entriesKey,
          storage.exportsKey,
        ],
      ]) {
        testWidgets(
          'ambiguous deletion $mode, locked=$lockDuringCommit, failedLoad=$failedLoad blocks stale saves and reconciles',
          (tester) async {
            var now = DateTime(2026, 11, 9);
            await tester.pumpWidget(
              MaterialApp(
                home: BriskaShell(
                  useLocalStorage: false,
                  initialSettings: originalSettings,
                  initialEntries: [original],
                  initialExports: [originalExport],
                  appLockConfigLoader: () async => AppLockConfig(
                    enabled: lockDuringCommit,
                    hasPin: lockDuringCommit,
                    lockAfterSeconds: 60,
                  ),
                  lockClock: () => now,
                  pinVerifier: (_) async => true,
                ),
              ),
            );
            await tester.pumpAndSettle();
            Future<void> unlock() async {
              await tester.enterText(find.byType(TextField), '1234');
              await tester.tap(find.text('Unlock'));
              await tester.pumpAndSettle();
            }

            if (lockDuringCommit) await unlock();
            await fixtures.tab(tester, 'Entries');
            tester
                .widget<EntriesScreen>(find.byType(EntriesScreen))
                .onEdit(original);
            await tester.pumpAndSettle();
            final staleSave = tester
                .widget<AddWorkDayScreen>(find.byType(AddWorkDayScreen))
                .onSave;
            await tester.pageBack();
            await tester.pumpAndSettle();
            await fixtures.tab(tester, 'Export');
            final staleLibrary = tester.widget<ExportScreen>(
              find.byType(ExportScreen),
            );
            await fixtures.tab(tester, 'Settings');
            final settings = tester.widget<SettingsScreen>(
              find.byType(SettingsScreen),
            );
            final deletionEntered = Completer<void>();
            final release = Completer<void>();
            platform.store.journalDeleteFailure = mode == 'success'
                ? null
                : mode;
            platform.store.beforeJournalDelete = () async {
              platform.store.beforeJournalDelete = null;
              deletionEntered.complete();
              await release.future;
            };
            var done = false;
            final restoring = settings.onRestoreBackup().whenComplete(
              () => done = true,
            );
            await pumpUntil(
              tester,
              () =>
                  find.text('Restore Briska Pay backup?').evaluate().isNotEmpty,
            );
            await tester.tap(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.text('Restore'),
              ),
            );
            await pumpUntil(tester, () => deletionEntered.isCompleted);
            final queuedSave = staleSave(original);
            final queuedSettings = expectLater(
              Future<void>.sync(
                () => settings.onPreferencesChanged(
                  originalSettings.copyWith(fullName: 'Stale queued settings'),
                ),
              ),
              throwsA(isA<Exception>()),
            );
            final queuedExport = staleLibrary.onAdd(staleExport);
            if (lockDuringCommit) {
              for (final state in [
                AppLifecycleState.inactive,
                AppLifecycleState.hidden,
                AppLifecycleState.paused,
              ]) {
                tester.binding.handleAppLifecycleStateChanged(state);
              }
              now = now.add(const Duration(seconds: 61));
              for (final state in [
                AppLifecycleState.hidden,
                AppLifecycleState.inactive,
                AppLifecycleState.resumed,
              ]) {
                tester.binding.handleAppLifecycleStateChanged(state);
              }
              await tester.pumpAndSettle();
            }
            release.complete();
            await pumpUntil(tester, () => done);
            await restoring;
            expect(await queuedSave, isFalse);
            await queuedSettings;
            expect(await queuedExport, isFalse);
            expect(await staleSave(original), isFalse);
            Future<void> assertMutationsBlocked() async {
              final before = await rawDatasets();
              expect(await staleSave(original), isFalse);
              await expectLater(
                Future<void>.sync(
                  () => settings.onPreferencesChanged(
                    originalSettings.copyWith(fullName: 'Stale settings'),
                  ),
                ),
                throwsA(isA<Exception>()),
              );
              expect(await staleLibrary.onAdd(staleExport), isFalse);
              expect(
                await staleLibrary.onUpdate(
                  originalExport.copyWith(fileName: 'stale.pdf'),
                ),
                isFalse,
              );
              expect(await staleLibrary.onDelete(originalExport), isFalse);
              expect(await rawDatasets(), before);
            }

            await assertMutationsBlocked();
            expect(
              find.textContaining('Your existing data has been kept'),
              findsNothing,
            );
            if (lockDuringCommit) {
              expect(find.byType(AppLockScreen), findsOneWidget);
              expect(find.byType(StartupRecoveryScreen), findsNothing);
              expect(
                find.byType(EntriesScreen, skipOffstage: false),
                findsNothing,
              );
              await unlock();
            }
            var recovery = tester.widget<StartupRecoveryScreen>(
              find.byType(StartupRecoveryScreen),
            );
            expect(recovery.restoreRecoveryRequired, isTrue);
            if (mode == 'before' || mode == 'silent') {
              // Parsing would succeed; failed recovery must nevertheless block Retry.
              await recovery.onRetry();
              await tester.pumpAndSettle();
              recovery = tester.widget<StartupRecoveryScreen>(
                find.byType(StartupRecoveryScreen),
              );
              expect(recovery.restoreRecoveryRequired, isTrue);
              expect(await staleSave(original), isFalse);
              expect(
                await SharedPreferencesAsync().getString(storage.journalKey),
                isNotNull,
              );
            }
            platform.store.journalDeleteFailure = null;
            if (failedLoad != null) {
              var loadAttempted = false;
              LocalStorage.readStringOverride = (key) async {
                expect(
                  await SharedPreferencesAsync().getString(storage.journalKey),
                  isNull,
                );
                if (key == failedLoad) {
                  loadAttempted = true;
                  throw StateError('Injected dataset read failure');
                }
                return SharedPreferencesAsync().getString(key);
              };
              await recovery.onRetry();
              await tester.pumpAndSettle();
              expect(loadAttempted, isTrue);
              expect(
                await SharedPreferencesAsync().getString(storage.journalKey),
                isNull,
              );
              recovery = tester.widget<StartupRecoveryScreen>(
                find.byType(StartupRecoveryScreen),
              );
              expect(recovery.restoreRecoveryRequired, isTrue);
              expect(find.byType(NavigationBar), findsNothing);
              await assertMutationsBlocked();
              // Even direct invocations of disabled reset/import callbacks cannot write.
              final beforeDisabledActions = await rawDatasets();
              await recovery.onResetLocalData();
              await recovery.onRestoreBackup();
              expect(find.byType(AlertDialog), findsNothing);
              expect(await rawDatasets(), beforeDisabledActions);
              LocalStorage.readStringOverride = null;
            }
            await recovery.onRetry();
            await tester.pumpAndSettle();
            expect(find.byType(StartupRecoveryScreen), findsNothing);
            expect(
              await SharedPreferencesAsync().getString(storage.journalKey),
              isNull,
            );
            final committed = mode == 'after' || mode == 'success';
            final expected = committed ? replacement : original;
            final expectedSettings = committed
                ? replacementSettings
                : originalSettings;
            final expectedExport = committed
                ? replacementExport
                : originalExport;
            expect((await LocalStorage.loadEntries()).single.id, expected.id);
            expect(
              (await LocalStorage.loadEntries()).single.toJson(),
              expected.toJson(),
            );
            expect(
              (await LocalStorage.loadSettings()).toJson(),
              expectedSettings.toJson(),
            );
            expect(
              (await LocalStorage.loadExportRecords())
                  .map((e) => e.toJson())
                  .toList(),
              [expectedExport.toJson()],
            );
            if (!committed) {
              expect(
                await SharedPreferencesAsync().getString(storage.entriesKey),
                originalRaw,
              );
            }
            expect(await staleSave(original), isFalse);
            await assertMutationsBlocked();
            await fixtures.tab(tester, 'Settings');
            final freshSettings = tester.widget<SettingsScreen>(
              find.byType(SettingsScreen),
            );
            expect(
              freshSettings.preferences.toJson(),
              expectedSettings.toJson(),
            );
            await fixtures.tab(tester, 'Export');
            final freshLibrary = tester.widget<ExportScreen>(
              find.byType(ExportScreen),
            );
            expect(freshLibrary.settings.toJson(), expectedSettings.toJson());
            expect(freshLibrary.records.map((e) => e.toJson()).toList(), [
              expectedExport.toJson(),
            ]);
            expect(freshLibrary.entries.single.toJson(), expected.toJson());
            final addedExport = record('fresh-export', 180);
            expect(await freshLibrary.onAdd(addedExport), isTrue);
            expect(
              (await LocalStorage.loadExportRecords()).map((e) => e.toJson()),
              unorderedEquals([expectedExport.toJson(), addedExport.toJson()]),
            );
            final changedSettings = freshSettings.preferences.copyWith(
              defaultBreakMinutes: 15,
            );
            await Future<void>.sync(
              () => freshSettings.onPreferencesChanged(changedSettings),
            );
            expect(
              (await LocalStorage.loadSettings()).toJson(),
              changedSettings.toJson(),
            );
            await fixtures.tab(tester, 'Entries');
            final entries = tester.widget<EntriesScreen>(
              find.byType(EntriesScreen),
            );
            expect(entries.entries.single.id, expected.id);
            entries.onEdit(expected);
            await tester.pumpAndSettle();
            final freshSave = tester
                .widget<AddWorkDayScreen>(find.byType(AddWorkDayScreen))
                .onSave;
            expect(
              await freshSave(fixtures.entry('new', DateTime(2026, 7, 16))),
              isTrue,
            );
            expect(
              (await LocalStorage.loadEntries()).map((e) => e.id),
              containsAll([expected.id, 'new']),
            );
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
