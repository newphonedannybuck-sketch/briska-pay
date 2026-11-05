import 'package:briska/src/briska_app.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/work_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkEntry savedEntry(String type, {double hours = 8}) => WorkEntry(
  id: 'saved',
  entryType: type,
  date: DateTime(2026, 7, 14),
  siteName: '',
  startTime: '',
  finishTime: '',
  breakMinutes: 0,
  hourlyRateUsed: 17,
  dailyAllowance: 0,
  jobUplift: 5,
  totalHours: hours,
  wages: hours * 17,
  totalPay: hours * 17 + 5,
  notes: 'Original',
);

void main() {
  final hoursField = find.byKey(const ValueKey('holiday-hours-field'));
  Future<void> open(
    WidgetTester tester, {
    WorkEntry? initial,
    List<WorkEntry> entries = const [],
    Future<bool> Function(WorkEntry)? save,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddWorkDayScreen(
          preferences: const AppSettings(primaryRateValue: 25),
          savedEntries: entries,
          initialEntry: initial,
          initialDate: DateTime(2026, 7, 14),
          onSave: save ?? (_) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String type) async {
    final chip = find.byKey(ValueKey('day-type-$type'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    tester
        .widget<BriskaPrimaryButton>(find.byType(BriskaPrimaryButton))
        .onPressed!();
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester) =>
      tester.widget<TextField>(hoursField).controller!.text;

  for (final type in ['Holiday', 'bankHoliday', 'BankHoliday']) {
    test('$type validates hours and retains saved hours on recalculation', () {
      for (final hours in [
        null,
        0.0,
        7.5,
        8.0,
        -1.0,
        double.nan,
        double.infinity,
      ]) {
        for (final paid in [true, false]) {
          final result = WorkCalculator.calculate(
            startTime: '',
            finishTime: '',
            breakMinutes: 0,
            hourlyRate: 17,
            dailyAllowance: 30,
            jobUplift: 5,
            entryType: type,
            holidayHours: hours,
            isPaidBankHoliday: paid,
          );
          final valid = hours == null || (hours.isFinite && hours >= 0);
          expect(result.isValid, valid);
          if (valid) {
            expect(result.totalHours, hours ?? 0);
            expect(
              result.wages,
              type == 'Holiday' || paid ? (hours ?? 0) * 17 : 0,
            );
            expect(result.totalPay, result.wages + 5);
          }
        }
      }
      final entry = savedEntry(type, hours: 7.5);
      final recalculated = WorkCalculator.recalculateEntry(entry);
      expect(recalculated.totalHours, 7.5);
      expect(recalculated.hourlyRateUsed, 17);
      expect(recalculated.totalPay, 132.5);
      expect(recalculated.entryType, entry.entryType);
    });
    testWidgets('$type edit preserves eight hours and historical rate', (
      tester,
    ) async {
      WorkEntry? result;
      await open(
        tester,
        initial: savedEntry(type),
        save: (entry) async {
          result = entry;
          return false;
        },
      );
      expect(text(tester), '8.0');
      final notes = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Anything useful to remember...',
      );
      await tester.ensureVisible(notes);
      await tester.enterText(notes, 'Updated notes');
      await submit(tester);
      expect(result!.totalHours, 8);
      expect(result!.hourlyRateUsed, 17);
      expect(result!.totalPay, 141);
      expect(result!.notes, 'Updated notes');
      expect(result!.entryType, savedEntry(type).entryType);
    });
  }
  for (final type in ['holiday', 'bankHoliday']) {
    testWidgets('$type starts blank, saves zero and previews decimal hours', (
      tester,
    ) async {
      WorkEntry? result;
      await open(
        tester,
        save: (entry) async {
          result = entry;
          return false;
        },
      );
      await select(tester, type);
      expect(text(tester), '');
      expect(find.text('Start time'), findsNothing);
      await submit(tester);
      expect(result!.totalHours, 0);
      expect(result!.wages, 0);
      await tester.ensureVisible(hoursField);
      await tester.enterText(hoursField, '7.5');
      await tester.pumpAndSettle();
      expect(find.textContaining('187.50'), findsWidgets);
      await submit(tester);
      expect(result!.totalHours, 7.5);
      expect(result!.wages, 187.5);
      if (type == 'bankHoliday') {
        await tester.ensureVisible(find.text('Unpaid'));
        await tester.tap(find.text('Unpaid'));
        await tester.pumpAndSettle();
        await submit(tester);
        expect(result!.totalHours, 7.5);
        expect(result!.wages, 0);
      }
    });
  }
  testWidgets('invalid hours are visible and cannot save', (tester) async {
    var saves = 0;
    await open(
      tester,
      save: (_) async {
        saves++;
        return false;
      },
    );
    await select(tester, 'holiday');
    for (final value in ['abc', '-1', 'NaN', 'Infinity', '1.2.3']) {
      await tester.ensureVisible(hoursField);
      await tester.enterText(hoursField, value);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(hoursField).decoration!.errorText,
        isNotNull,
      );
      await submit(tester);
    }
    expect(saves, 0);
  });
  testWidgets(
    'switching types clears irrelevant hours and preserves work times',
    (tester) async {
      await open(tester);
      await select(tester, 'holiday');
      await tester.ensureVisible(hoursField);
      await tester.enterText(hoursField, '7.5');
      await select(tester, 'bankHoliday');
      expect(text(tester), '');
      await select(tester, 'workDay');
      expect(hoursField, findsNothing);
      expect(find.text('Start time'), findsOneWidget);
      await select(tester, 'holiday');
      expect(text(tester), '');
    },
  );
  testWidgets(
    'duplicate Edit existing replaces displayed hours and saved rate',
    (tester) async {
      WorkEntry? result;
      await open(
        tester,
        entries: [savedEntry('BankHoliday')],
        save: (entry) async {
          result = entry;
          return false;
        },
      );
      await select(tester, 'holiday');
      await tester.ensureVisible(hoursField);
      await tester.enterText(hoursField, '4');
      await submit(tester);
      await tester.tap(find.text('Edit existing'));
      await tester.pumpAndSettle();
      expect(text(tester), '8.0');
      await submit(tester);
      expect(result!.id, 'saved');
      expect(result!.totalHours, 8);
      expect(result!.hourlyRateUsed, 17);
      expect(result!.wages, 136);
    },
  );
}
