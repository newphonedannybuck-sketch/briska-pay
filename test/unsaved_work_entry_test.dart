import 'dart:async';

import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/local_storage.dart';
import 'package:briska/src/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const preferences = AppSettings(
  onboardingCompleted: true,
  primaryRateValue: 20,
  secondaryRateValue: 25,
  defaultStartTime: '08:00',
  defaultFinishTime: '16:00',
  defaultBreakMinutes: 30,
);
final date = DateTime(2026, 7, 14);
WorkEntry existing([String type = 'WorkDay']) => WorkEntry(
  id: 'existing',
  date: date,
  entryType: type,
  siteName: 'Existing private site',
  startTime: '08:00',
  finishTime: '16:00',
  breakMinutes: 30,
  hourlyRateUsed: 20,
  dailyAllowance: 0,
  jobUplift: 0,
  totalHours: 7.5,
  wages: 150,
  totalPay: 150,
  notes: 'Existing notes',
);
Finder site() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'Where did you work?',
);
Finder time(int index) => find
    .byWidgetPredicate(
      (w) => w is TextField && w.keyboardType == TextInputType.datetime,
    )
    .at(index);
Finder field(String hint) => find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      (w.decoration?.hintText == hint || w.decoration?.labelText == hint),
);
Finder under(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);
Future<void> enter(WidgetTester tester, Finder field, String value) async {
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> open(
  WidgetTester tester, {
  WorkEntry? entry,
  List<WorkEntry> entries = const [],
  Future<bool> Function(WorkEntry)? save,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AddWorkDayScreen(
                  preferences: preferences,
                  savedEntries: entries,
                  initialDate: date,
                  initialEntry: entry,
                  onSave: save ?? (_) async => false,
                ),
              ),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

Future<void> back(WidgetTester tester, {bool system = true}) async {
  if (system) {
    await tester.binding.handlePopRoute();
  } else {
    await tester.tap(find.byTooltip('Back'), warnIfMissed: false);
  }
  await tester.pumpAndSettle();
}

void expectEditor() => expect(find.byType(AddWorkDayScreen), findsOneWidget);
void expectPrompt() =>
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
void expectClosed() {
  expect(find.byType(AddWorkDayScreen), findsNothing);
  expect(find.text('Discard unsaved changes?'), findsNothing);
  expect(find.text('Open editor'), findsOneWidget);
}

void main() {
  for (final edit in [false, true]) {
    testWidgets(
      'untouched ${edit ? 'existing' : 'new'} form closes immediately',
      (tester) async {
        await open(tester, entry: edit ? existing() : null);
        expect(
          ModalRoute.of(
            tester.element(find.byType(AddWorkDayScreen)),
          )!.popDisposition,
          RoutePopDisposition.pop,
        );
        await back(tester);
        expectClosed();
      },
    );
  }
  for (final system in [true, false]) {
    testWidgets(
      'site edits warn on ${system ? 'Android' : 'AppBar'} Back; Keep Editing preserves form',
      (tester) async {
        await open(tester);
        await enter(tester, site(), 'Unfinished private site');
        expect(
          ModalRoute.of(
            tester.element(find.byType(AddWorkDayScreen)),
          )!.popDisposition,
          RoutePopDisposition.doNotPop,
        );
        await back(tester, system: system);
        expectPrompt();
        await tester.tap(find.text('Keep Editing'));
        await tester.pumpAndSettle();
        expectEditor();
        expect(find.text('Unfinished private site'), findsOneWidget);
      },
    );
  }
  final changes = <String, Future<void> Function(WidgetTester)>{
    'start time': (t) => enter(t, time(0), '09:00'),
    'finish time': (t) => enter(t, time(1), '17:00'),
    'break': (t) => enter(t, field('Enter minutes'), '45'),
    'rate': (t) => enter(t, under('rate-primary'), '24'),
    'allowance': (t) => enter(t, under('allowance-null-primary'), '25'),
    'explicit zero allowance': (t) =>
        enter(t, under('allowance-null-primary'), '0'),
    'uplift': (t) => enter(t, under('job-uplift-field'), '5'),
    'deduction': (t) => enter(t, under('deduction-amount-field'), '10'),
    'deduction reason': (t) => enter(t, field('Deduction reason'), 'Advance'),
    'notes': (t) =>
        enter(t, field('Anything useful to remember...'), 'Private notes'),
  };
  for (final change in changes.entries) {
    testWidgets('${change.key} changes warn before leaving', (tester) async {
      await open(tester);
      await change.value(tester);
      await back(tester);
      expectPrompt();
    });
  }
  testWidgets('date changes are protected', (tester) async {
    await open(tester);
    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await back(tester);
    expectPrompt();
  });
  testWidgets('rate selection is protected', (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('Overtime'));
    await tester.tap(find.text('Overtime'));
    await tester.pumpAndSettle();
    await back(tester);
    expectPrompt();
  });
  for (final type in ['Holiday', 'bankHoliday']) {
    testWidgets('$type loaded values are clean; edited hours warn', (
      tester,
    ) async {
      await open(tester, entry: existing(type));
      expect(
        ModalRoute.of(
          tester.element(find.byType(AddWorkDayScreen)),
        )!.popDisposition,
        RoutePopDisposition.pop,
      );
      await enter(
        tester,
        find.byKey(const ValueKey('holiday-hours-field')),
        '6',
      );
      await back(tester);
      expectPrompt();
    });
  }
  for (final type in ['SickDay', 'bankHoliday']) {
    testWidgets('$type paid status changes warn', (tester) async {
      await open(tester, entry: existing(type));
      final button = find.widgetWithText(
        SegmentedButton<bool>,
        type == 'SickDay' ? 'Paid at Primary Rate' : 'Unpaid',
      );
      await tester.ensureVisible(button);
      tester.widget<SegmentedButton<bool>>(button).onSelectionChanged!({
        type == 'SickDay',
      });
      await tester.pump();
      await back(tester);
      expectPrompt();
    });
  }
  testWidgets('reverting text, numeric and time values clears dirty state', (
    tester,
  ) async {
    await open(tester);
    await enter(tester, site(), 'temporary');
    await enter(tester, site(), '');
    await enter(tester, time(0), '09:00');
    await enter(tester, time(0), '0800');
    await enter(tester, under('allowance-null-primary'), '0');
    await enter(tester, under('allowance-null-primary'), '');
    await enter(tester, field('Anything useful to remember...'), 'temporary');
    await enter(tester, field('Anything useful to remember...'), '');
    await back(tester);
    expectClosed();
  });
  testWidgets(
    'type round trip detects field resets instead of forgetting prior changes',
    (tester) async {
      await open(tester, entry: existing('Holiday'));
      await tester.tap(find.byKey(const ValueKey('day-type-workDay')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('day-type-holiday')));
      await tester.pumpAndSettle();
      await back(tester);
      expectPrompt(); // Loaded holiday hours were cleared by the type change.
    },
  );
  testWidgets('validation and focus alone do not mark a new form dirty', (
    tester,
  ) async {
    await open(tester);
    await tester.ensureVisible(site());
    await tester.tap(site());
    await tester.tap(find.text('Save Entry'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a site/job name'), findsOneWidget);
    await back(tester);
    expectClosed();
  });
  testWidgets('Discard Changes closes without saving', (tester) async {
    var saves = 0;
    await open(
      tester,
      save: (_) async {
        saves++;
        return true;
      },
    );
    await enter(tester, site(), 'Private site');
    await back(tester);
    await tester.tap(find.text('Discard Changes'));
    await tester.pumpAndSettle();
    expectClosed();
    expect(saves, 0);
  });
  testWidgets('repeated blocked Back callbacks cannot stack dialogs', (
    tester,
  ) async {
    await open(tester);
    await enter(tester, site(), 'Private site');
    final scope = tester.widget<PopScope<void>>(find.byType(PopScope<void>));
    scope.onPopInvokedWithResult!(false, null);
    scope.onPopInvokedWithResult!(false, null);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expectEditor();
    expect(find.byType(AlertDialog), findsNothing);
  });
  for (final fail in [false, true]) {
    testWidgets(
      'active save blocks navigation; ${fail ? 'failure preserves and retries' : 'success closes cleanly'}',
      (tester) async {
        final pending = Completer<bool>();
        var saves = 0;
        await open(
          tester,
          save: (_) {
            saves++;
            return saves == 1 ? pending.future : Future.value(true);
          },
        );
        await enter(tester, site(), 'Unfinished private site');
        final save = tester
            .widget<BriskaPrimaryButton>(find.byType(BriskaPrimaryButton))
            .onPressed!;
        save();
        save();
        await tester.pump();
        await back(tester);
        await back(tester, system: false);
        expectEditor();
        expect(find.byType(AlertDialog), findsNothing);
        expect(saves, 1);
        pending.complete(!fail);
        await tester.pumpAndSettle();
        if (fail) {
          expectEditor();
          expect(find.text('Unfinished private site'), findsOneWidget);
          await back(tester);
          expectPrompt();
          await tester.tap(find.text('Keep Editing'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save Entry'));
          await tester.pumpAndSettle();
          expect(saves, 2);
        }
        expectClosed();
      },
    );
  }
  testWidgets('thrown save error preserves fields and re-enables navigation', (
    tester,
  ) async {
    final pending = Completer<bool>();
    await open(tester, save: (_) => pending.future);
    await enter(tester, site(), 'Unfinished private site');
    await tester.tap(find.text('Save Entry'));
    await tester.pump();
    pending.completeError(StateError('save failed'));
    await tester.pumpAndSettle();
    expect(find.text('Unfinished private site'), findsOneWidget);
    expect(find.text('Could not save this day.'), findsOneWidget);
    await back(tester);
    expectPrompt();
  });
  testWidgets(
    'loading a duplicate existing entry establishes a new clean baseline',
    (tester) async {
      await open(tester, entries: [existing()]);
      await enter(tester, site(), 'New unsaved site');
      await tester.tap(find.text('Save Entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit existing'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(site()).controller!.text,
        'Existing private site',
      );
      await back(tester);
      expectClosed();
    },
  );

  for (final mode in ['modified', 'dialog', 'saving', 'biometric']) {
    testWidgets(
      'App Lock immediately removes editor and stale callbacks: $mode',
      (tester) async {
        final pending = Completer<void>();
        LocalStorage.saveEntriesOverride = (_) => pending.future;
        addTearDown(() => LocalStorage.saveEntriesOverride = null);
        var authentications = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: BriskaShell(
              useLocalStorage: false,
              initialSettings: preferences,
              appLockConfigLoader: () async => AppLockConfig(
                enabled: true,
                hasPin: true,
                useBiometrics: mode == 'biometric',
                lockAfterSeconds: 0,
              ),
              pinVerifier: (_) async => true,
              biometricAuthenticator: () async => ++authentications == 1,
              deviceAuthenticationAvailabilityChecker: () async => true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (mode != 'biometric') {
          await tester.enterText(find.byType(TextField), '1234');
          await tester.tap(find.text('Unlock'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('Add Day'));
        await tester.pumpAndSettle();
        await enter(tester, site(), 'Sensitive unfinished site');
        VoidCallback? staleDiscard;
        if (mode == 'dialog') {
          await back(tester);
          expectPrompt();
          staleDiscard = tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Discard Changes'),
              )
              .onPressed;
        }
        if (mode == 'saving') {
          await tester.tap(find.text('Save Entry'));
          await tester.pump();
        }
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        staleDiscard?.call();
        await tester.pump();
        expect(find.byType(AppLockScreen), findsOneWidget);
        expect(
          find.byType(AddWorkDayScreen, skipOffstage: false),
          findsNothing,
        );
        expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
        expect(
          find.text('Sensitive unfinished site', skipOffstage: false),
          findsNothing,
        );
        pending.complete();
        await tester.pumpAndSettle();
        expect(find.byType(AppLockScreen), findsOneWidget);
        expect(find.text('Day saved.'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
