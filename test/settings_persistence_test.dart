import 'dart:async';
import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/pay_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _settings({
  AppSettings preferences = const AppSettings(
    onboardingCompleted: true,
    fullName: 'Saved Name',
    companyName: 'Saved Company',
    homeHourlyRate: 20,
    payFrequency: lastFridayPayFrequency,
  ),
  AppLockConfig lockConfig = const AppLockConfig(),
  Future<void> Function(AppSettings)? savePreferences,
  Future<void> Function(AppLockConfig)? saveLock,
  Future<void> Function(String)? savePin,
  Future<void> Function(ThemeMode)? saveTheme,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SettingsScreen(
        preferences: preferences,
        lockConfig: lockConfig,
        onCreateBackup: () async {},
        onRestoreBackup: () async {},
        onLockConfigChanged: saveLock ?? (_) async {},
        onSetLockPin: savePin ?? (_) async {},
        onShowAbout: () {},
        onPreferencesChanged: savePreferences ?? (_) async {},
        onThemeModeChanged: saveTheme ?? (_) async {},
      ),
    ),
  );
}

void main() {
  testWidgets(
    'personal details wait for persistence and roll back on failure',
    (tester) async {
      await tester.pumpWidget(
        _settings(
          savePreferences: (_) async => throw Exception('RAW_STORAGE_FAILURE'),
        ),
      );

      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Unsaved Company',
      );
      await tester.pump();
      expect(find.text('Personal details updated.'), findsNothing);
      expect(find.text('Could not save personal details.'), findsNothing);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Personal details updated.'), findsNothing);
      expect(find.text('Could not save personal details.'), findsOneWidget);
      expect(find.text('RAW_STORAGE_FAILURE'), findsNothing);
      expect(find.text('Saved Company'), findsOneWidget);
    },
  );

  testWidgets('pay rate success waits and failure restores saved value', (
    tester,
  ) async {
    var shouldFail = false;
    AppSettings? saved;
    await tester.pumpWidget(
      _settings(
        savePreferences: (value) async {
          if (shouldFail) throw Exception('rate write failed');
          saved = value;
        },
      ),
    );

    final primaryRateField = find.byKey(const ValueKey('homeRate-0'));
    await tester.enterText(primaryRateField, '21.50');
    await tester.pump();
    expect(saved, isNull);
    expect(find.text('Pay rates updated.'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(saved?.primaryRateValue, 21.5);
    expect(find.text('Pay rates updated.'), findsOneWidget);

    shouldFail = true;
    await tester.enterText(primaryRateField, '99.00');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(find.text('Could not save pay rates.'), findsOneWidget);
    expect(find.text('99.00'), findsNothing);
  });

  testWidgets('currency and pay schedule failures roll back without success', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settings(savePreferences: (_) async => throw Exception('write failed')),
    );

    await tester.tap(find.textContaining('British Pound').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Euro').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change currency'));
    await tester.pumpAndSettle();
    expect(find.text('Currency updated.'), findsNothing);
    expect(find.text('Could not update currency.'), findsOneWidget);
    expect(find.textContaining('British Pound'), findsOneWidget);

    await tester.ensureVisible(find.text('Pay period type'));
    await tester.tap(find.text(lastFridayPayFrequency).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(calendarMonthlyPayFrequency).last);
    await tester.pumpAndSettle();
    expect(find.text('Pay schedule updated.'), findsNothing);
    expect(find.text('Could not update pay schedule.'), findsOneWidget);
    expect(find.text(lastFridayPayFrequency), findsOneWidget);
  });

  testWidgets('security and silent-setting failures use safe feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settings(
        lockConfig: const AppLockConfig(enabled: true, hasPin: true),
        saveLock: (_) async => throw Exception('SECURE_PATH_DETAIL'),
        savePin: (_) async => throw Exception('PIN_SECRET_DETAIL'),
        saveTheme: (_) async => throw Exception('THEME_PLATFORM_DETAIL'),
      ),
    );

    final lockTile = find.widgetWithText(SwitchListTile, 'App lock');
    await tester.ensureVisible(lockTile);
    await tester.tap(
      find.descendant(of: lockTile, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();
    expect(find.text('App lock disabled.'), findsNothing);
    expect(find.text('Could not update app lock.'), findsOneWidget);
    expect(find.text('SECURE_PATH_DETAIL'), findsNothing);

    await tester.ensureVisible(find.text('Set PIN fallback'));
    await tester.tap(find.text('Set PIN fallback'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'PIN'), '4321');
    await tester.tap(find.text('Save PIN'));
    await tester.pumpAndSettle();
    expect(find.text('PIN updated.'), findsNothing);
    expect(find.text('Could not update PIN.'), findsOneWidget);
    expect(find.text('PIN_SECRET_DETAIL'), findsNothing);

    await tester.ensureVisible(find.text('Theme'));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(find.text('Could not update theme.'), findsOneWidget);
    expect(find.text('THEME_PLATFORM_DETAIL'), findsNothing);
  });
  testWidgets('rapid schedule selections retain both changes before saving', (
    tester,
  ) async {
    final values = <AppSettings>[];
    final completions = <Completer<void>>[];
    await tester.pumpWidget(
      _settings(
        savePreferences: (value) {
          values.add(value);
          final completion = Completer<void>();
          completions.add(completion);
          return completion.future;
        },
      ),
    );
    await tester.ensureVisible(find.text('Pay period type'));
    await tester.tap(find.text(lastFridayPayFrequency).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(calendarMonthlyPayFrequency).last);
    await tester.pumpAndSettle();
    expect(values, hasLength(1));
    await tester.ensureVisible(find.text('Payday rule'));
    await tester.tap(find.text(paydayOnPeriodEnd).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(paydayFixedDayFollowingMonth).last);
    await tester.pumpAndSettle();
    expect(values, hasLength(2));
    expect(values.last.payFrequency, calendarMonthlyPayFrequency);
    expect(values.last.paydayRule, paydayFixedDayFollowingMonth);
    completions.first.complete();
    await tester.pump();
    expect(find.text('Pay schedule updated.'), findsNothing);
    completions.last.complete();
    await tester.pumpAndSettle();
    expect(find.text('Pay schedule updated.'), findsOneWidget);
  });

  testWidgets('save completion preserves text edited while write is pending', (
    tester,
  ) async {
    final completion = Completer<void>();
    final values = <AppSettings>[];
    await tester.pumpWidget(
      _settings(
        savePreferences: (value) {
          values.add(value);
          return values.length == 1 ? completion.future : Future<void>.value();
        },
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'First');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(1), 'Newer');
    completion.complete();
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(values.last.companyName, 'Newer');
  });
}
