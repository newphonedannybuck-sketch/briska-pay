import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String resource(String path) =>
      File('android/app/src/main/res/$path').readAsStringSync();

  test('Android 12 splash uses Briska production mark and background', () {
    for (final path in const [
      'values-v31/styles.xml',
      'values-night-v31/styles.xml',
    ]) {
      final styles = resource(path);
      expect(styles, contains('name="LaunchTheme"'));
      expect(
        styles,
        contains(
          '<item name="android:windowSplashScreenBackground">'
          '@color/briska_background</item>',
        ),
      );
      expect(
        styles,
        contains(
          '<item name="android:windowSplashScreenAnimatedIcon">'
          '@drawable/briska_splash_mark</item>',
        ),
      );
      expect(styles, contains('name="NormalTheme"'));
    }
  });

  test('Android 7 to 11 launch themes use the branded background', () {
    for (final path in const ['values/styles.xml', 'values-night/styles.xml']) {
      final styles = resource(path);
      expect(
        styles,
        contains(
          '<item name="android:windowBackground">'
          '@drawable/launch_background</item>',
        ),
      );
    }
    final background = resource('drawable/launch_background.xml');
    expect(background, contains('@color/briska_background'));
    expect(background, contains('@drawable/briska_splash_mark'));
  });

  test('splash mark is mark-only and does not reuse launcher tile', () {
    final mark = File(
      'android/app/src/main/res/drawable-nodpi/briska_splash_mark.png',
    );
    final allSplashResources = [
      resource('drawable/launch_background.xml'),
      resource('values-v31/styles.xml'),
      resource('values-night-v31/styles.xml'),
    ].join();

    expect(mark.existsSync(), isTrue);
    expect(mark.lengthSync(), greaterThan(0));
    expect(allSplashResources, isNot(contains('ic_launcher')));
    expect(allSplashResources, isNot(contains('flutter')));
  });

  test('manifest transitions from LaunchTheme to Flutter NormalTheme', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:theme="@style/LaunchTheme"'));
    expect(
      manifest,
      contains('android:name="io.flutter.embedding.android.NormalTheme"'),
    );
    expect(manifest, contains('android:resource="@style/NormalTheme"'));
  });
}
