import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _settings({required bool available}) => MaterialApp(
  home: SettingsScreen(
    preferences: const AppSettings(onboardingCompleted: true),
    lockConfig: const AppLockConfig(enabled: true, hasPin: true),
    onCreateBackup: () async {},
    onRestoreBackup: () async {},
    onLockConfigChanged: (_) async {},
    onSetLockPin: (_, currentPin) async {},
    onDisableLock: (_) async {},
    onShowAbout: () {},
    onPreferencesChanged: (_) async {},
    onThemeModeChanged: (_) async {},
    deviceAuthenticationAvailabilityChecker: () async => available,
  ),
);

Widget _lock({
  required bool available,
  Future<bool> Function()? authenticate,
}) => MaterialApp(
  home: AppLockScreen(
    config: const AppLockConfig(
      enabled: true,
      useBiometrics: true,
      hasPin: true,
    ),
    onUnlocked: () {},
    authenticateWithBiometrics: authenticate ?? () async => false,
    deviceAuthenticationAvailabilityChecker: () async => available,
  ),
);

void main() {
  testWidgets('Settings describes device authentication and Briska Pay PIN', (
    tester,
  ) async {
    await tester.pumpWidget(_settings(available: true));
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey('device-authentication-setting'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(tile, findsOneWidget);
    expect(
      find.text(
        'Unlock Briska Pay using your fingerprint, face, or device screen '
        'lock. This is separate from your Briska Pay PIN.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Use device biometrics'), findsNothing);
  });

  testWidgets(
    'unavailable device authentication is disabled with PIN fallback',
    (tester) async {
      await tester.pumpWidget(_settings(available: false));
      await tester.pumpAndSettle();

      final tileFinder = find.byKey(
        const ValueKey('device-authentication-setting'),
      );
      await tester.ensureVisible(tileFinder);
      await tester.pumpAndSettle();
      final tile = tester.widget<SwitchListTile>(tileFinder);
      expect(tile.onChanged, isNull);
      expect(
        find.textContaining('Your Briska Pay PIN remains available.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('lock screen names both authentication paths clearly', (
    tester,
  ) async {
    await tester.pumpWidget(_lock(available: true));
    await tester.pumpAndSettle();

    expect(find.text('Use device authentication'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Briska Pay PIN'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('unavailable device authentication hides action and keeps PIN', (
    tester,
  ) async {
    await tester.pumpWidget(_lock(available: false));
    await tester.pumpAndSettle();

    expect(find.text('Use device authentication'), findsNothing);
    expect(
      find.text(
        'Device authentication is unavailable. Use your Briska Pay PIN.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Briska Pay PIN'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('failure and thrown platform details use safe wording', (
    tester,
  ) async {
    await tester.pumpWidget(
      _lock(
        available: true,
        authenticate: () async => throw Exception('RAW_LOCAL_AUTH_EXCEPTION'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Device authentication was not completed. '
        'Use your Briska Pay PIN or try again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('RAW_LOCAL_AUTH_EXCEPTION'), findsNothing);
  });

  testWidgets(
    'device-auth lock layout survives narrow, landscape and text scale',
    (tester) async {
      for (final testCase in <({Size size, double scale})>[
        (size: const Size(320, 568), scale: 1.5),
        (size: const Size(568, 320), scale: 1.5),
        (size: const Size(320, 568), scale: 2),
        (size: const Size(568, 320), scale: 2),
      ]) {
        tester.view.physicalSize = testCase.size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = testCase.scale;
        await tester.pumpWidget(_lock(available: true));
        await tester.pumpAndSettle();
        expect(find.text('Use device authentication'), findsOneWidget);
        expect(find.text('Unlock'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    },
  );
}
