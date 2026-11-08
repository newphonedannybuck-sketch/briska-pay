import 'dart:convert';

import 'package:briska/src/local_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// Pure codec tests: no binding, storage backend or user-data access.
void main() {
  Map<String, Object?> valid() => {
    'journalVersion': 1,
    'original': <String, Object?>{
      'settings': '  {"name":"Private fixture £"}\n',
      'workEntries':
          '[ {"totalHours":7.125,"wages":999.99,"startTime":"bad"} ]',
      'exportRecords': '',
      'dataVersion': 42,
    },
  };

  void rejects(String encoded) {
    expect(
      () => LocalStorage.roundTripRestoreJournalForTesting(encoded),
      throwsA(
        isA<FormatException>()
            .having(
              (e) => e.message,
              'sanitized message',
              'Invalid restore journal.',
            )
            .having((e) => e.source, 'no serialized source', isNull),
      ),
    );
  }

  test('dedicated internal journal key', () {
    expect(LocalStorage.restoreJournalKeyForTesting, 'briska_restore_journal');
  });
  test('round trip preserves exact strings and independent data version', () {
    final fixture = valid();
    final fields = fixture['original']! as Map<String, Object?>;
    final encoded = LocalStorage.encodeRestoreJournalForTesting(
      settings: fields['settings'] as String?,
      workEntries: fields['workEntries'] as String?,
      exportRecords: fields['exportRecords'] as String?,
      dataVersion: fields['dataVersion'] as int?,
    );
    expect(jsonDecode(encoded), fixture);
    expect(
      jsonDecode(LocalStorage.roundTripRestoreJournalForTesting(encoded)),
      fixture,
    );
  });
  test('absent keys remain null rather than empty datasets or defaults', () {
    final encoded = LocalStorage.encodeRestoreJournalForTesting(
      settings: null,
      workEntries: null,
      exportRecords: null,
      dataVersion: null,
    );
    expect(
      jsonDecode(LocalStorage.roundTripRestoreJournalForTesting(encoded)),
      {
        'journalVersion': 1,
        'original': {
          'settings': null,
          'workEntries': null,
          'exportRecords': null,
          'dataVersion': null,
        },
      },
    );
  });
  test('opaque historical data is neither parsed nor normalized', () {
    for (final raw in [
      'not json',
      '{"wages":123.4500,"totalHours":25}',
      '\n',
      '{"a":1,"a":2}',
    ]) {
      final encoded = LocalStorage.encodeRestoreJournalForTesting(
        settings: raw,
        workEntries: raw,
        exportRecords: raw,
        dataVersion: 0,
      );
      final decoded =
          jsonDecode(LocalStorage.roundTripRestoreJournalForTesting(encoded))
              as Map;
      expect(decoded['original'], {
        'settings': raw,
        'workEntries': raw,
        'exportRecords': raw,
        'dataVersion': 0,
      });
    }
  });
  for (final malformed in [
    '',
    '{',
    '{"private":',
    'null',
    '[]',
    '"secret"',
    'true',
  ]) {
    test(
      'rejects malformed JSON or root structure: $malformed',
      () => rejects(malformed),
    );
  }
  for (final version in [0, 2, 1.0, '1', null, true]) {
    test(
      'rejects unsupported or wrongly typed journal version $version (${version.runtimeType})',
      () {
        rejects(jsonEncode(valid()..['journalVersion'] = version));
      },
    );
  }
  for (final key in ['journalVersion', 'original']) {
    test(
      'rejects missing root $key',
      () => rejects(jsonEncode(valid()..remove(key))),
    );
  }
  for (final key in [
    'settings',
    'workEntries',
    'exportRecords',
    'dataVersion',
  ]) {
    test('rejects missing snapshot $key', () {
      final fixture = valid();
      (fixture['original']! as Map).remove(key);
      rejects(jsonEncode(fixture));
    });
    test('rejects wrong types for $key', () {
      for (final value in [true, [], {}, key == 'dataVersion' ? '3' : 3, 3.5]) {
        final fixture = valid();
        (fixture['original']! as Map)[key] = value;
        rejects(jsonEncode(fixture));
      }
    });
  }
  test('rejects unknown fields and invalid snapshot structures', () {
    rejects(jsonEncode(valid()..['unexpected'] = false));
    final fixture = valid();
    (fixture['original']! as Map)['unexpected'] = false;
    rejects(jsonEncode(fixture));
    for (final value in [null, [], 'secret', 1]) {
      rejects(jsonEncode(valid()..['original'] = value));
    }
  });
  test('rejects duplicate and escaped-equivalent keys', () {
    final encoded = jsonEncode(valid());
    rejects(
      encoded.replaceFirst(
        '"journalVersion":1',
        '"journalVersion":2,"journalVersion":1',
      ),
    );
    rejects(
      encoded.replaceFirst(
        '"dataVersion":42',
        '"dataVersion":0,"dataVersion":42',
      ),
    );
    rejects(
      encoded.replaceFirst(
        '"dataVersion":42',
        r'"dataVersion":0,"data\u0056ersion":42',
      ),
    );
  });
}
