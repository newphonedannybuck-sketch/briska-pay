import 'dart:async';

import 'package:briska/src/briska_app.dart';
import 'package:briska/src/models.dart';
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

  Finder timeField(int index) => find
      .byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.keyboardType == TextInputType.datetime,
      )
      .at(index);
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
    await tester.enterText(siteField(), 'New site');
    await tester.pump();
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
