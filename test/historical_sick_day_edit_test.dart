import 'package:briska/src/briska_app.dart';
import 'package:briska/src/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editing historical paid sick-day notes preserves original pay', (
    tester,
  ) async {
    const settings = AppSettings(
      onboardingCompleted: true,
      primaryRateValue: 25,
      secondaryRateValue: 30,
    );

    final original = WorkEntry(
      id: 'historical-sick-day',
      date: DateTime(2026, 7, 14),
      entryType: 'SickDay',
      isPaidSickDay: true,
      siteName: '',
      startTime: '',
      finishTime: '',
      breakMinutes: 0,
      hourlyRateUsed: 20,
      dailyAllowance: 0,
      jobUplift: 0,
      totalHours: 8,
      wages: 160,
      totalPay: 160,
      notes: 'Original notes',
    );

    WorkEntry? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AddWorkDayScreen(
                    preferences: settings,
                    savedEntries: [original],
                    initialEntry: original,
                    onSave: (entry) async {
                      saved = entry;
                      return true;
                    },
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

    final notesField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.controller?.text == 'Original notes',
    );

    expect(notesField, findsOneWidget);

    await tester.ensureVisible(notesField);
    await tester.enterText(notesField, 'Updated notes');
    await tester.pump();

    await tester.ensureVisible(find.text('Update Entry'));
    await tester.tap(find.text('Update Entry'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.id, original.id);
    expect(saved!.notes, 'Updated notes');
    expect(saved!.hourlyRateUsed, 20);
    expect(saved!.totalHours, 8);
    expect(saved!.wages, 160);
    expect(saved!.totalPay, 160);
  });
}
