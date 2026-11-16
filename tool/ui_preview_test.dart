// Render actual Flutter screens without accessing installed app data.
// Run: flutter test tool/ui_preview_test.dart --reporter expanded
// Home-only review: flutter test tool/ui_preview_test.dart --dart-define=HOME_ONLY=true
// Images and generated review index: build/ui-preview/ (ignored by Git).
import 'dart:io';
import 'dart:convert';
import 'package:briska/src/backup_service.dart';
import 'package:briska/src/ads/ads_configuration.dart';
import 'package:briska/src/ads/ads_consent_coordinator.dart';
import 'package:briska/src/ads/ads_service.dart';
import 'package:briska/src/local_storage.dart';
import 'package:briska/screens/loading_screen.dart';
import 'dart:ui' as ui;

import 'package:briska/main.dart';
import 'package:briska/design_system/briska_theme.dart';
import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/currency.dart';
import 'package:briska/src/screens/settings/app_lock_pin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  const homeOnly = bool.fromEnvironment('HOME_ONLY');
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
      // This rendering test is outside test/ and uses the same isolated storage hook.
      // ignore: invalid_use_of_visible_for_testing_member
      addTearDown(() => LocalStorage.readStringOverride = null);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final boundaryKey = GlobalKey();
      final captures = <String>[];
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
      {
        for (var i = 0; i < 3; i++) {
          entries.add(
            WorkEntry(
              id: 'time-off-$i',
              entryType: i == 2 ? EntryType.bankHoliday : EntryType.holiday,
              date: DateTime(now.year, now.month, now.day - 7 - i),
              siteName: '',
              startTime: '',
              finishTime: '',
              breakMinutes: 0,
              hourlyRateUsed: 24,
              dailyAllowance: 0,
              jobUplift: 0,
              totalHours: 0,
              wages: 0,
              totalPay: 0,
              notes: '',
            ),
          );
        }
      }
      final settings = AppSettings(
        fullName: 'Alex Morgan',
        companyName: 'Morgan Building Services',
        primaryRateValue: 24,
        secondaryRateValue: 32,
        onboardingCompleted: true,
        themeMode: mode,
      );
      Future<void> capture(String name, {bool settle = true}) async {
        if (!name.endsWith('launcher')) captures.add(name);
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/branding/briska-bp-in-app.png'),
            boundaryKey.currentContext!,
          ),
        );
        if (settle) await tester.pumpAndSettle();
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
      if (!homeOnly) {
        await tester.runAsync(() async {
          final fixture = File('build/ui-preview/preview-backup.json');
          await fixture.parent.create(recursive: true);
          await File(
            'build/ui-preview/preview-report.pdf',
          ).writeAsString('%PDF-1.4\n%%EOF');
          await fixture.writeAsString(
            jsonEncode(
              BriskaBackupData(
                createdAt: now,
                settings: settings,
                workEntries: entries,
                exportRecords: [],
              ).toJson(),
            ),
          );
        });
        const picker = MethodChannel('plugins.flutter.io/file_selector');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              picker,
              (_) async => [
                File('build/ui-preview/preview-backup.json').absolute.path,
              ],
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(picker, null),
        );
      }
      await app();
      await capture('home');
      if (!homeOnly) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('recent-activity-preview-0')),
        );
        await tester.tap(
          find.byKey(const ValueKey('recent-activity-preview-0')),
        );
        await capture('entry-details');
        await tester.ensureVisible(find.text('Edit Entry'));
        await capture('entry-details-bottom');
        await app();
        for (final tab in ['Entries', 'Reports', 'Export', 'Settings']) {
          await tester.tap(find.text(tab).last);
          await capture(tab.toLowerCase());
          if (tab == 'Entries') {
            await tester.ensureVisible(
              find.byKey(const ValueKey('entry-card-preview-0')),
            );
            await capture('entry-list');
            await tester.ensureVisible(
              find.widgetWithText(TextButton, 'Delete').first,
            );
            await tester.tap(find.widgetWithText(TextButton, 'Delete').first);
            await capture('delete-day-dialog');
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
          }
          if (tab == 'Export') {
            await tester.tap(find.widgetWithText(ChoiceChip, 'Custom dates'));
            await capture('export-custom-dates');
            await tester.tap(find.text('From date'));
            await capture('date-picker');
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
            await tester.tap(find.widgetWithText(ChoiceChip, 'This month'));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('More options'));
            await tester.tap(find.text('More options'));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('Export report'));
            await capture('export-options');
          }
          if (tab == 'Reports') {
            await tester.ensureVisible(find.text('Work pattern'));
            await capture('reports-work-pattern');
          }
          if (tab == 'Settings') {
            for (final section in [
              'Pay & currency',
              'Work defaults',
              'Pay schedule',
              'Appearance',
              'Backup & restore',
            ]) {
              final finder = find.text(section);
              if (finder.evaluate().isNotEmpty) {
                await tester.ensureVisible(finder);
                await capture(
                  'settings-${section.toLowerCase().replaceAll(RegExp('[^a-z]+'), '-')}',
                );
              }
            }
            await tester.ensureVisible(find.text('Security'));
            await capture('settings-security');
            await tester.ensureVisible(find.text('Restore Briska Pay Backup'));
            await tester.tap(find.text('Restore Briska Pay Backup'));
            for (
              var attempt = 0;
              attempt < 50 &&
                  find.text('Restore Briska Pay backup?').evaluate().isEmpty;
              attempt++
            ) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await tester.pump();
            }
            expect(find.text('Restore Briska Pay backup?'), findsOneWidget);
            await capture('restore-confirmation');
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
            final currency = find.byWidgetPredicate(
              (widget) =>
                  widget is DropdownButtonFormField<String> &&
                  widget.initialValue == settings.currency.code,
            );
            await tester.ensureVisible(currency);
            tester.widget<DropdownButtonFormField<String>>(currency).onChanged!(
              'USD',
            );
            await capture('currency-confirmation');
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
          }
        }
        await tester.tap(find.text('Home').last);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FloatingActionButton, 'Add Day'));
        await capture('add-day');
        for (final type in ['Bank Holiday', 'Sick Day', 'Unpaid Day Off']) {
          await tester.ensureVisible(find.widgetWithText(ChoiceChip, type));
          await tester.tap(find.widgetWithText(ChoiceChip, type));
          await capture('add-${type.toLowerCase().replaceAll(' ', '-')}');
        }
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Holiday'));
        await tester.tap(find.widgetWithText(ChoiceChip, 'Holiday'));
        await capture('holiday');
        await tester.tap(find.text('Save Entry'));
        await capture('duplicate-entry-dialog');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        final hourField = find.byKey(const ValueKey('holiday-hours-field'));
        await tester.ensureVisible(hourField);
        await tester.tap(hourField);
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await capture('holiday-focused');
        tester.view.resetViewInsets();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await capture('discard-changes-dialog');
        await tester.tap(find.text('Keep Editing'));

        Future<void> standalone(String name, Widget child) async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                key: UniqueKey(),
                theme: mode == 'light' ? BriskaTheme.light : BriskaTheme.dark,
                debugShowCheckedModeBanner: false,
                home: child,
              ),
            ),
          );
          await capture(name);
        }

        for (final type in EntryType.values) {
          final edited = type == EntryType.workDay
              ? entries.first
              : WorkEntry(
                  id: 'edit-${type.name}',
                  entryType: type,
                  date: now,
                  siteName: '',
                  startTime: '',
                  finishTime: '',
                  breakMinutes: 0,
                  hourlyRateUsed: 24,
                  dailyAllowance: 0,
                  jobUplift: 0,
                  totalHours: 0,
                  wages: 0,
                  totalPay: 0,
                  notes: '',
                );
          await standalone(
            'edit-${type.name}',
            AddWorkDayScreen(
              preferences: settings,
              savedEntries: [edited],
              initialEntry: edited,
              onSave: (_) async => true,
            ),
          );
        }
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/branding/briska-bp-splash.png'),
            boundaryKey.currentContext!,
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              key: UniqueKey(),
              debugShowCheckedModeBanner: false,
              theme: mode == 'light' ? BriskaTheme.light : BriskaTheme.dark,
              home: LoadingScreen(
                useLocalStorage: false,
                initialSettings: settings,
              ),
            ),
          ),
        );
        await capture('launch-splash', settle: false);
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
        await tester.enterText(find.byType(TextField), '1234');
        await tester.tap(find.text('Unlock'));
        await capture('lock-error');
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
        await tester.ensureVisible(find.text('Open Source Licences'));
        await tester.tap(find.text('Open Source Licences'));
        await capture('licences');
        await standalone(
          'terms',
          const LegalTextScreen(
            title: 'Terms of Use',
            assetPath: 'assets/legal/terms_disclaimer.md',
          ),
        );
        await standalone('beta-checklist', const BetaChecklistScreen());
        await tester.ensureVisible(find.text('Reset checklist'));
        await tester.tap(find.text('Reset checklist'));
        await capture('checklist-reset-dialog');
        await standalone(
          'legal',
          const LegalTextScreen(
            title: 'Privacy Policy',
            assetPath: 'assets/legal/privacy_policy.md',
          ),
        );
        await standalone('support', const SupportScreen());
        await standalone(
          'security-error',
          AppLockInitializationErrorScreen(onRetry: () async {}),
        );
        await standalone(
          'startup',
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const StartupInitializationScreen(),
            ),
          ),
        );
        await standalone(
          'export-library',
          ExportLibraryScreen(
            records: [
              ExportedFileRecord(
                id: 'preview-file',
                fileName: 'Alex_Morgan_30_November_2026.pdf',
                fileType: 'PDF Timesheet',
                filePath: File(
                  'build/ui-preview/preview-report.pdf',
                ).absolute.path,
                exportedAt: now,
                periodLabel: 'November 2026',
                workDays: 6,
                totalHours: 51,
                totalPay: 1399,
                fileSize: 24576,
              ),
            ],
            onUpdate: (_) async => true,
            onDelete: (_) async => true,
          ),
        );
        await tester.ensureVisible(find.text('Rename'));
        await tester.tap(find.text('Rename'));
        await capture('rename-dialog');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Delete'));
        await tester.tap(find.text('Delete'));
        await capture('delete-dialog');
        await tester.tap(find.text('Delete file and remove from library'));
        await capture('delete-file-confirmation');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await standalone(
          'export-library-missing',
          ExportLibraryScreen(
            records: [
              ExportedFileRecord(
                id: 'missing',
                fileName: 'Missing_Report.pdf',
                fileType: 'PDF Timesheet',
                filePath: '',
                exportedAt: now,
                periodLabel: 'November 2026',
                workDays: 6,
                totalHours: 51,
                totalPay: 1399,
              ),
            ],
            onUpdate: (_) async => true,
            onDelete: (_) async => true,
          ),
        );

        // ignore: invalid_use_of_visible_for_testing_member
        LocalStorage.readStringOverride = (key) async =>
            key == 'work_entries_v1' ? 'invalid-preview-data' : null;
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: BriskaApp(
              key: UniqueKey(),
              useLocalStorage: true,
              adsConsentCoordinator: const InactiveAdsConsentCoordinator(),
              adsService: DisabledAdsService(AdsConfiguration.current()),
              initialSettings: settings,
              appLockConfigLoader: () async => const AppLockConfig(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reset local data'));
        await capture('reset-data-confirmation');
        await tester.tap(find.text('Cancel'));
        // ignore: invalid_use_of_visible_for_testing_member
        LocalStorage.readStringOverride = null;
        await standalone(
          'pin-launcher',
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showAppLockPinDialog(
                    context,
                    disabling: false,
                    hasPin: () => true,
                    onDisableLock: (_) async {},
                    onSetLockPin: (_, _) async {},
                  ),
                  child: const Text('Open PIN'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open PIN'));
        await capture('pin-dialog');
        await tester.tap(find.text('Cancel'));
        for (final disabling in [true, false]) {
          await standalone(
            'security-launcher',
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showAppLockPinDialog(
                      context,
                      disabling: disabling,
                      hasPin: () => false,
                      onDisableLock: (_) async {},
                      onSetLockPin: (_, _) async {},
                    ),
                    child: const Text('Open security'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open security'));
          await capture(
            disabling ? 'disable-lock-dialog' : 'create-pin-dialog',
          );
        }
        await standalone(
          'export-created-launcher',
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => ExportCreatedDialog(
                      record: ExportedFileRecord(
                        id: 'created',
                        fileName: 'Alex_Morgan_November_2026_Timesheet.pdf',
                        fileType: 'PDF Timesheet',
                        filePath: '',
                        exportedAt: now,
                        periodLabel: 'November 2026',
                        workDays: 6,
                        totalHours: 51,
                        totalPay: 1399,
                        fileSize: 24576,
                      ),
                      onDone: () => Navigator.pop(dialogContext),
                      onOpen: () {},
                      onPrint: () {},
                      onShare: () {},
                    ),
                  ),
                  child: const Text('Show export'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Show export'));
        await capture('export-created-dialog');
        await standalone(
          'export-library-empty',
          ExportLibraryScreen(
            records: const [],
            onUpdate: (_) async => true,
            onDelete: (_) async => true,
          ),
        );
        await standalone(
          'restore-recovery',
          StartupRecoveryScreen(
            error: 'Preview',
            dataIsCorrupt: true,
            restoreRecoveryRequired: true,
            onRetry: () async {},
            onRestoreBackup: () async {},
            onResetLocalData: () async {},
          ),
        );
      }
      final stress = WorkEntry(
        id: 'large',
        date: now,
        siteName: 'Long construction site and renovation project name',
        startTime: '22:00',
        finishTime: '06:00',
        breakMinutes: 30,
        hourlyRateUsed: 1234567,
        dailyAllowance: 0,
        jobUplift: 0,
        totalHours: 7.5,
        wages: 123456789.12,
        totalPay: 123456789.12,
        notes: '',
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: BriskaApp(
            key: UniqueKey(),
            initialEntries: [stress],
            initialSettings: settings.copyWith(
              currency: CurrencyCatalog.byCode('INR'),
              fullName: 'Alexandra Morgan-Williams',
              companyName:
                  'Morgan Building and Restoration Services International',
            ),
          ),
        ),
      );
      await capture('large-currency');
      if (!homeOnly) {
        for (final tab in ['Entries', 'Reports', 'Export', 'Settings']) {
          await tester.tap(find.text(tab).last);
          await capture('large-currency-${tab.toLowerCase()}');
          if (tab == 'Entries') {
            await tester.ensureVisible(
              find.byKey(const ValueKey('entry-card-large')),
            );
            await capture('long-entry-name');
          }
        }
      }
      if (homeOnly) {
        tester.view.physicalSize = const Size(320, 568);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await capture('narrow-large-currency-text');
        await tester.ensureVisible(
          find
              .descendant(
                of: find.byType(PageView),
                matching: find.byType(FittedBox),
              )
              .first,
        );
        await capture('narrow-large-currency-amount');
        await tester.ensureVisible(
          find.byKey(const ValueKey('home-final-bottom-clearance')),
        );
        await capture('narrow-large-currency-text-bottom');
      }
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
          if (!homeOnly) ...['Entries', 'Reports', 'Export', 'Settings'],
        ]) {
          await tester.tap(find.text(tab).last);
          await capture('${scenario.name}-${tab.toLowerCase()}');
          if (tab == 'Home') {
            await tester.ensureVisible(
              find.byKey(const ValueKey('home-time-off-tiles')),
            );
            await capture('${scenario.name}-home-time-off');
            await tester.ensureVisible(
              find.byKey(const ValueKey('home-final-bottom-clearance')),
            );
            await capture('${scenario.name}-home-bottom');
          }
        }
        if (!homeOnly) {
          await tester.tap(find.text('Home').last);
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Add Day'));
          await capture('${scenario.name}-add-day');
          await tester.ensureVisible(
            find.widgetWithText(ChoiceChip, 'Holiday'),
          );
          await tester.tap(find.widgetWithText(ChoiceChip, 'Holiday'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('holiday-hours-field')),
          );
          await capture('${scenario.name}-holiday-hours');
        }
      }
      {
        await tester.runAsync(() async {
          final html = StringBuffer(
            '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Briska Pay · Complete UI review</title><style>body{margin:32px;background:#f4f4f2;color:#202420;font:16px system-ui}p{max-width:800px;line-height:1.6}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px}figure{margin:0;padding:16px;background:white;border-radius:16px}img{max-width:100%;height:auto}figcaption{margin-bottom:12px}a{color:#22664d}</style><h1>Briska Pay · Complete UI review</h1><p>Approved mockup implementation: tinted earnings panel and recorded step chart, payday strip, lavender and amber time-off tiles, compact activity. Chart and time off follow the selected period. Blank and explicit zero hours are indistinguishable in existing storage; no hours are inferred. Actual Flutter renders with sample data. Native ad pixels are not rendered; advertising and consent remain unchanged. Bottom views show scroll reachability. All application routes inherit the same light/dark surfaces, inputs and dialog styling. Native OS file pickers, biometric prompts, keyboards and live ads are outside these Flutter renders.</p>',
          );
          for (final theme in ['light', 'dark']) {
            html.write('<h2>$theme</h2><main>');
            for (final name in captures.toSet()) {
              html.write(
                '<figure><figcaption>$name</figcaption><a href="$theme-$name.png"><img loading="lazy" src="$theme-$name.png" alt="$theme $name"></a></figure>',
              );
            }
            html.write('</main>');
          }
          html.write('</html>');
          await File(
            'build/ui-preview/index.html',
          ).writeAsString(html.toString());
        });
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
