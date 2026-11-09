import 'dart:async';
import 'dart:convert';

import 'package:briska/src/local_storage.dart';
import 'package:briska/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

final class _IntegrationPlatform extends InMemorySharedPreferencesAsync {
  _IntegrationPlatform() : super.empty();

  late InMemorySharedPreferencesAsync store;

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) =>
      store.getString(key, options);

  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) =>
      store.getInt(key, options);

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) => store.setString(key, value, options);

  @override
  Future<bool> setInt(
    String key,
    int value,
    SharedPreferencesOptions options,
  ) => store.setInt(key, value, options);

  @override
  Future<bool> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) => store.clear(parameters, options);
}

void main() {
  final platform = _IntegrationPlatform();
  const settingsKey = 'app_settings_v1';
  const entriesKey = 'work_entries_v1';
  const exportsKey = 'export_records_v1';
  const versionKey = 'briska_data_version';
  const journalKey = 'briska_restore_journal';

  setUp(() {
    platform.store = InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAsyncPlatform.instance = platform;
    LocalStorage.restoreWriteHook = null;
  });

  tearDown(() {
    LocalStorage.restoreWriteHook = null;
  });

  test('concurrent restores are rejected', () async {
    final entered = Completer<void>();
    final release = Completer<void>();

    LocalStorage.restoreWriteHook = (stage, isRollback) async {
      if (stage == RestoreWriteStage.settings && !isRollback) {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      }
    };

    final first = LocalStorage.replaceAll(
      settings: const AppSettings(fullName: 'First restore'),
      entries: const [],
      exportRecords: const [],
    );

    await entered.future;

    try {
      await expectLater(
        LocalStorage.replaceAll(
          settings: const AppSettings(fullName: 'Second restore'),
          entries: const [],
          exportRecords: const [],
        ),
        throwsA(isA<LocalRestoreException>()),
      );
    } finally {
      release.complete();
    }

    await first;

    final preferences = SharedPreferencesAsync();
    final saved =
        jsonDecode((await preferences.getString('app_settings_v1'))!)
            as Map<String, dynamic>;

    expect(saved['fullName'], 'First restore');
  });
  test('existing recovery journal cannot be overwritten', () async {
    final preferences = SharedPreferencesAsync();

    const originalSettings = '{"original":"settings"}';
    const originalEntries = '[{"wages":123.45}]';
    const originalExports = '[]';

    await preferences.setString(settingsKey, originalSettings);
    await preferences.setString(entriesKey, originalEntries);
    await preferences.setString(exportsKey, originalExports);
    await preferences.setInt(versionKey, 42);

    final existingJournal = LocalStorage.encodeRestoreJournalForTesting(
      settings: '{"older":"settings"}',
      workEntries: '[{"older":"entries"}]',
      exportRecords: null,
      dataVersion: 1,
    );

    await preferences.setString(journalKey, existingJournal);

    var restoreWriteStarted = false;

    LocalStorage.restoreWriteHook = (stage, isRollback) async {
      if (!isRollback) restoreWriteStarted = true;
    };

    await expectLater(
      LocalStorage.replaceAll(
        settings: const AppSettings(fullName: 'Replacement'),
        entries: const [],
        exportRecords: const [],
      ),
      throwsA(isA<LocalRestoreRecoveryRequiredException>()),
    );

    expect(restoreWriteStarted, isFalse);
    expect(await preferences.getString(journalKey), existingJournal);
    expect(await preferences.getString(settingsKey), originalSettings);
    expect(await preferences.getString(entriesKey), originalEntries);
    expect(await preferences.getString(exportsKey), originalExports);
    expect(await preferences.getInt(versionKey), 42);
  });
  test('failed restore recovers exact original data', () async {
    final preferences = SharedPreferencesAsync();

    const originalSettings = ' {"legacy":true} ';
    const originalEntries = '[{"wages":123.4500,"totalHours":25}]';
    const originalExports = '[] ';

    await preferences.setString(settingsKey, originalSettings);
    await preferences.setString(entriesKey, originalEntries);
    await preferences.setString(exportsKey, originalExports);
    await preferences.setInt(versionKey, 42);

    LocalStorage.restoreWriteHook = (stage, isRollback) async {
      if (!isRollback && stage == RestoreWriteStage.exportLibrary) {
        throw StateError('Simulated restore failure');
      }
    };

    await expectLater(
      LocalStorage.replaceAll(
        settings: const AppSettings(fullName: 'Replacement'),
        entries: const [],
        exportRecords: const [],
      ),
      throwsA(isA<LocalRestoreException>()),
    );

    expect(await preferences.getString(settingsKey), originalSettings);
    expect(await preferences.getString(entriesKey), originalEntries);
    expect(await preferences.getString(exportsKey), originalExports);
    expect(await preferences.getInt(versionKey), 42);

    // The journal must be removed only after verified recovery.
    expect(await preferences.getString(journalKey), isNull);
  });
  test('original data is journalled before first restore write', () async {
    final preferences = SharedPreferencesAsync();

    const originalSettings = ' {"legacy":true} ';
    const originalEntries = '[{"wages":123.4500}]';
    const originalExports = '[] ';

    await preferences.setString(settingsKey, originalSettings);
    await preferences.setString(entriesKey, originalEntries);
    await preferences.setString(exportsKey, originalExports);
    await preferences.setInt(versionKey, 42);

    var checked = false;

    LocalStorage.restoreWriteHook = (stage, isRollback) async {
      if (stage != RestoreWriteStage.settings || isRollback) return;

      final encoded = await preferences.getString(journalKey);
      expect(encoded, isNotNull);

      final decoded = jsonDecode(encoded!) as Map<String, dynamic>;
      final original = decoded['original'] as Map<String, dynamic>;

      expect(decoded['journalVersion'], 1);
      expect(original['settings'], originalSettings);
      expect(original['workEntries'], originalEntries);
      expect(original['exportRecords'], originalExports);
      expect(original['dataVersion'], 42);

      expect(await preferences.getString(settingsKey), originalSettings);
      expect(await preferences.getString(entriesKey), originalEntries);
      expect(await preferences.getString(exportsKey), originalExports);
      expect(await preferences.getInt(versionKey), 42);

      checked = true;
    };

    await LocalStorage.replaceAll(
      settings: const AppSettings(fullName: 'Restored user'),
      entries: const [],
      exportRecords: const [],
    );

    expect(checked, isTrue);
    expect(await preferences.getString(journalKey), isNull);
  });
}
