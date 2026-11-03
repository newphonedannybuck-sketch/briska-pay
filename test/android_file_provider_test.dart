import 'dart:io';

import 'package:briska/src/export_formats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('open-file provider exposes only the internal exports directory', () {
    final paths = File(
      'android/app/src/main/res/xml/filepaths.xml',
    ).readAsStringSync();

    expect(paths, contains('<files-path'));
    expect(paths, contains('path="exports/"'));
    expect(paths, contains('getApplicationSupportDirectory()/exports'));
    expect(paths, isNot(contains('app_flutter/exports')));
    expect(paths, isNot(contains('<root-path')));
    expect(paths, isNot(contains('<external-path')));
    expect(paths, isNot(contains('<external-files-path')));
    expect(paths, isNot(contains('<external-cache-path')));
    expect(paths, isNot(contains('<cache-path')));
    expect(paths, isNot(contains('path="."')));
  });

  test(
    'app manifest permits AdMob network access without broad provider paths',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android.permission.INTERNET'));
      expect(manifest, isNot(contains('<root-path')));
    },
  );

  test('legacy internal exports are eligible for safe migration', () {
    expect(
      ExportFileNamer.isLegacyInternalExportPath(
        '/data/data/com.berkzerker.briska/app_flutter/exports/report.pdf',
      ),
      isTrue,
    );
    expect(
      ExportFileNamer.isLegacyInternalExportPath(
        '/data/user/0/com.berkzerker.briska/app_flutter/exports/report.xlsx',
      ),
      isTrue,
    );
    expect(
      ExportFileNamer.isLegacyInternalExportPath(
        '/data/user/0/com.berkzerker.briska/app_flutter/exports/report.csv',
      ),
      isTrue,
    );
    expect(
      ExportFileNamer.isLegacyInternalExportPath(
        '/storage/emulated/0/Download/report.pdf',
      ),
      isFalse,
    );
  });
}
