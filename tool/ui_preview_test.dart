// Render actual Flutter screens without accessing installed app data.
// Run: flutter test tool/ui_preview_test.dart --reporter expanded
// Images: build/ui-preview/ (ignored by Git).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:briska/main.dart';
import 'package:briska/design_system/briska_theme.dart';
import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Poppins');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Poppins-$weight.ttf'));
    }
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    // This optional rendering test lives outside the default test suite.
    // ignore: invalid_use_of_visible_for_testing_member
    PackageInfo.setMockInitialValues(
      appName: 'Briska Pay',
      packageName: 'com.preview.briska',
      version: 'Preview',
      buildNumber: 'UI',
      buildSignature: '',
    );
  });

  for (final mode in ['light', 'dark']) {
    testWidgets('render premium UI $mode', (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final boundaryKey = GlobalKey();
      final now = DateTime.now();
      final entries = List.generate(
        6,
        (i) => WorkEntry(
          id: 'preview-$i',
          date: DateTime(now.year, now.month, now.day - i),
          siteName: i == 0 ? 'Riverside renovation' : 'Oakfield construction',
          startTime: '08:00',
          finishTime: '17:00',
          breakMinutes: 30,
          rateType: i == 1 ? 'secondary' : 'primary',
          hourlyRateUsed: i == 1 ? 32 : 24,
          dailyAllowance: 12,
          jobUplift: i == 0 ? 35 : 0,
          totalHours: 8.5,
          wages: i == 1 ? 272 : 204,
          totalPay: i == 1 ? 284 : (i == 0 ? 251 : 216),
          notes: 'Site completed.',
        ),
      );
      final settings = AppSettings(
        fullName: 'Alex Morgan',
        companyName: 'Morgan Building Services',
        primaryRateValue: 24,
        secondaryRateValue: 32,
        onboardingCompleted: true,
        themeMode: mode,
      );
      Future<void> capture(String name) async {
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/branding/briska-bp-in-app.png'),
            boundaryKey.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('build/ui-preview')
            ..createSync(recursive: true);
          await File(
            '${dir.path}/$mode-$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<void> app() => tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: BriskaApp(
            key: UniqueKey(),
            initialEntries: entries,
            initialSettings: settings,
          ),
        ),
      );
      await app();
      await capture('home');
      for (final tab in ['Entries', 'Reports', 'Export', 'Settings']) {
        await tester.tap(find.text(tab).last);
        await capture(tab.toLowerCase());
      }
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add Day'));
      await capture('add-day');
      await tester.tap(find.text('Holiday'));
      await capture('holiday');
      final hourField = find.byKey(const ValueKey('holiday-hours-field'));
      await tester.ensureVisible(hourField);
      await tester.tap(hourField);
      await tester.pumpAndSettle();
      await capture('holiday-focused');

      Future<void> standalone(String name, Widget child) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: mode == 'light' ? BriskaTheme.light : BriskaTheme.dark,
              debugShowCheckedModeBanner: false,
              home: child,
            ),
          ),
        );
        await capture(name);
      }

      await standalone(
        'onboarding',
        OnboardingScreen(initialSettings: settings, onComplete: (_) async {}),
      );
      await standalone(
        'lock',
        AppLockScreen(
          config: const AppLockConfig(enabled: true, hasPin: true),
          onUnlocked: () {},
          verifyPin: (_) async => false,
        ),
      );
      await standalone(
        'recovery',
        StartupRecoveryScreen(
          error: 'Preview',
          dataIsCorrupt: true,
          onRetry: () async {},
          onRestoreBackup: () async {},
          onResetLocalData: () async {},
        ),
      );
      await standalone(
        'about',
        const AboutBriskaScreen(showTesterTools: false),
      );
      await standalone(
        'legal',
        const LegalTextScreen(
          title: 'Privacy Policy',
          assetPath: 'assets/legal/privacy_policy.md',
        ),
      );
      for (final scenario in [
        (name: 'narrow', size: Size(320, 568), scale: 1.0),
        (name: 'large-text', size: Size(360, 800), scale: 2.0),
        (name: 'landscape', size: Size(844, 390), scale: 1.0),
      ]) {
        tester.view.physicalSize = scenario.size;
        tester.platformDispatcher.textScaleFactorTestValue = scenario.scale;
        await app();
        for (final tab in [
          'Home',
          'Entries',
          'Reports',
          'Export',
          'Settings',
        ]) {
          await tester.tap(find.text(tab).last);
          await capture('${scenario.name}-${tab.toLowerCase()}');
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
