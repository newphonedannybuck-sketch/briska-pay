import 'package:briska/src/briska_app.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/local_storage.dart';
import 'package:briska/src/backup_service.dart';
import 'package:briska/src/csv_export_service.dart';
import 'package:briska/src/excel_export_service.dart';
import 'package:briska/src/pdf_export_service.dart';
import 'package:excel/excel.dart'
    show Excel, DoubleCellValue, IntCellValue, DateCellValue;
import 'dart:convert';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
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

  for (final type in ['Holiday', 'bankHoliday']) {
    for (final input in ['', '0', '7.5', '24']) {
      testWidgets('$type saves $input as numeric hours and reopens correctly', (
        tester,
      ) async {
        final previous = SharedPreferencesAsyncPlatform.instance;
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
        await open(
          tester,
          initial: savedEntry(type, hours: 0),
          save: (entry) async {
            await LocalStorage.saveEntries([entry]);
            return false;
          },
        );
        expect(text(tester), isEmpty);
        await tester.enterText(hoursField, input);
        await submit(tester);
        final loaded = (await LocalStorage.loadEntries()).single;
        final expected = double.tryParse(input) ?? 0;
        expect(loaded.totalHours, expected);
        expect(loaded.toJson()['totalHours'], isA<num>());
        expect(loaded.wages, expected * 17);
        expect(loaded.totalPay, expected * 17 + 5);
        expect(loaded.startTime, isEmpty);
        expect(loaded.finishTime, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await open(tester, initial: loaded);
        expect(text(tester), expected == 0 ? '' : expected.toString());
        expect(
          PdfExportService.calculateTotals([loaded]).totalRecordedHours,
          expected,
        );
        final csv = utf8.decode(CsvExportService.buildCsv([loaded]));
        expect(double.parse(csv.split('\r\n')[1].split(',')[8]), expected);
        final backup = BriskaBackupData(
          createdAt: DateTime(2026, 7, 14),
          settings: const AppSettings(),
          workEntries: [loaded],
          exportRecords: [],
        );
        expect(
          BriskaBackupService.previewJson(
            backup.toJson(),
          ).data.workEntries.single.toJson(),
          loaded.toJson(),
        );
        final sheet = Excel.decodeBytes(
          ExcelExportService.buildWorkbook([loaded]),
        ).tables['Work Entries']!;
        final row = sheet.rows.singleWhere(
          (row) => row.isNotEmpty && row.first?.value is DateCellValue,
        );
        final hoursCell = row[8]!.value;
        expect(hoursCell, anyOf(isA<IntCellValue>(), isA<DoubleCellValue>()));
        expect(
          hoursCell is IntCellValue
              ? hoursCell.value
              : (hoursCell as DoubleCellValue).value,
          expected,
        );
      });
    }
    testWidgets(
      '$type rejects invalid hours then accepts correction without clamping',
      (tester) async {
        WorkEntry? saved;
        await open(
          tester,
          initial: savedEntry(type),
          save: (entry) async {
            saved = entry;
            return false;
          },
        );
        for (final input in ['24.01', '25', '-1', 'abc', 'NaN', 'Infinity']) {
          await tester.ensureVisible(hoursField);
          await tester.enterText(hoursField, input);
          await submit(tester);
          expect(saved, isNull);
          expect(text(tester), input);
          expect(
            tester.widget<TextField>(hoursField).decoration!.errorText,
            'Enter valid hours from 0 to 24.',
          );
        }
        await tester.enterText(hoursField, '23.75');
        await submit(tester);
        expect(saved!.totalHours, 23.75);
        expect(
          tester.widget<TextField>(hoursField).decoration!.errorText,
          isNull,
        );
      },
    );
    testWidgets(
      '$type historical over-limit hours and earnings reload unchanged',
      (tester) async {
        final previous = SharedPreferencesAsyncPlatform.instance;
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
        final original = savedEntry(type, hours: 25);
        await LocalStorage.saveEntries([original]);
        final loaded = (await LocalStorage.loadEntries()).single;
        expect(loaded.toJson(), original.toJson());
        var saves = 0;
        await open(
          tester,
          initial: loaded,
          save: (_) async {
            saves++;
            return false;
          },
        );
        expect(text(tester), '25.0');
        await submit(tester);
        expect(saves, 0);
        expect(
          (await LocalStorage.loadEntries()).single.toJson(),
          original.toJson(),
        );
      },
    );
  }
  testWidgets('blank hours survive holiday switches and paid status toggles', (
    tester,
  ) async {
    await open(tester);
    await select(tester, 'holiday');
    await select(tester, 'bankHoliday');
    expect(text(tester), isEmpty);
    await tester.ensureVisible(find.text('Unpaid'));
    await tester.tap(find.text('Unpaid'));
    await tester.pumpAndSettle();
    expect(text(tester), isEmpty);
    await select(tester, 'holiday');
    expect(text(tester), isEmpty);
    await select(tester, 'bankHoliday');
    await tester.ensureVisible(hoursField);
    await tester.enterText(hoursField, '7.5');
    for (final label in ['Unpaid', 'Paid']) {
      await tester.ensureVisible(find.text(label).first);
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(text(tester), '7.5');
    }
  });

  for (final type in ['Holiday', 'bankHoliday', 'BankHoliday']) {
    test('$type validates hours and retains saved hours on recalculation', () {
      for (final hours in [
        null,
        0.0,
        7.5,
        8.0,
        24.0,
        24.01,
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
          final valid =
              hours == null || (hours.isFinite && hours >= 0 && hours <= 24);
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
      expect(text(tester), '7.5');
      await select(tester, 'holiday');
      expect(text(tester), '7.5');
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
