import 'dart:async';

import 'package:briska/src/local_storage.dart';
import 'package:briska/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

const journalKey = 'briska_restore_journal';
const settingsKey = 'app_settings_v1';
const entriesKey = 'work_entries_v1';
const exportsKey = 'export_records_v1';
const versionKey = 'briska_data_version';

final class JournalFailureStore extends InMemorySharedPreferencesAsync {
  JournalFailureStore(super.data) : super.withData();

  bool failJournalWrite = false;
  bool silentJournalWrite = false;
  String? journalDeleteFailure;
  final writes = <String>[];
  Future<void> Function(String key)? beforeRead;
  Future<void> Function()? beforeJournalDelete;

  @override
  Future<String?> getString(
    String key,
    SharedPreferencesOptions options,
  ) async {
    await beforeRead?.call(key);
    return super.getString(key, options);
  }

  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) async {
    await beforeRead?.call(key);
    return super.getInt(key, options);
  }

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) {
    writes.add(key);
    if (key == journalKey && failJournalWrite) {
      throw StateError('Simulated journal write failure');
    }
    if (key == journalKey && silentJournalWrite) {
      return Future<bool>.value(true);
    }
    return super.setString(key, value, options);
  }

  @override
  Future<bool> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    final keys = parameters.filter.allowList;
    if (keys == null || keys.length != 1 || !keys.contains(journalKey)) {
      return super.clear(parameters, options);
    }
    await beforeJournalDelete?.call();

    if (journalDeleteFailure == 'before') {
      throw StateError('Simulated deletion failure');
    }
    if (journalDeleteFailure == 'silent') {
      return true;
    }

    final result = await super.clear(parameters, options);

    if (journalDeleteFailure == 'after') {
      throw StateError('Simulated deletion failure');
    }

    return result;
  }
}

final class JournalFailurePlatform extends InMemorySharedPreferencesAsync {
  JournalFailurePlatform() : super.empty();

  late JournalFailureStore store;

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
  final platform = JournalFailurePlatform();
  late SharedPreferencesAsyncPlatform? previous;

  setUp(() {
    previous = SharedPreferencesAsyncPlatform.instance;
    LocalStorage.restoreWriteHook = null;
    platform.store = JournalFailureStore({
      settingsKey: ' {"legacy":true} ',
      entriesKey: '[{"wages":123.4500}]',
      exportsKey: '[] ',
      versionKey: 42,
    });
    SharedPreferencesAsyncPlatform.instance = platform;
  });

  tearDown(() {
    LocalStorage.restoreWriteHook = null;
    SharedPreferencesAsyncPlatform.instance = previous;
  });

  for (final boundary in [
    'before writes',
    settingsKey,
    entriesKey,
    exportsKey,
    versionKey,
    journalKey,
  ]) {
    test('session invalidation at $boundary uses verified rollback', () async {
      final preferences = SharedPreferencesAsync();
      final entered = Completer<void>();
      final release = Completer<void>();
      var valid = boundary != 'before writes';
      final rollbackStages = <RestoreWriteStage>[];
      LocalStorage.restoreWriteHook = (stage, rollback) async {
        if (rollback) {
          rollbackStages.add(stage);
          expect(await preferences.getString(journalKey), isNotNull);
        } else if (stage == RestoreWriteStage.dataVersion) {
          platform.store.beforeRead = (key) async {
            if (key != boundary) return;
            platform.store.beforeRead = null;
            entered.complete();
            await release.future;
          };
        }
      };
      final result = expectLater(
        LocalStorage.replaceAll(
          settings: const AppSettings(fullName: 'Replacement'),
          entries: const [],
          exportRecords: const [],
          validateOperation: () {
            if (!valid) throw StateError('Session invalidated');
          },
        ),
        throwsA(isA<LocalRestoreException>()),
      );
      if (boundary != 'before writes') {
        await entered.future;
        valid = false;
        release.complete();
      }
      await result;
      expect(rollbackStages, RestoreWriteStage.values.reversed.toList());
      expect(await preferences.getString(settingsKey), ' {"legacy":true} ');
      expect(await preferences.getString(entriesKey), '[{"wages":123.4500}]');
      expect(await preferences.getString(exportsKey), '[] ');
      expect(await preferences.getInt(versionKey), 42);
      expect(await preferences.getString(journalKey), isNull);
    });
  }

  for (final failureMode in ['before', 'after', 'silent']) {
    test('journal deletion failure $failureMode is handled safely', () async {
      final preferences = SharedPreferencesAsync();

      platform.store.journalDeleteFailure = failureMode;

      var rollbackStarted = false;

      LocalStorage.restoreWriteHook = (stage, isRollback) async {
        if (isRollback) rollbackStarted = true;
      };

      await expectLater(
        LocalStorage.replaceAll(
          settings: const AppSettings(fullName: 'Replacement'),
          entries: const [],
          exportRecords: const [],
        ),
        throwsA(isA<LocalRestoreRecoveryRequiredException>()),
      );

      // The commit boundary must never trigger automatic rollback.
      expect(rollbackStarted, isFalse);

      // Replacement data was written before journal deletion.
      final savedSettings = await preferences.getString(settingsKey);
      expect(savedSettings, contains('Replacement'));
      expect(await preferences.getString(entriesKey), '[]');
      expect(await preferences.getString(exportsKey), '[]');
      expect(
        await preferences.getInt(versionKey),
        LocalStorage.currentDataVersion,
      );

      final pendingJournal = await preferences.getString(journalKey);

      if (failureMode == 'after') {
        // Deletion took effect despite reporting an error.
        expect(pendingJournal, isNull);
      } else {
        // Recovery information must remain available.
        expect(pendingJournal, isNotNull);
      }
    });
  }
  test('silent journal write failure prevents dataset changes', () async {
    final preferences = SharedPreferencesAsync();

    platform.store.silentJournalWrite = true;

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
    expect(platform.store.writes, [journalKey]);

    expect(await preferences.getString(settingsKey), ' {"legacy":true} ');
    expect(await preferences.getString(entriesKey), '[{"wages":123.4500}]');
    expect(await preferences.getString(exportsKey), '[] ');
    expect(await preferences.getInt(versionKey), 42);
    expect(await preferences.getString(journalKey), isNull);
  });
  test('journal write failure prevents all dataset changes', () async {
    final preferences = SharedPreferencesAsync();

    platform.store.failJournalWrite = true;

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
    expect(platform.store.writes, [journalKey]);

    expect(await preferences.getString(settingsKey), ' {"legacy":true} ');
    expect(await preferences.getString(entriesKey), '[{"wages":123.4500}]');
    expect(await preferences.getString(exportsKey), '[] ');
    expect(await preferences.getInt(versionKey), 42);
    expect(await preferences.getString(journalKey), isNull);
  });
}
