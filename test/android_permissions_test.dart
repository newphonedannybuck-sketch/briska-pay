import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final mainManifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  test('main manifest declares only app-required direct permissions', () {
    expect(mainManifest, contains('android.permission.INTERNET'));
    expect(mainManifest, contains('android.permission.USE_BIOMETRIC'));

    final declaredPermissions = RegExp(
      r'<uses-permission\b[^>]*android:name="([^"]+)"[^>]*/>',
      multiLine: true,
    ).allMatches(mainManifest).map((match) => match.group(1)).toList();

    expect(
      declaredPermissions,
      unorderedEquals(const [
        'android.permission.READ_EXTERNAL_STORAGE',
        'android.permission.READ_MEDIA_IMAGES',
        'android.permission.READ_MEDIA_VIDEO',
        'android.permission.READ_MEDIA_AUDIO',
        'android.permission.USE_BIOMETRIC',
        'android.permission.INTERNET',
      ]),
    );
  });

  test('unneeded dangerous permissions are absent or explicitly removed', () {
    for (final permission in const [
      'ACCESS_COARSE_LOCATION',
      'ACCESS_FINE_LOCATION',
      'ACCESS_BACKGROUND_LOCATION',
      'CAMERA',
      'RECORD_AUDIO',
      'POST_NOTIFICATIONS',
      'BLUETOOTH',
      'BLUETOOTH_ADMIN',
      'BLUETOOTH_CONNECT',
      'BLUETOOTH_SCAN',
      'MANAGE_EXTERNAL_STORAGE',
      'WRITE_EXTERNAL_STORAGE',
    ]) {
      expect(
        mainManifest,
        isNot(contains('android.permission.$permission')),
        reason: permission,
      );
    }

    for (final permission in const [
      'READ_EXTERNAL_STORAGE',
      'READ_MEDIA_IMAGES',
      'READ_MEDIA_VIDEO',
      'READ_MEDIA_AUDIO',
    ]) {
      expect(
        RegExp(
          '<uses-permission\\s+'
          'android:name="android\\.permission\\.$permission"\\s+'
          'tools:node="remove"\\s*/>',
        ).hasMatch(mainManifest),
        isTrue,
        reason: permission,
      );
    }
  });

  test('debug and profile manifests add only development internet access', () {
    for (final variant in const ['debug', 'profile']) {
      final manifest = File(
        'android/app/src/$variant/AndroidManifest.xml',
      ).readAsStringSync();
      final permissions = RegExp(
        r'<uses-permission\b[^>]*android:name="([^"]+)"[^>]*/>',
      ).allMatches(manifest).map((match) => match.group(1));

      expect(
        permissions,
        orderedEquals(const ['android.permission.INTERNET']),
        reason: variant,
      );
    }
  });
}
