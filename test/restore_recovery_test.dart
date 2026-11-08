import 'package:briska/src/local_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

const settings = 'app_settings_v1';
const entries = 'work_entries_v1';
const exports = 'export_records_v1';
const version = 'briska_data_version';
const journal = 'briska_restore_journal';
const original = <String, Object>{
  settings: ' {"legacy":true} ',
  entries: '[ {"wages":123.4500,"totalHours":25,"startTime":"bad"} ]\n',
  exports: '[] ',
  version: 42,
};

final class RecoveryStore extends InMemorySharedPreferencesAsync {
  RecoveryStore(super.data) : super.withData();
  final writes = <String>[];
  String? failKey;
  String? silentKey;
  String? unreadKey;
  String? deleteFailure;
  int? interruptAfter;
  Map<String, Object>? interrupted;

  Future<Map<String, Object>> dump() => super.getPreferences(
    const GetPreferencesParameters(filter: PreferencesFilters()),
    const SharedPreferencesOptions(),
  );

  Future<bool> write(String key, Future<bool> Function() action) async {
    writes.add(key);
    if (interrupted != null || key == failKey) {
      throw StateError('private fixture/path');
    }
    if (key == silentKey) return true;
    final result = await action();
    if (writes.length == interruptAfter) {
      interrupted = await dump();
      throw StateError('simulated process interruption');
    }
    return result;
  }

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) => write(key, () => super.setString(key, value, options));
  @override
  Future<bool> setInt(
    String key,
    int value,
    SharedPreferencesOptions options,
  ) => write(key, () => super.setInt(key, value, options));
  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) {
    if (key == unreadKey) throw StateError('private fixture/path');
    return super.getString(key, options);
  }

  @override
  Future<bool> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    final key = parameters.filter.allowList!.single;
    return write(key, () async {
      if (key == journal && deleteFailure == 'before') {
        throw StateError('delete');
      }
      if (key == journal && deleteFailure == 'silent') return true;
      final result = await super.clear(parameters, options);
      if (key == journal && deleteFailure == 'after') {
        throw StateError('delete');
      }
      return result;
    });
  }
}

// SharedPreferencesAsync captures its platform instance. Keep that facade stable
// while replacing the entire simulated persisted backend and fault state.
final class RecoveryPlatform extends InMemorySharedPreferencesAsync {
  RecoveryPlatform() : super.empty();
  late RecoveryStore store;
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
  final platform = RecoveryPlatform();
  late SharedPreferencesAsyncPlatform? previous;
  setUp(() {
    previous = SharedPreferencesAsyncPlatform.instance;
  });
  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = previous;
    LocalStorage.restoreWriteHook = null;
  });
  String encode(Map<String, Object> values) =>
      LocalStorage.encodeRestoreJournalForTesting(
        settings: values[settings] as String?,
        workEntries: values[entries] as String?,
        exportRecords: values[exports] as String?,
        dataVersion: values[version] as int?,
      );
  RecoveryStore install(Map<String, Object> data) {
    final store = RecoveryStore(data);
    platform.store = store;
    SharedPreferencesAsyncPlatform.instance = platform;
    return store;
  }

  Map<String, Object> pending([Map<String, Object> values = original]) => {
    settings: 'replacement settings',
    entries: 'replacement entries',
    exports: 'replacement exports',
    version: 3,
    'unrelated': 'keep',
    journal: encode(values),
  };
  Future<void> fails() => expectLater(
    LocalStorage.recoverPendingRestore(),
    throwsA(
      isA<LocalRestoreRecoveryRequiredException>().having(
        (e) => e.toString(),
        'sanitized error',
        'Saved data recovery could not be completed. Please retry.',
      ),
    ),
  );

  test('no journal performs no writes', () async {
    final store = install({...original, 'unrelated': 'keep'});
    await LocalStorage.recoverPendingRestore();
    expect(store.writes, isEmpty);
    expect(await store.dump(), {...original, 'unrelated': 'keep'});
  });
  test(
    'exact historical strings restored in reverse order and recovery repeats safely',
    () async {
      final store = install(pending());
      await LocalStorage.recoverPendingRestore();
      expect(store.writes, [version, exports, entries, settings, journal]);
      expect(await store.dump(), {...original, 'unrelated': 'keep'});
      store.writes.clear();
      await LocalStorage.recoverPendingRestore();
      expect(store.writes, isEmpty);
    },
  );
  test('originally absent keys are removed, including version', () async {
    final store = install(pending({}));
    await LocalStorage.recoverPendingRestore();
    expect(await store.dump(), {'unrelated': 'keep'});
    expect(store.writes, [version, exports, entries, settings, journal]);
  });
  for (var boundary = 1; boundary <= 5; boundary++) {
    test('fresh backend recovers after write boundary $boundary', () async {
      final first = install(pending())..interruptAfter = boundary;
      await fails();
      final restarted = install(first.interrupted!);
      await LocalStorage.recoverPendingRestore();
      expect(await restarted.dump(), {...original, 'unrelated': 'keep'});
      if (boundary == 5) expect(restarted.writes, isEmpty);
    });
  }
  for (final key in [settings, entries, exports, version]) {
    test(
      'failure at $key retains journal and attempts remaining stages',
      () async {
        final store = install(pending())..failKey = key;
        await fails();
        expect(store.writes, [version, exports, entries, settings]);
        expect((await store.dump())[journal], encode(original));
        final restarted = install(await store.dump());
        await LocalStorage.recoverPendingRestore();
        expect(await restarted.dump(), {...original, 'unrelated': 'keep'});
      },
    );
    test('silent failed write at $key is detected by verification', () async {
      final store = install(pending())..silentKey = key;
      await fails();
      expect(store.writes, [version, exports, entries, settings]);
      expect((await store.dump())[journal], encode(original));
    });
  }
  test('verification read failure retains journal', () async {
    final store = install(pending())..unreadKey = entries;
    await fails();
    expect((await store.dump())[journal], encode(original));
    expect(store.writes, isNot(contains(journal)));
  });
  for (final invalid in [
    '{secret',
    '{"journalVersion":2,"original":{}}',
    '{}',
    12,
  ]) {
    test('invalid journal $invalid remains untouched', () async {
      final data = pending()..[journal] = invalid;
      final store = install(data);
      await fails();
      expect(store.writes, isEmpty);
      expect(await store.dump(), data);
    });
  }
  test('unreadable journal prevents all writes', () async {
    final store = install(pending())..unreadKey = journal;
    await fails();
    expect(store.writes, isEmpty);
    expect(await store.dump(), pending());
  });
  for (final mode in ['before', 'after', 'silent']) {
    test('journal deletion failure $mode is safe on retry', () async {
      final store = install(pending())..deleteFailure = mode;
      await fails();
      final persisted = await store.dump();
      expect(persisted.containsKey(journal), mode != 'after');
      final restarted = install(persisted);
      await LocalStorage.recoverPendingRestore();
      expect(await restarted.dump(), {...original, 'unrelated': 'keep'});
    });
  }
}
