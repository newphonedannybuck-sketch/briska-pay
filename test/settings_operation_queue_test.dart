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
import 'package:briska/src/pay_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

AppSettings settings(String name) =>
    AppSettings(onboardingCompleted: true, fullName: name);

class ControlledSettings {
  final snapshots = <AppSettings>[];
  final completions = <Completer<void>>[];
  Future<void> save(AppSettings value) async {
    snapshots.add(value);
    final completion = Completer<void>();
    completions.add(completion);
    await completion.future;
    await SharedPreferencesAsync().setString(
      'app_settings_v1',
      jsonEncode(value.toJson()),
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
  });
  tearDown(() {
    LocalStorage.saveSettingsOverride = null;
    LocalStorage.readStringOverride = null;
    LocalStorage.restoreWriteHook = null;
  });
  Future<SettingsScreen> screen(WidgetTester tester) async {
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    return tester.widget<SettingsScreen>(find.byType(SettingsScreen));
  }

  Future<bool> save(SettingsScreen screen, String name) async {
    try {
      await screen.onPreferencesChanged(settings(name));
      return true;
    } catch (_) {
      return false;
    }
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

  for (final failFirst in [false, true]) {
    testWidgets('sequential settings writes recover: failure=$failFirst', (
      tester,
    ) async {
      await tester.pumpWidget(const BriskaApp());
      await tester.pumpAndSettle();
      final ui = await screen(tester);
      final writes = ControlledSettings();
      LocalStorage.saveSettingsOverride = writes.save;
      final first = save(ui, 'first');
      final second = save(ui, 'second');
      await tester.pump();
      expect(writes.snapshots.map((s) => s.fullName), ['first']);
      if (failFirst) {
        writes.completions.first.completeError(StateError('disk'));
      } else {
        writes.completions.first.complete();
      }
      expect(await first, !failFirst);
      await tester.pump();
      expect(writes.snapshots.map((s) => s.fullName), ['first', 'second']);
      writes.completions.last.complete();
      expect(await second, isTrue);
      await tester.pump();
      expect(
        tester
            .widget<SettingsScreen>(find.byType(SettingsScreen))
            .preferences
            .fullName,
        'second',
      );
      expect((await LocalStorage.loadSettings()).fullName, 'second');
    });
  }

  for (final outcome in ['success', 'failure', 'cancel', 'pickerCancel']) {
    testWidgets('settings around restore: $outcome', (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'settings_restore_',
      );
      final backup = File('${directory.path}/input.json');
      backup.writeAsStringSync(
        jsonEncode(
          BriskaBackupData(
            createdAt: DateTime(2026, 7, 1),
            settings: settings('restored'),
            workEntries: [],
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
        return outcome == 'pickerCancel' ? <String>[] : [backup.path];
      });
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      addTearDown(() {
        messenger.setMockMethodCallHandler(picker, null);
        messenger.setMockMethodCallHandler(paths, null);
        directory.deleteSync(recursive: true);
      });
      await tester.pumpWidget(const BriskaApp());
      await tester.pumpAndSettle();
      final ui = await screen(tester);
      final writes = ControlledSettings();
      LocalStorage.saveSettingsOverride = writes.save;
      final pending = save(ui, 'before');
      await tester.pump();
      var done = false;
      final restoring = ui.onRestoreBackup().then((_) => done = true);
      final queued = save(ui, 'during');
      await tester.pump();
      expect(pickerCalls, 0);
      if (outcome == 'success') {
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'stale company',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
      }
      LocalStorage.saveSettingsOverride = null;
      writes.completions.single.complete();
      expect(await pending, isTrue);
      if (outcome != 'pickerCancel') {
        await pumpUntil(
          tester,
          () => find.text('Restore Briska Pay backup?').evaluate().isNotEmpty,
        );
        if (outcome == 'failure') {
          LocalStorage.restoreWriteHook = (stage, rollback) async {
            if (!rollback && stage == RestoreWriteStage.workEntries) {
              throw StateError('restore');
            }
          };
        }
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(outcome == 'cancel' ? 'Cancel' : 'Restore'),
          ),
        );
      }
      await pumpUntil(tester, () => done);
      await restoring;
      expect(await queued, outcome != 'success');
      expect(
        (await LocalStorage.loadSettings()).fullName,
        outcome == 'success' ? 'restored' : 'during',
      );
      if (outcome == 'success') {
        expect(await save(ui, 'stale UI'), isFalse);
        expect(find.text('Personal details updated.'), findsNothing);
        expect(find.text('Could not save personal details.'), findsNothing);
        expect((await LocalStorage.loadSettings()).fullName, 'restored');
        final safety =
            Directory('${directory.path}/backups').listSync().single as File;
        expect(
          (jsonDecode(safety.readAsStringSync())
              as Map)['settings']['fullName'],
          'before',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final cancel in [false, true]) {
    testWidgets('settings reset ordering and invalidation: cancel=$cancel', (
      tester,
    ) async {
      await LocalStorage.saveSettings(settings('original'));
      LocalStorage.readStringOverride = (_) async => throw StateError('read');
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
      LocalStorage.readStringOverride = null;
      await recovery.onRetry();
      await tester.pumpAndSettle();
      final ui = await screen(tester);
      final writes = ControlledSettings();
      LocalStorage.saveSettingsOverride = writes.save;
      final pending = save(ui, 'before');
      await tester.pump();
      final resetting = recovery.onResetLocalData();
      final queued = save(ui, 'during');
      await tester.pump();
      expect(find.text('Reset local Briska Pay data?'), findsNothing);
      LocalStorage.saveSettingsOverride = null;
      writes.completions.single.complete();
      expect(await pending, isTrue);
      await tester.pumpAndSettle();
      await tester.tap(find.text(cancel ? 'Cancel' : 'Reset data'));
      await tester.pumpAndSettle();
      await resetting;
      expect(await queued, cancel);
      if (cancel) {
        expect((await LocalStorage.loadSettings()).fullName, 'during');
      } else {
        expect(await save(ui, 'stale UI'), isFalse);
        expect(
          (await LocalStorage.loadSettings()).onboardingCompleted,
          isFalse,
        );
        expect(find.byType(OnboardingScreen), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('export preferences report persistence failure and recover', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export').last);
    await tester.pumpAndSettle();
    final export = tester.widget<ExportScreen>(find.byType(ExportScreen));
    LocalStorage.saveSettingsOverride = (_) async =>
        throw StateError('private error');
    export.onPreferencesChanged(settings('failed'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not save settings. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<ExportScreen>(find.byType(ExportScreen)).settings.fullName,
      isNot('failed'),
    );
    LocalStorage.saveSettingsOverride = null;
    export.onPreferencesChanged(settings('retry'));
    await tester.pumpAndSettle();
    expect((await LocalStorage.loadSettings()).fullName, 'retry');
    expect(tester.takeException(), isNull);
  });
  testWidgets('queued theme change retains earlier settings', (tester) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.pumpAndSettle();
    final ui = await screen(tester);
    final writes = ControlledSettings();
    LocalStorage.saveSettingsOverride = writes.save;
    final pending = save(ui, 'new name');
    final theme = ui.onThemeModeChanged(ThemeMode.dark);
    await tester.pump();
    writes.completions.first.complete();
    await pending;
    await tester.pump();
    expect(writes.snapshots.last.fullName, 'new name');
    expect(writes.snapshots.last.themeMode, 'dark');
    writes.completions.last.complete();
    await theme;
  });

  testWidgets('onboarding failure retains entered values and allows retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const BriskaApp(
        initialSettings: AppSettings(
          fullName: 'Entered Name',
          homeHourlyRate: 20,
          awayHourlyRate: 25,
          payFrequency: lastFridayPayFrequency,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final writes = ControlledSettings();
    LocalStorage.saveSettingsOverride = writes.save;
    final button = find.text('Start Using Briska Pay');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(writes.completions, hasLength(1));
    expect(find.byType(OnboardingScreen), findsOneWidget);
    writes.completions.single.completeError(StateError('disk'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not save settings. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Entered Name'), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    LocalStorage.saveSettingsOverride = null;
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsNothing);
    expect((await LocalStorage.loadSettings()).fullName, 'Entered Name');
    expect(tester.takeException(), isNull);
  });
  testWidgets('later failed settings save retains the earlier durable value', (
    tester,
  ) async {
    await tester.pumpWidget(const BriskaApp());
    await tester.pumpAndSettle();
    final ui = await screen(tester);
    final writes = ControlledSettings();
    LocalStorage.saveSettingsOverride = writes.save;
    final first = save(ui, 'durable');
    final second = save(ui, 'failed');
    await tester.pump();
    writes.completions.first.complete();
    expect(await first, isTrue);
    await tester.pump();
    writes.completions.last.completeError(StateError('disk'));
    expect(await second, isFalse);
    await tester.pump();
    expect(
      tester
          .widget<SettingsScreen>(find.byType(SettingsScreen))
          .preferences
          .fullName,
      'durable',
    );
    expect((await LocalStorage.loadSettings()).fullName, 'durable');
  });
}
