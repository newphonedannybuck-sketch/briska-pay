import 'dart:async';
import 'dart:io';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;
  late ExportedFileRecord record;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('briska-export-actions-');
    file = File('${directory.path}/report.pdf')..writeAsStringSync('original');
    record = ExportedFileRecord(
      id: 'record',
      fileName: 'report.pdf',
      fileType: 'PDF',
      filePath: file.path,
      exportedAt: DateTime(2026, 7, 1),
      periodLabel: 'July',
      workDays: 1,
      totalHours: 8,
      totalPay: 100,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    directory.deleteSync(recursive: true);
  });
  Future<void> open(
    WidgetTester tester, {
    Future<bool> Function(ExportedFileRecord)? update,
    Future<bool> Function(ExportedFileRecord)? delete,
    ExportActionOverrides? actions,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExportScreen(
          entries: const [],
          fullName: '',
          companyName: '',
          settings: const AppSettings(),
          records: [record],
          libraryOnly: true,
          onPreferencesChanged: (_) {},
          onAdd: (_) async => true,
          onUpdate: update ?? (_) async => true,
          onDelete: delete ?? (_) async => true,
          actionOverrides: actions,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 1000 && !ready(); i++) {
        await Future<void>(() {});
        await tester.pump();
      }
    });
    expect(ready(), isTrue);
    await tester.pump();
  }

  Future<void> deleteChoice(
    WidgetTester tester, {
    bool physical = false,
  }) async {
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(
        physical
            ? 'Delete file and remove from library'
            : 'Remove from library',
      ),
    );
    await tester.pumpAndSettle();
    if (physical) {
      await tester.tap(find.text('Delete file'));
      await tester.pump();
    }
  }

  Future<void> rename(WidgetTester tester) async {
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'renamed');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Rename'),
      ),
    );
    await tester.pump();
  }

  for (final success in [true, false]) {
    testWidgets('library removal awaits storage success=$success', (
      tester,
    ) async {
      final completion = Completer<bool>();
      await open(tester, delete: (_) => completion.future);
      await deleteChoice(tester);
      expect(find.text('Export removed from library.'), findsNothing);
      completion.complete(success);
      await tester.pumpAndSettle();
      expect(
        find.text(
          success
              ? 'Export removed from library.'
              : 'Could not remove this export from the library. Please try again.',
        ),
        findsOneWidget,
      );
      expect(file.existsSync(), isTrue);
    });
    testWidgets(
      'physical deletion reports persistence success=$success accurately',
      (tester) async {
        var called = false;
        await open(
          tester,
          delete: (_) async {
            called = true;
            return success;
          },
        );
        await deleteChoice(tester, physical: true);
        await until(tester, () => called);
        expect(file.existsSync(), isFalse);
        expect(
          find.text(
            success
                ? 'Export deleted.'
                : 'The file was deleted, but its library record could not be removed. Try Remove from library again.',
          ),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets('physical delete failure preserves metadata', (tester) async {
    var deleted = false;
    await open(
      tester,
      delete: (_) async {
        deleted = true;
        return true;
      },
      actions: ExportActionOverrides(
        deleteFile: (_) async => throw const FileSystemException('blocked'),
      ),
    );
    await deleteChoice(tester, physical: true);
    await tester.pumpAndSettle();
    expect(deleted, isFalse);
    expect(file.existsSync(), isTrue);
    expect(find.text('Could not delete this export.'), findsOneWidget);
  });
  testWidgets(
    'favourite waits and reports thrown storage errors without optimistic UI',
    (tester) async {
      final completion = Completer<bool>();
      var calls = 0;
      await open(
        tester,
        update: (_) {
          calls++;
          return completion.future;
        },
      );
      await tester.tap(find.text('Favourite'));
      await tester.tap(find.text('Favourite'));
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Favourited'), findsNothing);
      completion.completeError(StateError('storage'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save favourite status. Please try again.'),
        findsOneWidget,
      );
    },
  );
  for (final collision in [false, true]) {
    testWidgets(
      'rename persistence failure rolls back safely collision=$collision',
      (tester) async {
        await open(
          tester,
          update: (_) async {
            if (collision) file.writeAsStringSync('other file');
            return false;
          },
        );
        await rename(tester);
        await until(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
        expect(file.readAsStringSync(), collision ? 'other file' : 'original');
        expect(File('${directory.path}/renamed.pdf').existsSync(), collision);
        expect(
          find.textContaining(
            collision
                ? 'original name could not be restored'
                : 'original filename has been kept',
          ),
          findsOneWidget,
        );
        expect(find.text('Export renamed.'), findsNothing);
      },
    );
  }
  testWidgets('rename collision never overwrites another file', (tester) async {
    final target = File('${directory.path}/renamed.pdf')
      ..writeAsStringSync('other');
    var updated = false;
    await open(
      tester,
      update: (_) async {
        updated = true;
        return true;
      },
    );
    await rename(tester);
    await until(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
    expect(updated, isFalse);
    expect(target.readAsStringSync(), 'other');
    expect(file.readAsStringSync(), 'original');
  });
  for (final success in [true, false]) {
    testWidgets('provider path persistence gates opening success=$success', (
      tester,
    ) async {
      final legacy = Directory('${directory.path}/app_flutter/exports')
        ..createSync(recursive: true);
      file = File('${legacy.path}/report.pdf')..writeAsStringSync('original');
      record = record.copyWith(filePath: file.path);
      final completion = Completer<bool>();
      ExportedFileRecord? changed;
      ExportedFileRecord? opened;
      await open(
        tester,
        update: (value) {
          changed = value;
          return completion.future;
        },
        actions: ExportActionOverrides(
          open: (value) async {
            opened = value;
            return true;
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await until(tester, () => changed != null);
      expect(opened, isNull);
      expect(File(changed!.filePath).readAsStringSync(), 'original');
      completion.complete(success);
      await tester.pumpAndSettle();
      expect(opened?.filePath, success ? changed!.filePath : null);
      expect(file.existsSync(), isTrue);
      if (!success) {
        expect(
          find.textContaining('Could not save the updated export path'),
          findsOneWidget,
        );
      }
    });
  }
  for (final success in [true, false]) {
    testWidgets(
      'created file is retained while library addition awaits success=$success',
      (tester) async {
        final completion = Completer<bool>();
        ExportedFileRecord? created;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExportScreen(
                entries: [
                  WorkEntry(
                    id: 'work',
                    date: DateTime.now(),
                    siteName: 'Site',
                    startTime: '08:00',
                    finishTime: '16:00',
                    breakMinutes: 0,
                    hourlyRateUsed: 20,
                    dailyAllowance: 0,
                    jobUplift: 0,
                    totalHours: 8,
                    wages: 160,
                    totalPay: 160,
                    notes: '',
                  ),
                ],
                fullName: 'Test Person',
                companyName: '',
                settings: const AppSettings(),
                records: const [],
                onPreferencesChanged: (_) {},
                onAdd: (value) {
                  created = value;
                  return completion.future;
                },
                onUpdate: (_) async => true,
                onDelete: (_) async => true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('More options'));
        await tester.tap(find.text('More options'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('CSV (.csv)'));
        await tester.tap(find.text('CSV (.csv)'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Export report'));
        await tester.tap(find.text('Export report'));
        await until(tester, () => created != null);
        expect(find.text('Export created'), findsNothing);
        expect(File(created!.filePath).existsSync(), isTrue);
        completion.complete(success);
        await until(
          tester,
          () =>
              find.byType(AlertDialog).evaluate().isNotEmpty ||
              find.byType(SnackBar).evaluate().isNotEmpty,
        );
        await tester.pump();
        expect(File(created!.filePath).existsSync(), isTrue);
        if (success) {
          expect(find.text('Export created'), findsOneWidget);
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
        } else {
          expect(
            find.textContaining('but could not be added to the Export Library'),
            findsOneWidget,
          );
          expect(find.text('Could not generate the report.'), findsNothing);
        }
      },
    );
  }
}
