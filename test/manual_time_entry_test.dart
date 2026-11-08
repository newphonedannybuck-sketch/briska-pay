import 'dart:async';

import 'package:briska/src/briska_app.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/local_storage.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final date = DateTime(2026, 7, 14);
  final existing = WorkEntry(
    id: 'existing',
    date: date,
    siteName: 'Existing site',
    startTime: '22:00',
    finishTime: '06:00',
    breakMinutes: 30,
    hourlyRateUsed: 20,
    dailyAllowance: 0,
    jobUplift: 0,
    totalHours: 7.5,
    wages: 150,
    totalPay: 150,
    notes: '',
  );

  Finder timeField(int index) => find.descendant(
    of: find.ancestor(
      of: find.text(index == 0 ? 'Start time' : 'Finish time'),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Column &&
            w.children.any(
              (child) =>
                  child is TextField &&
                  child.keyboardType == TextInputType.datetime,
            ),
      ),
    ),
    matching: find.byType(TextField),
  );
  Finder breakField() => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == 'Enter minutes',
  );
  Finder siteField() => find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Where did you work?',
  );
  TextEditingController controller(WidgetTester tester, int index) =>
      tester.widget<TextField>(timeField(index)).controller!;
  BriskaPrimaryButton saveButton(WidgetTester tester) =>
      tester.widget<BriskaPrimaryButton>(find.byType(BriskaPrimaryButton));

  Future<void> openForm(
    WidgetTester tester, {
    List<WorkEntry> entries = const [],
    WorkEntry? initialEntry,
    Future<bool> Function(WorkEntry)? onSave,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AddWorkDayScreen(
                      preferences: const AppSettings(
                        primaryRateValue: 20,
                        defaultBreakMinutes: 30,
                      ),
                      savedEntries: entries,
                      initialDate: date,
                      initialEntry: initialEntry,
                      onSave: onSave ?? (_) async => false,
                    ),
                  ),
                ),
                child: const Text('Open form'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    if (initialEntry == null) await tester.enterText(siteField(), 'New site');
    await tester.pump();
  }

  for (final input in ['1230', '2130']) {
    testWidgets('finish typing $input preserves cursor and selection', (
      tester,
    ) async {
      await openForm(tester);
      await tester.showKeyboard(timeField(1));
      for (var length = 0; length <= input.length; length++) {
        final value = input.substring(0, length);
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: length),
          ),
        );
        await tester.pump();
        expect(controller(tester, 1).text, value);
        expect(controller(tester, 1).selection.baseOffset, length);
      }
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: input,
          selection: const TextSelection(baseOffset: 0, extentOffset: 2),
        ),
      );
      await tester.pump();
      expect(
        controller(tester, 1).selection,
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '2230',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      expect(controller(tester, 1).text, '2230');
      expect(controller(tester, 1).selection.baseOffset, 2);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(controller(tester, 1).text, '22:30');
    });
  }

  for (final input in ['30.5', 'bad', '-1', '480', '481']) {
    testWidgets(
      'break $input rejects save with the correct reason and permits correction',
      (tester) async {
        WorkEntry? saved;
        await openForm(
          tester,
          onSave: (entry) async {
            saved = entry;
            return false;
          },
        );
        await tester.enterText(timeField(0), '08:00');
        await tester.enterText(timeField(1), '16:00');
        await tester.enterText(breakField(), input);
        saveButton(tester).onPressed!();
        await tester.pumpAndSettle();
        expect(saved, isNull);
        final message = ['30.5', 'bad'].contains(input)
            ? 'Enter break duration in whole minutes.'
            : input == '-1'
            ? 'Break minutes cannot be negative.'
            : 'Break must be shorter than the work period.';
        expect(find.text(message), findsWidgets);
        expect(tester.widget<TextField>(breakField()).controller!.text, input);
        await tester.enterText(breakField(), '30');
        saveButton(tester).onPressed!();
        await tester.pumpAndSettle();
        expect(saved!.breakMinutes, 30);
        expect(saved!.totalHours, 7.5);
        expect(saved!.wages, 150);
      },
    );
  }

  testWidgets(
    'manual overnight values survive storage reload and editor reopening',
    (tester) async {
      final previous = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
      await openForm(
        tester,
        onSave: (entry) async {
          await LocalStorage.saveEntries([entry]);
          return true;
        },
      );
      await tester.enterText(timeField(0), '2130');
      await tester.enterText(timeField(1), '530');
      saveButton(tester).onPressed!();
      await tester.pumpAndSettle();
      final loaded = (await LocalStorage.loadEntries()).single;
      expect(loaded.startTime, '21:30');
      expect(loaded.finishTime, '05:30');
      expect(loaded.totalHours, 7.5);
      expect(loaded.wages, 150);
      await openForm(tester, initialEntry: loaded);
      expect(controller(tester, 0).text, '21:30');
      expect(controller(tester, 1).text, '05:30');
      expect(tester.widget<TextField>(breakField()).controller!.text, '30');
    },
  );

  testWidgets('Work Day round trip retains both entered times', (tester) async {
    await openForm(tester);
    await tester.enterText(timeField(0), '2130');
    await tester.enterText(timeField(1), '0530');
    await tester.ensureVisible(find.byKey(const ValueKey('day-type-holiday')));
    await tester.tap(find.byKey(const ValueKey('day-type-holiday')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('day-type-workDay')));
    await tester.pumpAndSettle();
    expect(controller(tester, 0).text, '21:30');
    expect(controller(tester, 1).text, '05:30');
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'finish picker cancel=$cancel preserves correct submitted time',
      (tester) async {
        WorkEntry? saved;
        await openForm(
          tester,
          onSave: (entry) async {
            saved = entry;
            return false;
          },
        );
        await tester.enterText(timeField(1), '1730');
        final picker = find.descendant(
          of: find
              .ancestor(of: timeField(1), matching: find.byType(Column))
              .first,
          matching: find.byTooltip('Pick time'),
        );
        await tester.ensureVisible(picker);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.keyboard_outlined));
        await tester.pumpAndSettle();
        Finder pickerInput(String label) => find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == label,
          ),
          matching: find.byType(TextField),
        );
        final hour = pickerInput('Hour');
        final minute = pickerInput('Minute');
        await tester.enterText(hour, '18');
        await tester.enterText(minute, '45');
        await tester.tap(find.text(cancel ? 'Cancel' : 'OK'));
        await tester.pumpAndSettle();
        expect(controller(tester, 1).text, cancel ? '17:30' : '18:45');
        saveButton(tester).onPressed!();
        await tester.pumpAndSettle();
        expect(saved!.finishTime, cancel ? '17:30' : '18:45');
        expect(saved!.totalHours, cancel ? 9 : 10.25);
      },
    );
  }

  testWidgets(
    'typing each character preserves raw text and cursor through rebuilds',
    (tester) async {
      await openForm(tester);
      await tester.showKeyboard(timeField(0));
      for (final text in ['', '0', '07', '073', '0730']) {
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
        await tester.pump();
        expect(controller(tester, 0).text, text);
        expect(controller(tester, 0).selection.baseOffset, text.length);
      }
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '0830',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      expect(controller(tester, 0).text, '0830');
      expect(controller(tester, 0).selection.baseOffset, 2);
    },
  );

  testWidgets('supported times format on completion and focus loss', (
    tester,
  ) async {
    await openForm(tester);
    for (final value in {
      '730': '07:30',
      '0730': '07:30',
      '7:30': '07:30',
      '17.30': '17:30',
      '1730': '17:30',
    }.entries) {
      await tester.enterText(timeField(0), value.key);
      await tester.pump();
      expect(controller(tester, 0).text, value.key);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(controller(tester, 0).text, value.value);
    }
    await tester.enterText(timeField(0), '730');
    await tester.enterText(timeField(1), '1730');
    await tester.pump();
    expect(controller(tester, 0).text, '07:30');
    expect(controller(tester, 1).text, '1730');
    expect(find.text('£190.00'), findsWidgets);
  });

  testWidgets(
    'invalid and partial input survives completion and unrelated edits',
    (tester) async {
      await openForm(tester);
      for (final text in ['', '7', '07:', '25:00', 'bad']) {
        await tester.enterText(timeField(0), text);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(controller(tester, 0).text, text);
      }
      await tester.enterText(timeField(0), '07:');
      await tester.enterText(siteField(), 'Changed site');
      await tester.pump();
      expect(controller(tester, 0).text, '07:');
      expect(find.text('Enter time like 08:00, 17:30 or 0730'), findsWidgets);
    },
  );

  testWidgets('time picker updates displayed time and submitted value', (
    tester,
  ) async {
    WorkEntry? saved;
    await openForm(
      tester,
      onSave: (entry) async {
        saved = entry;
        return false;
      },
    );
    final picker = find.byTooltip('Pick time').first;
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final inputs = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(inputs.at(0), '07');
    await tester.enterText(inputs.at(1), '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(controller(tester, 0).text, '07:30');
    saveButton(tester).onPressed!();
    await tester.pumpAndSettle();
    expect(saved!.startTime, '07:30');
    expect(saved!.totalHours, 8.5);
  });

  testWidgets(
    'Edit existing synchronises both fields and reports update success',
    (tester) async {
      WorkEntry? saved;
      await openForm(
        tester,
        entries: [existing],
        onSave: (entry) async {
          saved = entry;
          return true;
        },
      );
      await tester.tap(find.text('Save Entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit existing'));
      await tester.pumpAndSettle();
      expect(controller(tester, 0).text, '22:00');
      expect(controller(tester, 1).text, '06:00');
      expect(find.text('Edit Day'), findsOneWidget);
      await tester.tap(find.text('Update Entry'));
      await tester.pumpAndSettle();
      expect(saved!.id, existing.id);
      expect(saved!.startTime, '22:00');
      expect(saved!.finishTime, '06:00');
      expect(saved!.totalHours, 7.5);
      expect(saved!.totalPay, 150);
      expect(find.text('Day updated.'), findsOneWidget);
      expect(find.byType(AddWorkDayScreen), findsNothing);
    },
  );

  testWidgets(
    'rapid Save taps submit once and remain disabled until completion',
    (tester) async {
      final completion = Completer<bool>();
      var calls = 0;
      await openForm(
        tester,
        onSave: (_) {
          calls++;
          return completion.future;
        },
      );
      await tester.tap(find.text('Save Entry'));
      await tester.tap(find.text('Save Entry'));
      await tester.tap(find.text('Save Entry'));
      await tester.pump();
      expect(calls, 1);
      expect(saveButton(tester).onPressed, isNull);
      completion.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Day saved.'), findsOneWidget);
      expect(find.byType(AddWorkDayScreen), findsNothing);
    },
  );

  testWidgets(
    'duplicate confirmation is guarded and cancellation permits retry',
    (tester) async {
      final completion = Completer<bool>();
      var calls = 0;
      await openForm(
        tester,
        entries: [existing],
        onSave: (_) {
          calls++;
          return completion.future;
        },
      );
      final submit = saveButton(tester).onPressed!;
      submit();
      submit();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(saveButton(tester).onPressed, isNull);
      expect(calls, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saveButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('Save Entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      submit();
      expect(calls, 1);
      expect(saveButton(tester).onPressed, isNull);
      completion.complete(false);
      await tester.pumpAndSettle();
      expect(saveButton(tester).onPressed, isNotNull);
    },
  );

  for (final throws in [false, true]) {
    testWidgets(
      'persistence ${throws ? 'exception' : 'failure'} permits retry',
      (tester) async {
        final completion = Completer<bool>();
        var calls = 0;
        await openForm(
          tester,
          onSave: (_) {
            calls++;
            return calls == 1 ? completion.future : Future.value(true);
          },
        );
        await tester.tap(find.text('Save Entry'));
        await tester.pump();
        if (throws) {
          completion.completeError(StateError('write failed'));
        } else {
          completion.complete(false);
        }
        await tester.pumpAndSettle();
        expect(saveButton(tester).onPressed, isNotNull);
        await tester.tap(find.text('Save Entry'));
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(find.byType(AddWorkDayScreen), findsNothing);
      },
    );
  }

  testWidgets(
    'validation failure allows correction and preserves 16-hour limit',
    (tester) async {
      var calls = 0;
      await openForm(
        tester,
        onSave: (_) async {
          calls++;
          return false;
        },
      );
      await tester.enterText(timeField(0), '07:');
      saveButton(tester).onPressed!();
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(saveButton(tester).onPressed, isNotNull);
      await tester.enterText(timeField(0), '00:00');
      await tester.enterText(timeField(1), '17:00');
      saveButton(tester).onPressed!();
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('A work period cannot exceed 16 hours.'), findsWidgets);
      await tester.enterText(timeField(1), '16:00');
      saveButton(tester).onPressed!();
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  testWidgets('pending save can finish after the form is disposed', (
    tester,
  ) async {
    final completion = Completer<bool>();
    await openForm(tester, onSave: (_) => completion.future);
    await tester.tap(find.text('Save Entry'));
    await tester.pump();
    Navigator.of(tester.element(find.byType(AddWorkDayScreen))).pop();
    await tester.pumpAndSettle();
    completion.complete(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
