import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'currency.dart';

enum LocalDataSet { settings, workEntries, exportLibrary }

enum RestoreWriteStage { settings, workEntries, exportLibrary, dataVersion }

final class LocalRestoreException implements Exception {
  const LocalRestoreException();

  @override
  String toString() => 'The restore could not be completed.';
}

final class LocalRestoreRollbackException implements Exception {
  const LocalRestoreRollbackException();

  @override
  String toString() => 'The restore rollback could not be completed.';
}

final class LocalRestoreRecoveryRequiredException implements Exception {
  const LocalRestoreRecoveryRequiredException();

  @override
  String toString() =>
      'Saved data recovery could not be completed. Please retry.';
}

sealed class LocalDataLoadException implements Exception {
  const LocalDataLoadException(this.dataSet);

  final LocalDataSet dataSet;
}

final class LocalDataCorruptionException extends LocalDataLoadException {
  const LocalDataCorruptionException(super.dataSet);

  @override
  String toString() => 'Local data is malformed (${dataSet.name}).';
}

final class LocalDataReadException extends LocalDataLoadException {
  const LocalDataReadException(super.dataSet);

  @override
  String toString() => 'Local data could not be read (${dataSet.name}).';
}

class LocalStorage {
  LocalStorage._();

  // Pure codec seams: no preferences are read or written by these helpers.
  @visibleForTesting
  static String get restoreJournalKeyForTesting => _RestoreJournal.storageKey;

  @visibleForTesting
  static String encodeRestoreJournalForTesting({
    required String? settings,
    required String? workEntries,
    required String? exportRecords,
    required int? dataVersion,
  }) => _RestoreJournal(
    _RestoreSnapshot(
      settings: settings,
      entries: workEntries,
      exports: exportRecords,
      dataVersion: dataVersion,
    ),
  ).encode();

  @visibleForTesting
  static String roundTripRestoreJournalForTesting(String encoded) =>
      _RestoreJournal.decode(encoded).encode();

  static const _entriesKey = 'work_entries_v1';
  static const _settingsKey = 'app_settings_v1';
  static const _exportsKey = 'export_records_v1';
  static const _dataVersionKey = 'briska_data_version';
  static const _betaChecklistKey = 'beta_checklist_v1';
  static const currentDataVersion = 3;
  static final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  @visibleForTesting
  static Future<void> Function(List<WorkEntry>)? saveEntriesOverride;
  @visibleForTesting
  static Future<void> Function(List<ExportedFileRecord>)?
  saveExportRecordsOverride;
  @visibleForTesting
  static Future<String?> Function(String key)? readStringOverride;
  @visibleForTesting
  static Future<void> Function(RestoreWriteStage stage, bool isRollback)?
  restoreWriteHook;

  static Future<String?> _readString(String key, LocalDataSet dataSet) async {
    try {
      final override = readStringOverride;
      return override != null
          ? await override(key)
          : await _preferences.getString(key);
    } catch (_) {
      throw LocalDataReadException(dataSet);
    }
  }

  static Future<int> loadDataVersion() async {
    return await _preferences.getInt(_dataVersionKey) ?? 0;
  }

  static Future<void> markCurrentDataVersion() {
    return _preferences.setInt(_dataVersionKey, currentDataVersion);
  }

  static Future<List<WorkEntry>> loadEntries() async {
    final value = await _readString(_entriesKey, LocalDataSet.workEntries);
    if (value == null) return [];
    late List<WorkEntry> entries;
    try {
      final data = jsonDecode(value) as List<dynamic>;
      entries =
          data
              .map((item) => WorkEntry.fromJson(item as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
    } catch (_) {
      throw const LocalDataCorruptionException(LocalDataSet.workEntries);
    }
    return entries;
  }

  static Future<void> saveEntries(List<WorkEntry> entries) {
    final override = saveEntriesOverride;
    if (override != null) return override(entries);
    return _preferences.setString(
      _entriesKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  static Future<AppSettings> loadSettings() async {
    final value = await _readString(_settingsKey, LocalDataSet.settings);
    if (value == null) return const AppSettings();
    late AppSettings settings;
    late Map<String, dynamic> json;
    try {
      json = jsonDecode(value) as Map<String, dynamic>;
      settings = AppSettings.fromJson(json);
    } catch (_) {
      throw const LocalDataCorruptionException(LocalDataSet.settings);
    }
    if (json['currency'] == null ||
        settings.themeMode == 'system' ||
        json['themeMode'] == 'ThemeMode.system' ||
        json.containsKey('dailyAllowance') ||
        json.containsKey('homeHourlyRate') ||
        !json.containsKey('primaryRateLabel')) {
      var migrated = json['currency'] == null
          ? settings.copyWith(
              currency: CurrencyCatalog.fromLocale(Platform.localeName),
            )
          : settings;
      if (json['themeMode'] == 'system' ||
          json['themeMode'] == 'ThemeMode.system') {
        migrated = migrated.copyWith(
          themeMode:
              PlatformDispatcher.instance.platformBrightness == Brightness.dark
              ? 'dark'
              : 'light',
        );
      }
      await saveSettings(migrated);
      return migrated;
    }
    return settings;
  }

  @visibleForTesting
  static Future<void> Function(AppSettings)? saveSettingsOverride;

  static Future<void> saveSettings(AppSettings settings) {
    final override = saveSettingsOverride;
    if (override != null) return override(settings);
    return _preferences.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  static Future<List<ExportedFileRecord>> loadExportRecords() async {
    final value = await _readString(_exportsKey, LocalDataSet.exportLibrary);
    if (value == null) return [];
    try {
      final data = jsonDecode(value) as List<dynamic>;
      return data
          .map(
            (item) => ExportedFileRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList()
        ..sort((a, b) => b.exportedAt.compareTo(a.exportedAt));
    } on LocalDataLoadException {
      rethrow;
    } catch (_) {
      throw const LocalDataCorruptionException(LocalDataSet.exportLibrary);
    }
  }

  static Future<void> saveExportRecords(List<ExportedFileRecord> records) {
    final override = saveExportRecordsOverride;
    if (override != null) return override(records);
    return _preferences.setString(
      _exportsKey,
      jsonEncode(records.map((record) => record.toJson()).toList()),
    );
  }

  static Future<Set<String>> loadBetaChecklist() async {
    return (await _preferences.getStringList(_betaChecklistKey) ?? <String>[])
        .toSet();
  }

  static Future<void> saveBetaChecklist(Set<String> completedItems) {
    final sortedItems = completedItems.toList()..sort();
    return _preferences.setStringList(_betaChecklistKey, sortedItems);
  }

  /// Replays an unfinished restore's raw snapshot. Call before normal data use;
  /// callers must exclude concurrent dataset mutations during recovery.
  static Future<void> recoverPendingRestore() async {
    try {
      final encoded = await _preferences.getString(_RestoreJournal.storageKey);
      if (encoded == null) return;
      final snapshot = _RestoreJournal.decode(encoded).original;
      if (!await _rollbackRestore(snapshot)) {
        throw const LocalRestoreRecoveryRequiredException();
      }
      final settings = await _preferences.getString(_settingsKey);
      final entries = await _preferences.getString(_entriesKey);
      final exports = await _preferences.getString(_exportsKey);
      final version = await _preferences.getInt(_dataVersionKey);
      if (settings != snapshot.settings ||
          entries != snapshot.entries ||
          exports != snapshot.exports ||
          version != snapshot.dataVersion ||
          await _preferences.getString(_RestoreJournal.storageKey) != encoded) {
        throw const LocalRestoreRecoveryRequiredException();
      }
      await _preferences.remove(_RestoreJournal.storageKey);
      if (await _preferences.getString(_RestoreJournal.storageKey) != null) {
        throw const LocalRestoreRecoveryRequiredException();
      }
    } catch (_) {
      // Never attach raw storage errors or journal contents to a UI exception.
      throw const LocalRestoreRecoveryRequiredException();
    }
  }

  static Future<void> replaceAll({
    required AppSettings settings,
    required List<WorkEntry> entries,
    required List<ExportedFileRecord> exportRecords,
    // Throw to cancel an invalidated caller and use the same rollback as a
    // storage failure. Check again after the last write before committing.
    void Function()? validateOperation,
  }) async {
    late final _RestoreSnapshot original;
    try {
      original = _RestoreSnapshot(
        settings: await _preferences.getString(_settingsKey),
        entries: await _preferences.getString(_entriesKey),
        exports: await _preferences.getString(_exportsKey),
        dataVersion: await _preferences.getInt(_dataVersionKey),
      );
    } catch (_) {
      throw const LocalRestoreException();
    }

    try {
      await _beforeRestoreWrite(RestoreWriteStage.settings);
      validateOperation?.call();
      await saveSettings(settings);
      await _beforeRestoreWrite(RestoreWriteStage.workEntries);
      validateOperation?.call();
      await saveEntries(entries);
      await _beforeRestoreWrite(RestoreWriteStage.exportLibrary);
      validateOperation?.call();
      await saveExportRecords(exportRecords);
      await _beforeRestoreWrite(RestoreWriteStage.dataVersion);
      validateOperation?.call();
      await markCurrentDataVersion();
      validateOperation?.call();
    } catch (_) {
      if (!await _rollbackRestore(original)) {
        throw const LocalRestoreRollbackException();
      }
      throw const LocalRestoreException();
    }
  }

  static Future<void> _beforeRestoreWrite(RestoreWriteStage stage) async {
    await restoreWriteHook?.call(stage, false);
  }

  static Future<bool> _rollbackRestore(_RestoreSnapshot snapshot) async {
    var completed = true;
    for (final stage in RestoreWriteStage.values.reversed) {
      try {
        await restoreWriteHook?.call(stage, true);
        switch (stage) {
          case RestoreWriteStage.settings:
            await _restoreString(_settingsKey, snapshot.settings);
          case RestoreWriteStage.workEntries:
            await _restoreString(_entriesKey, snapshot.entries);
          case RestoreWriteStage.exportLibrary:
            await _restoreString(_exportsKey, snapshot.exports);
          case RestoreWriteStage.dataVersion:
            final version = snapshot.dataVersion;
            if (version == null) {
              await _preferences.remove(_dataVersionKey);
            } else {
              await _preferences.setInt(_dataVersionKey, version);
            }
        }
      } catch (_) {
        completed = false;
      }
    }
    return completed;
  }

  static Future<void> _restoreString(String key, String? value) {
    return value == null
        ? _preferences.remove(key)
        : _preferences.setString(key, value);
  }

  static Future<void> resetLocalData() async {
    await _preferences.remove(_entriesKey);
    await _preferences.remove(_settingsKey);
    await _preferences.remove(_exportsKey);
    await _preferences.remove(_dataVersionKey);
    await _preferences.remove(_betaChecklistKey);
  }
}

final class _RestoreSnapshot {
  const _RestoreSnapshot({
    required this.settings,
    required this.entries,
    required this.exports,
    required this.dataVersion,
  });

  final String? settings;
  final String? entries;
  final String? exports;
  final int? dataVersion;
}

// Internal undo-journal format, independent of public backups and data versions.
final class _RestoreJournal {
  const _RestoreJournal(this.original);

  static const storageKey = 'briska_restore_journal';
  static const version = 1;
  final _RestoreSnapshot original;

  String encode() => jsonEncode({
    'journalVersion': version,
    'original': {
      'settings': original.settings,
      'workEntries': original.entries,
      'exportRecords': original.exports,
      'dataVersion': original.dataVersion,
    },
  });

  static _RestoreJournal decode(String encoded) {
    Never invalid() => throw const FormatException('Invalid restore journal.');
    Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      invalid();
    }
    // jsonDecode otherwise silently accepts duplicate keys (last value wins).
    // Tokenize only the outer JSON, never the serialized dataset strings.
    final tokens = RegExp(
      r'"(?:[^"\\]|\\.)*"|[{}\[\]:]',
    ).allMatches(encoded).map((m) => m[0]!).toList();
    final objects = <Set<String>?>[];
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token == '{') {
        objects.add(<String>{});
      } else if (token == '[') {
        objects.add(null);
      } else if (token == '}' || token == ']') {
        objects.removeLast();
      } else if (token.startsWith('"') &&
          i + 1 < tokens.length &&
          tokens[i + 1] == ':') {
        if (!objects.last!.add(jsonDecode(token) as String)) invalid();
      }
    }
    bool keys(Object? value, Set<String> expected) =>
        value is Map<String, dynamic> &&
        value.length == expected.length &&
        expected.every(value.containsKey);
    if (!keys(decoded, {'journalVersion', 'original'})) invalid();
    final root = decoded as Map<String, dynamic>;
    if (root['journalVersion'] is! int || root['journalVersion'] != version) {
      invalid();
    }
    final snapshot = root['original'];
    if (!keys(snapshot, {
      'settings',
      'workEntries',
      'exportRecords',
      'dataVersion',
    })) {
      invalid();
    }
    final fields = snapshot as Map<String, dynamic>;
    for (final key in ['settings', 'workEntries', 'exportRecords']) {
      if (fields[key] != null && fields[key] is! String) invalid();
    }
    if (fields['dataVersion'] != null && fields['dataVersion'] is! int) {
      invalid();
    }
    return _RestoreJournal(
      _RestoreSnapshot(
        settings: fields['settings'] as String?,
        entries: fields['workEntries'] as String?,
        exports: fields['exportRecords'] as String?,
        dataVersion: fields['dataVersion'] as int?,
      ),
    );
  }
}
