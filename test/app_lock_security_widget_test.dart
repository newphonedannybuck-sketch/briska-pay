import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/premium_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'duplicate PIN and device requests cannot overlap; unlock fires once',
    (tester) async {
      final pending = Completer<bool>();
      final availability = Completer<bool>();
      var checks = 0;
      var biometrics = 0;
      var unlocks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AppLockScreen(
            config: const AppLockConfig(
              enabled: true,
              hasPin: true,
              useBiometrics: true,
            ),
            verifyPin: (_) {
              checks++;
              return pending.future;
            },
            authenticateWithBiometrics: () async {
              biometrics++;
              return true;
            },
            deviceAuthenticationAvailabilityChecker: () => availability.future,
            onUnlocked: () => unlocks++,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '1234');
      final submit = tester
          .widget<TextField>(find.byType(TextField))
          .onSubmitted!;
      submit('1234');
      submit('1234');
      await tester.pump();
      availability.complete(true);
      await tester.pump();
      expect(checks, 1);
      expect(biometrics, 0);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      pending.complete(true);
      await tester.pumpAndSettle();
      submit('1234');
      await tester.pump();
      expect(unlocks, 1);
      expect(checks, 1);
    },
  );
  testWidgets('PIN exceptions are safe and retry remains available', (
    tester,
  ) async {
    var checks = 0;
    var unlocks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppLockScreen(
          config: const AppLockConfig(enabled: true, hasPin: true),
          verifyPin: (_) async {
            if (++checks == 1) throw StateError('SECRET');
            return true;
          },
          onUnlocked: () => unlocks++,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not verify authentication. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('SECRET'), findsNothing);
    expect(unlocks, 0);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(unlocks, 1);
  });
  for (final biometric in [false, true]) {
    testWidgets(
      'stale result cannot unlock a newer mounted session: biometric=$biometric',
      (tester) async {
        final pending = Completer<bool>();
        var unlocks = 0;
        Widget lock(int session) => MaterialApp(
          home: AppLockScreen(
            sessionId: session,
            config: AppLockConfig(
              enabled: true,
              hasPin: true,
              useBiometrics: biometric,
            ),
            verifyPin: (_) => pending.future,
            authenticateWithBiometrics: () => pending.future,
            deviceAuthenticationAvailabilityChecker: () async => true,
            onUnlocked: () => unlocks++,
          ),
        );
        await tester.pumpWidget(lock(1));
        await tester.pumpAndSettle();
        if (!biometric) {
          await tester.enterText(find.byType(TextField), '1234');
          await tester.tap(find.text('Unlock'));
          await tester.pump();
        }
        await tester.pumpWidget(lock(2));
        pending.complete(true);
        await tester.pumpAndSettle();
        expect(unlocks, 0);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isTrue,
        );
      },
    );
  }
  testWidgets('cancelled device auth does not unlock; PIN cannot overlap it', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var pins = 0;
    var unlocks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppLockScreen(
          config: const AppLockConfig(
            enabled: true,
            hasPin: true,
            useBiometrics: true,
          ),
          verifyPin: (_) async {
            pins++;
            return true;
          },
          authenticateWithBiometrics: () => pending.future,
          deviceAuthenticationAvailabilityChecker: () async => true,
          onUnlocked: () => unlocks++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.widget<TextField>(find.byType(TextField)).onSubmitted!('1234');
    expect(pins, 0);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(unlocks, 0);
    expect(find.textContaining('was not completed'), findsOneWidget);
  });

  for (final delay in [0, 60, 300, 900]) {
    testWidgets('first background timestamp governs $delay second lock', (
      tester,
    ) async {
      var now = DateTime.utc(2026, 11, 5);
      await tester.pumpWidget(
        MaterialApp(
          home: BriskaShell(
            useLocalStorage: false,
            lockClock: () => now,
            appLockConfigLoader: () async => AppLockConfig(
              enabled: true,
              hasPin: true,
              lockAfterSeconds: delay,
            ),
            pinVerifier: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      if (delay > 0) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        now = now.add(Duration(seconds: delay - 1));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(find.byType(AppLockScreen), findsNothing);
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      now = now.add(Duration(seconds: delay));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      if (tester.binding.lifecycleState == AppLifecycleState.paused) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });
  }
  for (final realBackground in [false, true]) {
    testWidgets(
      'device prompt lifecycle does not loop: background=$realBackground',
      (tester) async {
        final pending = Completer<bool>();
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: BriskaShell(
              useLocalStorage: false,
              appLockConfigLoader: () async => const AppLockConfig(
                enabled: true,
                useBiometrics: true,
                hasPin: true,
                lockAfterSeconds: 0,
              ),
              biometricAuthenticator: () {
                calls++;
                return pending.future;
              },
              deviceAuthenticationAvailabilityChecker: () async => true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        if (realBackground) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        }
        await tester.pump();
        pending.complete(true);
        await tester.pump();
        expect(find.byType(HomeScreen), findsNothing);
        if (realBackground) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(
          find.byType(AppLockScreen),
          realBackground ? findsOneWidget : findsNothing,
        );
      },
    );
  }
  testWidgets(
    'shell rejects a captured unlock callback from an earlier session',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BriskaShell(
            useLocalStorage: false,
            appLockConfigLoader: () async => const AppLockConfig(
              enabled: true,
              hasPin: true,
              lockAfterSeconds: 0,
            ),
            pinVerifier: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final staleUnlock = tester
          .widget<AppLockScreen>(find.byType(AppLockScreen))
          .onUnlocked;
      staleUnlock();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add Day'));
      await tester.pumpAndSettle();
      expect(find.byType(AddWorkDayScreen), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      if (tester.binding.lifecycleState == AppLifecycleState.paused) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      staleUnlock();
      await tester.pump();
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(AddWorkDayScreen), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
    },
  );

  testWidgets(
    'creating the first PIN then enabling preserves the usable PIN state',
    (tester) async {
      final storage = <String, String>{};
      AppLockService.resetOperationsForTesting();
      AppLockService.readOverride = (key) async => storage[key];
      AppLockService.writeOverride = (key, value) async {
        storage[key] = value;
      };
      addTearDown(() {
        AppLockService.readOverride = null;
        AppLockService.writeOverride = null;
        AppLockService.resetOperationsForTesting();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: BriskaShell(
            useLocalStorage: false,
            appLockConfigLoader: AppLockService.loadConfig,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(SwitchListTile, 'App lock');
      await tester.ensureVisible(tile);
      await tester.tap(
        find.descendant(of: tile, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Current PIN'), findsNothing);
      await tester.enterText(find.widgetWithText(TextField, 'PIN'), '1234');
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm PIN'),
        '1234',
      );
      await tester.tap(find.text('Save PIN'));
      await tester.pumpAndSettle();
      final config = tester
          .widget<SettingsScreen>(find.byType(SettingsScreen))
          .lockConfig;
      expect(config.enabled, isTrue);
      expect(config.hasPin, isTrue);
      expect((await AppLockService.loadConfig()).enabled, isTrue);
      expect(await AppLockService.verifyPin('1234'), isTrue);
      await tester.pump();
      final settings = tester.widget<SettingsScreen>(
        find.byType(SettingsScreen),
      );
      await expectLater(
        settings.onLockConfigChanged(config.copyWith(enabled: false)),
        throwsA(isA<PinVerificationException>()),
      );
      expect((await AppLockService.loadConfig()).enabled, isTrue);
      AppLockService.writeOverride = (key, value) async {
        if (key == 'briska_lock_enabled') throw StateError('write failed');
        storage[key] = value;
      };
      await tester.ensureVisible(tile);
      await tester.tap(
        find.descendant(of: tile, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Current PIN'),
        '1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Disable App Lock'));
      await tester.pumpAndSettle();
      expect(find.text('Could not update app lock.'), findsOneWidget);
      expect(
        tester
            .widget<SettingsScreen>(find.byType(SettingsScreen))
            .lockConfig
            .enabled,
        isTrue,
      );
      expect((await AppLockService.loadConfig()).enabled, isTrue);
      AppLockService.writeOverride = (key, value) async {
        storage[key] = value;
      };
      await tester.tap(find.widgetWithText(FilledButton, 'Disable App Lock'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SettingsScreen>(find.byType(SettingsScreen))
            .lockConfig
            .enabled,
        isFalse,
      );
      expect((await AppLockService.loadConfig()).enabled, isFalse);
      expect(find.text('App lock disabled.'), findsOneWidget);
      await tester.pump();
    },
  );

  group('PIN management', () {
    late Map<String, String> storage;
    setUp(() {
      storage = {
        'briska_lock_enabled': 'true',
        'briska_lock_pin_salt': 'legacy-salt',
        'briska_lock_pin_hash': sha256
            .convert(utf8.encode('legacy-salt:1234'))
            .toString(),
      };
      AppLockService.readOverride = (key) async => storage[key];
      AppLockService.writeOverride = (key, value) async {
        storage[key] = value;
      };
      AppLockService.resetOperationsForTesting();
    });
    tearDown(() {
      AppLockService.readOverride = null;
      AppLockService.writeOverride = null;
      AppLockService.resetOperationsForTesting();
    });
    Future<void> settings(
      WidgetTester tester, {
      Future<void> Function(String, String?)? save,
    }) async {
      AppLockService.resetOperationsForTesting();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(
              preferences: const AppSettings(onboardingCompleted: true),
              lockConfig: const AppLockConfig(enabled: true, hasPin: true),
              onCreateBackup: () async {},
              onRestoreBackup: () async {},
              onLockConfigChanged: AppLockService.saveConfig,
              onDisableLock: (pin) => AppLockService.saveConfig(
                const AppLockConfig(enabled: false),
                currentPin: pin,
              ),
              onSetLockPin:
                  save ??
                  (pin, current) =>
                      AppLockService.setPin(pin, currentPin: current),
              onShowAbout: () {},
              onPreferencesChanged: (_) async {},
              onThemeModeChanged: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openPin(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Set PIN fallback'));
      await tester.tap(find.text('Set PIN fallback'));
      await tester.pumpAndSettle();
    }

    Future<void> enter(WidgetTester tester, String label, String value) =>
        tester.enterText(find.widgetWithText(TextField, label), value);
    testWidgets(
      'invalid, mismatched and incorrect current PIN never replace PIN; cancellation preserves it',
      (tester) async {
        await settings(tester);
        await openPin(tester);
        await enter(tester, 'Current PIN', '0000');
        await enter(tester, 'PIN', 'abcd');
        await enter(tester, 'Confirm PIN', 'abcd');
        await tester.tap(find.text('Save PIN'));
        await tester.pump();
        expect(find.text('Use 4-12 numerical digits.'), findsOneWidget);
        await enter(tester, 'PIN', '9876');
        await tester.tap(find.text('Save PIN'));
        await tester.pump();
        expect(find.text('PINs do not match.'), findsOneWidget);
        await enter(tester, 'Confirm PIN', '9876');
        await tester.tap(find.text('Save PIN'));
        await tester.pumpAndSettle();
        expect(find.text('Current PIN did not match.'), findsOneWidget);
        expect(await AppLockService.verifyPin('1234'), isTrue);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(await AppLockService.verifyPin('1234'), isTrue);
        expect(find.text('PIN updated.'), findsNothing);
      },
    );
    testWidgets(
      'verified replacement prevents duplicate submissions while writing',
      (tester) async {
        final pending = Completer<void>();
        var calls = 0;
        await settings(
          tester,
          save: (pin, current) async {
            calls++;
            await pending.future;
            await AppLockService.setPin(pin, currentPin: current);
          },
        );
        await openPin(tester);
        await enter(tester, 'Current PIN', '1234');
        await enter(tester, 'PIN', '9876');
        await enter(tester, 'Confirm PIN', '9876');
        final submit = tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save PIN'))
            .onPressed!;
        submit();
        submit();
        await tester.pump();
        expect(calls, 1);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
          isNull,
        );
        pending.complete();
        await tester.pumpAndSettle();
        expect(await AppLockService.verifyPin('9876'), isTrue);
        expect(find.text('PIN updated.'), findsOneWidget);
      },
    );
    testWidgets(
      'disable cancellation, wrong PIN and write failure preserve enabled state',
      (tester) async {
        await settings(tester);
        final tile = find.widgetWithText(SwitchListTile, 'App lock');
        await tester.ensureVisible(tile);
        await tester.tap(
          find.descendant(of: tile, matching: find.byType(Switch)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect((await AppLockService.loadConfig()).enabled, isTrue);
        await tester.tap(
          find.descendant(of: tile, matching: find.byType(Switch)),
        );
        await tester.pumpAndSettle();
        await enter(tester, 'Current PIN', '0000');
        await tester.tap(find.widgetWithText(FilledButton, 'Disable App Lock'));
        await tester.pumpAndSettle();
        expect(find.text('Current PIN did not match.'), findsOneWidget);
        expect((await AppLockService.loadConfig()).enabled, isTrue);
        AppLockService.writeOverride = (key, value) async {
          if (key == 'briska_lock_enabled') throw StateError('PRIVATE_DETAIL');
          storage[key] = value;
        };
        await enter(tester, 'Current PIN', '1234');
        await tester.tap(find.widgetWithText(FilledButton, 'Disable App Lock'));
        await tester.pumpAndSettle();
        expect(find.text('Could not update app lock.'), findsOneWidget);
        expect(find.textContaining('PRIVATE_DETAIL'), findsNothing);
        expect(find.text('App lock disabled.'), findsNothing);
        expect((await AppLockService.loadConfig()).enabled, isTrue);
        AppLockService.writeOverride = (key, value) async {
          storage[key] = value;
        };
        await tester.tap(find.widgetWithText(FilledButton, 'Disable App Lock'));
        await tester.pumpAndSettle();
        expect((await AppLockService.loadConfig()).enabled, isFalse);
        expect(find.text('App lock disabled.'), findsOneWidget);
      },
    );
  });
}
