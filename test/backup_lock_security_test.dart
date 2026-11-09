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
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'retained_navigation_safety_test.dart' as fixtures;

Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
  // Real file I/O must get time to finish even under full-suite CPU load.
  // Yield to the event loop without adding a fixed delay to the test.
  final elapsed = Stopwatch()..start();
  await tester.runAsync(() async {
    while (!ready() && elapsed.elapsed < const Duration(seconds: 10)) {
      await Future<void>(() {});
      await tester.pump();
    }
  });
  expect(ready(), isTrue);
  await tester.pumpAndSettle();
}

// Forward-looking security contracts. Stale completions intentionally fail on
// 0d4cb64; valid-session and existing route-dismissal controls must pass.
void main() {
  const picker = MethodChannel('plugins.flutter.io/file_selector');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const sharing = MethodChannel('dev.fluttercommunity.plus/share');
  late Directory directory;
  late File input;
  late String inputContents;
  late Completer<String> pathGate;
  late Completer<List<String>> pickerGate;
  late Completer<bool> biometricGate;
  late DateTime now;
  late List<MethodCall> shareCalls;
  late int pathCalls;
  late int pickerCalls;
  late int biometricCalls;
  late List<WorkEntry> originalEntries;
  final original = fixtures.preferences.copyWith(
    fullName: 'Original Private Person',
  );
  final restored = fixtures.preferences.copyWith(
    fullName: 'Backup Private Person',
    companyName: 'Backup Private Employer',
  );

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    directory = Directory.systemTemp.createTempSync('briska_backup_lock_');
    originalEntries = [fixtures.entry('original', DateTime(2026, 7, 14))];
    await LocalStorage.saveSettings(original);
    await LocalStorage.saveEntries(originalEntries);
    await LocalStorage.saveExportRecords([]);
    inputContents = jsonEncode(
      BriskaBackupData(
        createdAt: DateTime(2026, 7, 15),
        settings: restored,
        workEntries: [fixtures.entry('restored', DateTime(2026, 7, 15))],
        exportRecords: [],
      ).toJson(),
    );
    input = File('${directory.path}/input.json')
      ..writeAsStringSync(inputContents);
    pathGate = Completer<String>();
    pickerGate = Completer<List<String>>();
    now = DateTime.utc(2026, 11, 7, 12);
    shareCalls = [];
    pathCalls = 0;
    pickerCalls = 0;
    biometricCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (_) {
      pathCalls++;
      return pathGate.future;
    });
    messenger.setMockMethodCallHandler(picker, (_) {
      pickerCalls++;
      return pickerGate.future;
    });
    messenger.setMockMethodCallHandler(sharing, (call) async {
      shareCalls.add(call);
      return 'test-recipient';
    });
  });
  tearDown(() {
    LocalStorage.restoreWriteHook = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [paths, picker, sharing]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    directory.deleteSync(recursive: true);
  });

  Future<void> unlock(WidgetTester tester, {bool biometric = false}) async {
    expect(find.byType(AppLockScreen), findsOneWidget);
    if (biometric) {
      await tester.pump();
      expect(biometricCalls, greaterThan(0));
      // Native prompt inactivity alone must not invalidate the current attempt.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      biometricGate.complete(true);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    } else {
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
    }
    await tester.pumpAndSettle();
    expect(find.byType(AppLockScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  }

  Future<SettingsScreen> open(
    WidgetTester tester, {
    bool biometric = false,
  }) async {
    biometricGate = Completer<bool>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: BriskaShell(
          useLocalStorage: false,
          initialSettings: original,
          initialEntries: originalEntries,
          lockClock: () => now,
          appLockConfigLoader: () async => AppLockConfig(
            enabled: true,
            hasPin: true,
            useBiometrics: biometric,
            lockAfterSeconds: 60,
          ),
          pinVerifier: (pin) async => pin == '1234',
          biometricAuthenticator: () {
            biometricCalls++;
            return biometricGate.future;
          },
          deviceAuthenticationAvailabilityChecker: () async => biometric,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await unlock(tester, biometric: biometric);
    await fixtures.tab(tester, 'Entries');
    await fixtures.tab(tester, 'Settings');
    return tester.widget<SettingsScreen>(find.byType(SettingsScreen));
  }

  Future<void> background(
    WidgetTester tester,
    int seconds, {
    bool biometric = false,
  }) async {
    if (biometric) biometricGate = Completer<bool>();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    now = now.add(Duration(seconds: seconds));
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    if (seconds >= 60) {
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(SettingsScreen, skipOffstage: false), findsNothing);
      expect(find.byType(EntriesScreen, skipOffstage: false), findsNothing);
    } else {
      expect(find.byType(AppLockScreen), findsNothing);
    }
  }

  Future<void> unchanged() async {
    expect((await LocalStorage.loadSettings()).toJson(), original.toJson());
    expect(
      (await LocalStorage.loadEntries()).map((e) => e.toJson()).toList(),
      originalEntries.map((e) => e.toJson()).toList(),
    );
    expect(await LocalStorage.loadExportRecords(), isEmpty);
    expect(input.readAsStringSync(), inputContents);
  }

  for (final timing in [
    'before timeout',
    'locked',
    'PIN reauthentication',
    'device reauthentication',
  ]) {
    final stale = timing != 'before timeout';
    final biometric = timing == 'device reauthentication';
    final reauthenticate = timing.contains('reauthentication');
    testWidgets('backup completion: $timing', (tester) async {
      final settings = await open(tester, biometric: biometric);
      Object? operationError;
      var done = false;
      final operation = settings
          .onCreateBackup()
          .catchError((Object error) {
            operationError = error;
          })
          .whenComplete(() => done = true);
      await tester.pump();
      expect(pathCalls, 1);
      expect(shareCalls, isEmpty);
      expect(done, isFalse);
      await background(tester, stale ? 60 : 59, biometric: biometric);
      if (reauthenticate) await unlock(tester, biometric: biometric);
      pathGate.complete(directory.path);
      await pumpUntil(tester, () => done);
      await operation;
      await unchanged();
      final backups = Directory('${directory.path}/backups');
      // A security fix may cancel before writing. Any completed file must still
      // contain the original snapshot, never corrupt or replace existing data.
      if (backups.existsSync()) {
        for (final file in backups.listSync().whereType<File>()) {
          final data = jsonDecode(file.readAsStringSync()) as Map;
          expect(data['settings'], original.toJson());
          expect(
            data['workEntries'],
            originalEntries.map((e) => e.toJson()).toList(),
          );
        }
      }
      if (biometric) expect(biometricCalls, 2);
      expect(
        operationError,
        isNull,
        reason: 'Backup/restore must complete safely.',
      );
      expect(
        {
          'share requests': shareCalls.length,
          'backup feedback visible': find
              .textContaining('Backup saved:')
              .evaluate()
              .isNotEmpty,
        },
        {'share requests': stale ? 0 : 1, 'backup feedback visible': !stale},
      );
    });

    testWidgets('restore picker completion: $timing', (tester) async {
      final settings = await open(tester, biometric: biometric);
      pathGate.complete(directory.path);
      Object? operationError;
      var done = false;
      final operation = settings
          .onRestoreBackup()
          .catchError((Object error) {
            operationError = error;
          })
          .whenComplete(() => done = true);
      await tester.pump();
      expect(pickerCalls, 1);
      expect(done, isFalse);
      await background(tester, stale ? 60 : 59, biometric: biometric);
      if (reauthenticate) await unlock(tester, biometric: biometric);
      pickerGate.complete([input.path]);
      await pumpUntil(
        tester,
        () =>
            done ||
            find.text('Restore Briska Pay backup?').evaluate().isNotEmpty,
      );
      final previewVisible = find
          .text('Restore Briska Pay backup?')
          .evaluate()
          .isNotEmpty;
      final sensitiveVisible = find
          .text('Backup Private Employer')
          .evaluate()
          .isNotEmpty;
      if (previewVisible) {
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(stale ? 'Cancel' : 'Restore'),
          ),
        );
      }
      await pumpUntil(tester, () => done);
      await operation;
      expect(
        operationError,
        isNull,
        reason: 'Backup/restore must complete safely.',
      );
      if (stale) {
        await unchanged();
      } else {
        expect((await LocalStorage.loadSettings()).fullName, restored.fullName);
        expect((await LocalStorage.loadEntries()).single.id, 'restored');
      }
      if (biometric) expect(biometricCalls, 2);
      expect(
        {'preview': previewVisible, 'sensitive details': sensitiveVisible},
        {'preview': !stale, 'sensitive details': !stale},
      );
    });
  }

  testWidgets('stale restore confirmation cannot apply data while locked', (
    tester,
  ) async {
    final settings = await open(tester);
    pathGate.complete(directory.path);
    Object? operationError;
    var done = false;
    final operation = settings
        .onRestoreBackup()
        .catchError((Object error) {
          operationError = error;
        })
        .whenComplete(() => done = true);
    await tester.pump();
    expect(pickerCalls, 1);
    await background(tester, 60);
    pickerGate.complete([input.path]);
    await pumpUntil(
      tester,
      () =>
          done || find.text('Restore Briska Pay backup?').evaluate().isNotEmpty,
    );
    // Deliberately exercise the stale confirmation if production exposes it;
    // the final assertion checks durable data, independently of UI visibility.
    if (find.text('Restore Briska Pay backup?').evaluate().isNotEmpty) {
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Restore'),
        ),
      );
    }
    await pumpUntil(tester, () => done);
    await operation;
    expect(find.byType(AppLockScreen), findsOneWidget);
    await unchanged();
    expect(operationError, isNull);
  });

  testWidgets(
    'lock dismisses an already visible restore confirmation without applying data',
    (tester) async {
      final settings = await open(tester);
      pathGate.complete(directory.path);
      pickerGate.complete([input.path]);
      Object? operationError;
      var done = false;
      final operation = settings
          .onRestoreBackup()
          .catchError((Object error) {
            operationError = error;
          })
          .whenComplete(() => done = true);
      await pumpUntil(
        tester,
        () => find.text('Restore Briska Pay backup?').evaluate().isNotEmpty,
      );
      await background(tester, 60);
      await pumpUntil(tester, () => done);
      await operation;
      expect(
        operationError,
        isNull,
        reason: 'Backup/restore must complete safely.',
      );
      expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
      await unchanged();
    },
  );

  for (final stage in RestoreWriteStage.values) {
    testWidgets('lock during restore write $stage rolls back', (tester) async {
      final settings = await open(tester);
      final gate = Completer<void>();
      var reached = false;
      LocalStorage.restoreWriteHook = (current, rollback) async {
        if (!rollback && current == stage) {
          reached = true;
          await gate.future;
        }
      };
      pathGate.complete(directory.path);
      pickerGate.complete([input.path]);
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
      await pumpUntil(tester, () => reached);
      await background(tester, 60);
      gate.complete();
      await pumpUntil(tester, () => done);
      await operation;
      await unchanged();
      expect(find.byType(SnackBar), findsNothing);
      await unlock(tester);
      expect(find.text('Briska Pay backup restored.'), findsNothing);
    });
  }

  testWidgets('lock while restore safety backup is pending cancels restore', (
    tester,
  ) async {
    final settings = await open(tester);
    pickerGate.complete([input.path]);
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
    await pumpUntil(tester, () => pathCalls == 1);
    await background(tester, 60);
    pathGate.complete(directory.path);
    await pumpUntil(tester, () => done);
    await operation;
    await unchanged();
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final restore in [false, true]) {
    testWidgets('stale ${restore ? 'restore' : 'backup'} errors are silent', (
      tester,
    ) async {
      pathGate = Completer<String>();
      pickerGate = Completer<List<String>>();
      final settings = await open(tester);
      var done = false;
      final operation =
          (restore ? settings.onRestoreBackup() : settings.onCreateBackup())
              .whenComplete(() => done = true);
      await tester.pump();
      await background(tester, 60);
      if (restore) {
        pickerGate.completeError(PlatformException(code: 'picker_failed'));
      } else {
        pathGate.completeError(PlatformException(code: 'path_failed'));
      }
      await pumpUntil(tester, () => done);
      await operation;
      await unchanged();
      expect(find.byType(SnackBar), findsNothing);
      await unlock(tester);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  for (final restore in [false, true]) {
    testWidgets(
      'new ${restore ? 'restore' : 'backup'} after PIN reauthentication remains functional',
      (tester) async {
        await open(tester);
        await background(tester, 60);
        await unlock(tester);
        await fixtures.tab(tester, 'Settings');
        final settings = tester.widget<SettingsScreen>(
          find.byType(SettingsScreen),
        );
        pathGate.complete(directory.path);
        pickerGate.complete([input.path]);
        Object? operationError;
        var done = false;
        final operation =
            (restore ? settings.onRestoreBackup() : settings.onCreateBackup())
                .catchError((Object error) {
                  operationError = error;
                })
                .whenComplete(() => done = true);
        if (restore) {
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
        }
        await pumpUntil(tester, () => done);
        await operation;
        expect(
          operationError,
          isNull,
          reason: 'Backup/restore must complete safely.',
        );
        if (restore) {
          expect(
            (await LocalStorage.loadSettings()).fullName,
            restored.fullName,
          );
        } else {
          expect(shareCalls, hasLength(1));
          await unchanged();
        }
      },
    );
  }

  testWidgets('restore picker returns before app resumes', (tester) async {
    final settings = await open(tester);

    final operation = settings.onRestoreBackup();
    await tester.pump();
    expect(pickerCalls, 1);

    // Android may deliver the selected file while Flutter is inactive.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    pickerGate.complete([input.path]);
    await tester.pump();

    // The app resumes without an App Lock timeout.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await pumpUntil(
      tester,
      () => find.text('Restore Briska Pay backup?').evaluate().isNotEmpty,
    );

    expect(find.text('Restore Briska Pay backup?'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ),
    );

    await tester.pumpAndSettle();
    await operation;
    await unchanged();
  });
}
