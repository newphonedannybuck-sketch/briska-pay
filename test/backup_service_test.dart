import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:briska/src/backup_service.dart';
import 'package:briska/src/models.dart';

void main() {
  Map<String, dynamic> validBackup({
    List<Object?>? entries,
    List<Object?>? exports,
  }) => {
    'backupVersion': 1,
    'createdAt': '2026-07-14T10:30:00.000',
    'appName': 'Briska',
    'settings': const AppSettings().toJson(),
    'workEntries': entries ?? [],
    'exportRecords': exports ?? [],
  };

  Map<String, Object?> validEntry() => WorkEntry(
    id: 'entry-1',
    date: DateTime(2026, 7, 14),
    siteName: 'Site',
    startTime: '08:00',
    finishTime: '16:30',
    breakMinutes: 30,
    workLocation: 'Home',
    hourlyRateUsed: 20,
    dailyAllowance: 0,
    jobUplift: 0,
    totalHours: 8,
    wages: 160,
    totalPay: 160,
    notes: '',
  ).toJson();

  Map<String, Object?> validExport() => ExportedFileRecord(
    id: 'export-1',
    fileName: 'timesheet.xlsx',
    fileType: 'Excel',
    filePath: r'Z:\file-that-does-not-exist.xlsx',
    exportedAt: DateTime(2026, 7, 14),
    periodLabel: 'July',
    workDays: 1,
    totalHours: 8,
    totalPay: 160,
  ).toJson();

  Matcher isSafeBackupFailure() => throwsA(
    isA<BriskaBackupException>()
        .having(
          (error) => error.message,
          'message',
          contains('This backup could not be restored.'),
        )
        .having(
          (error) => error.message,
          'message',
          isNot(anyOf(contains('workEntries'), contains('hourlyRateUsed'))),
        ),
  );

  test('backup preview accepts valid versioned Briska data', () {
    final preview = BriskaBackupService.previewJson({
      'backupVersion': 1,
      'createdAt': '2026-07-14T10:30:00.000',
      'appName': 'Briska',
      'settings': const AppSettings(
        fullName: 'Daniel Beckett',
        companyName: 'Berkzerker',
        onboardingCompleted: true,
        paydaySelectedWeekday: DateTime.tuesday,
      ).toJson(),
      'workEntries': [
        WorkEntry(
          id: '1',
          date: DateTime(2026, 7, 14),
          siteName: 'Site',
          startTime: '08:00',
          finishTime: '16:30',
          breakMinutes: 30,
          workLocation: 'Home',
          hourlyRateUsed: 20,
          dailyAllowance: 0,
          jobUplift: 0,
          totalHours: 8,
          wages: 160,
          totalPay: 160,
          notes: '',
        ).toJson(),
      ],
      'exportRecords': [],
    });

    expect(preview.userName, 'Daniel Beckett');
    expect(preview.companyName, 'Berkzerker');
    expect(preview.entryCount, 1);
    expect(preview.exportCount, 0);
    expect(preview.data.settings.paydaySelectedWeekday, DateTime.tuesday);
  });

  test('backup preview rejects unsupported backup versions', () {
    expect(
      () => BriskaBackupService.previewJson({
        'backupVersion': 999,
        'createdAt': '2026-07-14T10:30:00.000',
        'appName': 'Briska',
        'settings': const AppSettings().toJson(),
        'workEntries': [],
        'exportRecords': [],
      }),
      throwsA(isA<BriskaBackupException>()),
    );
  });

  test('backup preview supports missing optional exports field', () {
    final preview = BriskaBackupService.previewJson({
      'backupVersion': 1,
      'createdAt': '2026-07-14T10:30:00.000',
      'appName': 'Briska',
      'settings': const AppSettings().toJson(),
      'workEntries': [],
    });

    expect(preview.exportCount, 0);
  });

  test('backup preview accepts legacy rebrand-era app name', () {
    final preview = BriskaBackupService.previewJson({
      'backupVersion': 1,
      'createdAt': '2026-07-14T10:30:00.000',
      'appName':
          'Wage'
          'Mate',
      'settings': const AppSettings(companyName: '').toJson(),
      'workEntries': [],
      'exportRecords': [],
    });

    expect(preview.entryCount, 0);
    expect(preview.companyName, '');
  });

  test('backup preview accepts unknown extra fields', () {
    final backup = validBackup(entries: [validEntry()]);
    backup['futureTopLevelField'] = {'ignored': true};
    (backup['settings']! as Map<String, Object?>)['futureSetting'] = 1;
    (backup['workEntries']! as List).single['futureEntryField'] = 'ignored';

    expect(BriskaBackupService.previewJson(backup).entryCount, 1);
  });

  test(
    'backup preview retains structurally valid unavailable export metadata',
    () {
      final preview = BriskaBackupService.previewJson(
        validBackup(exports: [validExport()]),
      );

      expect(preview.exportCount, 1);
      expect(preview.data.exportRecords.single.isAvailable, isFalse);
    },
  );

  test('legacy backup may use settings defaults for fields added later', () {
    final backup = validBackup();
    backup['appName'] =
        'Wage'
        'Mate';
    backup['settings'] = <String, dynamic>{
      'fullName': 'Legacy user',
      'homeHourlyRate': 10,
    };

    final preview = BriskaBackupService.previewJson(backup);

    expect(preview.userName, 'Legacy user');
    expect(preview.data.settings.defaultStartTime, '08:00');
  });

  group('backup preview rejects invalid top-level data', () {
    test('wrong top-level structure', () async {
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'briska_wrong_top_level.json',
      );
      await file.writeAsString('[]');

      await expectLater(
        BriskaBackupService.previewFile(file),
        isSafeBackupFailure(),
      );
    });

    test('missing required section', () {
      final backup = validBackup()..remove('workEntries');
      expect(
        () => BriskaBackupService.previewJson(backup),
        isSafeBackupFailure(),
      );
    });

    test('incorrectly typed optional exports section', () {
      final backup = validBackup()..['exportRecords'] = {};
      expect(
        () => BriskaBackupService.previewJson(backup),
        isSafeBackupFailure(),
      );
    });
  });

  group('backup preview strictly validates settings', () {
    test('rejects a missing current-format setting', () {
      final backup = validBackup();
      (backup['settings']! as Map<String, Object?>).remove('primaryRateValue');

      expect(
        () => BriskaBackupService.previewJson(backup),
        isSafeBackupFailure(),
      );
    });

    test('rejects malformed and impossible settings', () {
      final backup = validBackup();
      (backup['settings']! as Map<String, Object?>)['defaultBreakMinutes'] = -1;

      expect(
        () => BriskaBackupService.previewJson(backup),
        isSafeBackupFailure(),
      );
    });
  });

  group('backup preview strictly validates every work entry', () {
    test('rejects a non-map member without silently discarding it', () {
      expect(
        () => BriskaBackupService.previewJson(
          validBackup(entries: [validEntry(), 'damaged']),
        ),
        isSafeBackupFailure(),
      );
    });

    test('rejects one malformed entry among valid entries', () {
      final malformed = validEntry()..['hourlyRateUsed'] = -1;
      expect(
        () => BriskaBackupService.previewJson(
          validBackup(entries: [validEntry(), malformed]),
        ),
        isSafeBackupFailure(),
      );
    });

    for (final testCase in <String, void Function(Map<String, Object?>)>{
      'missing required field': (entry) => entry.remove('siteName'),
      'invalid day type': (entry) => entry['entryType'] = 'InvalidDay',
      'invalid date': (entry) => entry['date'] = '2026-02-30',
      'invalid start time': (entry) => entry['startTime'] = '25:00',
      'invalid finish time': (entry) => entry['finishTime'] = 'not-a-time',
      'invalid numeric value': (entry) => entry['totalPay'] = double.infinity,
      'numeric string': (entry) => entry['hourlyRateUsed'] = '20',
    }.entries) {
      test('rejects ${testCase.key}', () {
        final entry = validEntry();
        testCase.value(entry);
        expect(
          () => BriskaBackupService.previewJson(validBackup(entries: [entry])),
          isSafeBackupFailure(),
        );
      });
    }
  });

  group('backup preview strictly validates every export record', () {
    test('rejects malformed export metadata', () {
      final record = validExport()..['exportedAt'] = 'not-a-date';
      expect(
        () => BriskaBackupService.previewJson(validBackup(exports: [record])),
        isSafeBackupFailure(),
      );
    });

    test('rejects one malformed export among valid records', () {
      expect(
        () => BriskaBackupService.previewJson(
          validBackup(exports: [validExport(), 42]),
        ),
        isSafeBackupFailure(),
      );
    });
  });

  test('failed validation produces no partial in-memory restore model', () {
    final existingEntries = [validEntry()];
    final malformed = validEntry()..remove('date');

    expect(
      () => BriskaBackupService.previewJson(
        validBackup(entries: [validEntry(), malformed]),
      ),
      isSafeBackupFailure(),
    );
    expect(existingEntries, hasLength(1));
  });

  test('backup preview rejects invalid JSON files cleanly', () async {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}briska_bad_backup.json',
    );
    await file.writeAsString('{not valid json');

    await expectLater(
      BriskaBackupService.previewFile(file),
      isSafeBackupFailure(),
    );
  });
}
