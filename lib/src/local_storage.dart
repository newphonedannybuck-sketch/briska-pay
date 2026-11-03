import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'currency.dart';
import 'work_calculator.dart';

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
              .map(WorkCalculator.recalculateEntry)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
    } catch (_) {
      throw const LocalDataCorruptionException(LocalDataSet.workEntries);
    }
    await saveEntries(entries);
    await markCurrentDataVersion();
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

  static Future<void> saveSettings(AppSettings settings) {
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

  static Future<void> replaceAll({
    required AppSettings settings,
    required List<WorkEntry> entries,
    required List<ExportedFileRecord> exportRecords,
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
      await saveSettings(settings);
      await _beforeRestoreWrite(RestoreWriteStage.workEntries);
      await saveEntries(entries);
      await _beforeRestoreWrite(RestoreWriteStage.exportLibrary);
      await saveExportRecords(exportRecords);
      await _beforeRestoreWrite(RestoreWriteStage.dataVersion);
      await markCurrentDataVersion();
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
