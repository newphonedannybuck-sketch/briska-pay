import 'dart:convert';

import 'package:briska/src/briska_app.dart';
import 'package:briska/src/local_storage.dart';
import 'package:briska/src/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  const settingsKey = 'app_settings_v1';
  const entriesKey = 'work_entries_v1';
  const exportsKey = 'export_records_v1';
  const versionKey = 'briska_data_version';

  late SharedPreferencesAsync preferences;

  final newEntry = WorkEntry(
    id: 'new-entry',
    date: DateTime(2026, 7, 24),
    siteName: 'New site',
    startTime: '08:00',
    finishTime: '16:00',
    breakMinutes: 30,
    workLocation: 'Home',
    hourlyRateUsed: 25,
    dailyAllowance: 0,
    jobUplift: 0,
    totalHours: 7.5,
    wages: 187.5,
    totalPay: 187.5,
    notes: '',
  );
  final newExport = ExportedFileRecord(
    id: 'new-export',
    fileName: 'new.xlsx',
    fileType: 'Excel',
    filePath: '',
    exportedAt: DateTime(2026, 7, 24),
    periodLabel: 'New period',
    workDays: 1,
    totalHours: 7.5,
    totalPay: 187.5,
  );
  const newSettings = AppSettings(
    onboardingCompleted: true,
    fullName: 'Restored user',
  );

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    LocalStorage.restoreWriteHook = null;
    LocalStorage.saveEntriesOverride = null;
    await preferences.setString(settingsKey, '{"original":"settings"}');
    await preferences.setString(entriesKey, '[{"original":"entries"}]');
    await preferences.setString(exportsKey, '[{"original":"exports"}]');
    await preferences.setInt(versionKey, 1);
  });

  tearDown(() {
    LocalStorage.restoreWriteHook = null;
    LocalStorage.saveEntriesOverride = null;
  });

  Future<void> replaceAll() => LocalStorage.replaceAll(
    settings: newSettings,
    entries: [newEntry],
    exportRecords: [newExport],
  );

  Future<Map<String, Object?>> rawState() async => {
    settingsKey: await preferences.getString(settingsKey),
    entriesKey: await preferences.getString(entriesKey),
    exportsKey: await preferences.getString(exportsKey),
    versionKey: await preferences.getInt(versionKey),
  };

  test('successful transactional restore replaces every dataset', () async {
    await replaceAll();

    expect(
      jsonDecode((await preferences.getString(settingsKey))!)['fullName'],
      'Restored user',
    );
    expect(
      jsonDecode((await preferences.getString(entriesKey))!).single['id'],
      'new-entry',
    );
    expect(
      jsonDecode((await preferences.getString(exportsKey))!).single['id'],
      'new-export',
    );
    expect(
      await preferences.getInt(versionKey),
      LocalStorage.currentDataVersion,
    );
  });

  for (final failureStage in RestoreWriteStage.values) {
    test(
      'failure at ${failureStage.name} restores exact original serialized state',
      () async {
        final original = await rawState();
        LocalStorage.restoreWriteHook = (stage, isRollback) async {
          if (!isRollback && stage == failureStage) {
            throw StateError('injected commit failure');
          }
        };

        await expectLater(replaceAll(), throwsA(isA<LocalRestoreException>()));

        expect(await rawState(), original);
      },
    );
  }

  test('rollback restores absent keys as absent', () async {
    await preferences.remove(exportsKey);
    await preferences.remove(versionKey);
    final original = await rawState();
    LocalStorage.restoreWriteHook = (stage, isRollback) async {
      if (!isRollback && stage == RestoreWriteStage.dataVersion) {
        throw StateError('injected commit failure');
      }
    };

    await expectLater(replaceAll(), throwsA(isA<LocalRestoreException>()));

    expect(await rawState(), original);
  });

  test(
    'rollback failure is reported distinctly and attempts all stages',
    () async {
      final rollbackAttempts = <RestoreWriteStage>[];
      LocalStorage.restoreWriteHook = (stage, isRollback) async {
        if (!isRollback && stage == RestoreWriteStage.exportLibrary) {
          throw StateError('injected commit failure');
        }
        if (isRollback) {
          rollbackAttempts.add(stage);
          if (stage == RestoreWriteStage.settings) {
            throw StateError('injected rollback failure');
          }
        }
      };

      await expectLater(
        replaceAll(),
        throwsA(isA<LocalRestoreRollbackException>()),
      );
      expect(rollbackAttempts, containsAll(RestoreWriteStage.values));
    },
  );

  testWidgets('rollback failure recovery UI is strong and user-safe', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StartupRecoveryScreen(
          error: const LocalRestoreRollbackException().toString(),
          dataIsCorrupt: false,
          restoreRecoveryRequired: true,
          onRetry: () async {},
          onRestoreBackup: () async {},
          onResetLocalData: () async {},
        ),
      ),
    );

    expect(
      find.text("Briska Pay couldn't complete the restore safely"),
      findsOneWidget,
    );
    expect(find.textContaining('may need recovery'), findsOneWidget);
    expect(find.textContaining('SharedPreferences'), findsNothing);
    expect(find.textContaining('app_settings_v1'), findsNothing);
  });
}
