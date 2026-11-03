import 'dart:async';

import 'package:briska/main.dart';
import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/premium_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sensitiveSettings = AppSettings(
  onboardingCompleted: true,
  fullName: 'Private Person',
  companyName: 'Secret Employer',
  homeHourlyRate: 42,
);

final _sensitiveEntry = WorkEntry(
  id: 'private-entry',
  date: DateTime(2026, 7, 24),
  siteName: 'Secret Site',
  startTime: '08:00',
  finishTime: '16:00',
  breakMinutes: 30,
  workLocation: 'Home',
  hourlyRateUsed: 42,
  dailyAllowance: 0,
  jobUplift: 0,
  totalHours: 7.5,
  wages: 315,
  totalPay: 315,
  notes: 'Private notes',
);

void main() {
  testWidgets('startup gate hides all sensitive shell content while loading', (
    tester,
  ) async {
    final lockConfig = Completer<AppLockConfig>();
    var loadCount = 0;

    await tester.pumpWidget(
      BriskaApp(
        initialSettings: _sensitiveSettings,
        initialEntries: [_sensitiveEntry],
        appLockConfigLoader: () {
          loadCount++;
          return lockConfig.future;
        },
      ),
    );
    await tester.pump();

    expect(find.byType(StartupInitializationScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(EntriesScreen), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Private Person'), findsNothing);
    expect(find.text('Secret Employer'), findsNothing);
    expect(find.text('Secret Site'), findsNothing);
    expect(loadCount, 1);
  });

  testWidgets('enabled app lock routes directly to the lock screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      BriskaApp(
        initialSettings: _sensitiveSettings,
        initialEntries: [_sensitiveEntry],
        appLockConfigLoader: () async =>
            const AppLockConfig(enabled: true, hasPin: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppLockScreen), findsOneWidget);
    expect(find.text('Unlock Briska Pay'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Secret Site'), findsNothing);
  });

  testWidgets('disabled app lock opens the main shell after loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      BriskaApp(
        initialSettings: _sensitiveSettings,
        initialEntries: [_sensitiveEntry],
        appLockConfigLoader: () async => const AppLockConfig(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StartupInitializationScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('onboarding waits for security initialization', (tester) async {
    final lockConfig = Completer<AppLockConfig>();
    await tester.pumpWidget(
      BriskaApp(
        initialSettings: const AppSettings(),
        appLockConfigLoader: () => lockConfig.future,
      ),
    );
    await tester.pump();

    expect(find.byType(StartupInitializationScreen), findsOneWidget);
    expect(find.text('Welcome to Briska Pay'), findsNothing);

    lockConfig.complete(const AppLockConfig());
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Briska Pay'), findsOneWidget);
  });

  testWidgets('secure-state loading failure remains fail closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      BriskaApp(
        initialSettings: _sensitiveSettings,
        initialEntries: [_sensitiveEntry],
        appLockConfigLoader: () async => throw StateError('secure failure'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppLockInitializationErrorScreen), findsOneWidget);
    expect(
      find.text('Briska Pay could not verify app security'),
      findsOneWidget,
    );
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('secure failure'), findsNothing);
    expect(find.text('Secret Site'), findsNothing);
  });

  testWidgets('successful PIN unlock opens the main shell', (tester) async {
    await tester.pumpWidget(
      BriskaApp(
        initialSettings: _sensitiveSettings,
        appLockConfigLoader: () async =>
            const AppLockConfig(enabled: true, hasPin: true),
        pinVerifier: (pin) async => pin == '4321',
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '4321');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.byType(AppLockScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('successful device authentication still unlocks', (tester) async {
    await tester.pumpWidget(
      BriskaApp(
        initialSettings: _sensitiveSettings,
        appLockConfigLoader: () async =>
            const AppLockConfig(enabled: true, useBiometrics: true),
        biometricAuthenticator: () async => true,
        deviceAuthenticationAvailabilityChecker: () async => true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppLockScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('lifecycle timeout still locks after returning to the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      BriskaApp(
        initialSettings: _sensitiveSettings,
        appLockConfigLoader: () async => const AppLockConfig(
          enabled: true,
          lockAfterSeconds: 0,
          hasPin: true,
        ),
        pinVerifier: (_) async => true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(AppLockScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('startup and lock surfaces remain responsive and overflow-free', (
    tester,
  ) async {
    final cases = <({Size size, double scale})>[
      (size: const Size(320, 568), scale: 1.5),
      (size: const Size(568, 320), scale: 1.5),
      (size: const Size(320, 568), scale: 2),
      (size: const Size(568, 320), scale: 2),
    ];

    for (final testCase in cases) {
      tester.view.physicalSize = testCase.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = testCase.scale;

      final pendingConfig = Completer<AppLockConfig>();
      await tester.pumpWidget(
        BriskaApp(appLockConfigLoader: () => pendingConfig.future),
      );
      await tester.pump();
      expect(find.byType(StartupInitializationScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        BriskaApp(
          key: UniqueKey(),
          appLockConfigLoader: () async =>
              const AppLockConfig(enabled: true, hasPin: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}
