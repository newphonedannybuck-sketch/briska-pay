import 'dart:async';

import 'package:briska/main.dart';
import 'package:briska/src/ads/ads_configuration.dart';
import 'package:briska/src/ads/ads_consent_coordinator.dart';
import 'package:briska/src/ads/ads_service.dart';
import 'package:briska/src/app_lock_service.dart';
import 'package:briska/src/briska_app.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/premium_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

final class _FakeConsentCoordinator implements AdsConsentCoordinator {
  _FakeConsentCoordinator({
    this.formRequirement = ConsentFormRequirement.notRequired,
    this.adsAllowed = false,
    this.privacyRequirement = PrivacyOptionsRequirement.notRequired,
    this.updateFailure,
    this.updateCompleter,
    this.formCompleter,
    this.formFailure,
  });

  final ConsentFormRequirement formRequirement;
  final bool adsAllowed;
  final PrivacyOptionsRequirement privacyRequirement;
  final Object? updateFailure;
  final Completer<void>? updateCompleter;
  final Completer<void>? formCompleter;
  final Object? formFailure;
  int updates = 0;
  int forms = 0;
  int privacyForms = 0;
  int canRequestChecks = 0;

  @override
  Future<void> updateConsentInformation() async {
    updates++;
    if (updateFailure != null) throw updateFailure!;
    await updateCompleter?.future;
  }

  @override
  Future<ConsentFormRequirement> consentFormRequirement() async =>
      formRequirement;

  @override
  Future<void> showRequiredConsentForm() async {
    forms++;
    if (formFailure != null) throw formFailure!;
    await formCompleter?.future;
  }

  @override
  Future<bool> canRequestAds() async {
    canRequestChecks++;
    return adsAllowed;
  }

  @override
  Future<PrivacyOptionsRequirement> privacyOptionsRequirement() async =>
      privacyRequirement;

  @override
  Future<void> showPrivacyOptions() async {
    privacyForms++;
  }
}

final class _FakeAdsService implements AdsService {
  _FakeAdsService({this.failure});

  final Object? failure;
  int initializations = 0;
  int bannerRequests = 0;

  @override
  AdsConfiguration get configuration =>
      AdsConfiguration.forEnvironment(AdsEnvironment.test);

  @override
  Future<AdsCapability> capability() async => AdsCapability.testConfigured;

  @override
  Future<void> initialize() async {
    initializations++;
    if (failure != null) throw failure!;
  }

  @override
  Future<LoadedBannerAd?> loadAnchoredAdaptiveBanner(
    double width, {
    ValueChanged<double>? onSizeResolved,
  }) async {
    bannerRequests++;
    return null;
  }
}

Widget _settings({
  required bool privacyRequired,
  required Future<void> Function() showPrivacyOptions,
}) => MaterialApp(
  home: Scaffold(
    body: SettingsScreen(
      preferences: const AppSettings(onboardingCompleted: true),
      lockConfig: const AppLockConfig(),
      onCreateBackup: () async {},
      onRestoreBackup: () async {},
      onLockConfigChanged: (_) async {},
      onSetLockPin: (_) async {},
      onShowAbout: () {},
      onPreferencesChanged: (_) async {},
      onThemeModeChanged: (_) async {},
      privacyOptionsRequired: privacyRequired,
      onShowAdvertisingPrivacyChoices: showPrivacyOptions,
    ),
  ),
);

void main() {
  testWidgets(
    'consent update starts early but forms wait for successful unlock',
    (tester) async {
      final lock = Completer<AppLockConfig>();
      final consent = _FakeConsentCoordinator();
      await tester.pumpWidget(
        BriskaApp(
          adsConsentCoordinator: consent,
          adsService: _FakeAdsService(),
          appLockConfigLoader: () => lock.future,
          pinVerifier: (_) async => true,
        ),
      );
      await tester.pump();
      expect(consent.updates, 1);
      expect(consent.forms, 0);

      lock.complete(const AppLockConfig(enabled: true, hasPin: true));
      await tester.pumpAndSettle();
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(consent.updates, 1);
      expect(consent.forms, 0);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(consent.updates, 1);
      expect(find.byType(HomeScreen), findsOneWidget);
    },
  );

  testWidgets('onboarding remains ahead of consent form handling', (
    tester,
  ) async {
    final consent = _FakeConsentCoordinator();
    await tester.pumpWidget(
      BriskaApp(
        initialSettings: const AppSettings(),
        adsConsentCoordinator: consent,
        adsService: _FakeAdsService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(consent.updates, 1);
    expect(consent.forms, 0);
  });

  testWidgets('required form is shown once and eligible ads initialize once', (
    tester,
  ) async {
    final consent = _FakeConsentCoordinator(
      formRequirement: ConsentFormRequirement.required,
      adsAllowed: true,
      privacyRequirement: PrivacyOptionsRequirement.required,
    );
    final ads = _FakeAdsService();
    await tester.pumpWidget(
      BriskaApp(adsConsentCoordinator: consent, adsService: ads),
    );
    await tester.pumpAndSettle();
    await tester.pump();

    expect(consent.updates, 1);
    expect(consent.forms, 1);
    expect(ads.initializations, 1);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(AdWidget), findsNothing);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Advertising privacy choices'), findsOneWidget);
  });

  testWidgets(
    'displayed consent form can remain open beyond infrastructure timeout',
    (tester) async {
      final dismissal = Completer<void>();
      final consent = _FakeConsentCoordinator(
        formRequirement: ConsentFormRequirement.required,
        adsAllowed: true,
        formCompleter: dismissal,
      );
      final ads = _FakeAdsService();
      await tester.pumpWidget(
        BriskaApp(adsConsentCoordinator: consent, adsService: ads),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(consent.forms, 1);
      expect(consent.canRequestChecks, 0);
      expect(ads.initializations, 1);
      expect(ads.bannerRequests, 0);
      expect(find.textContaining('TimeoutException'), findsNothing);

      dismissal.complete();
      await tester.pumpAndSettle();
      expect(consent.canRequestChecks, 1);
      expect(ads.initializations, 1);
      expect(find.byType(HomeScreen), findsOneWidget);
    },
  );

  testWidgets('delayed dismissal without ad eligibility still opens Home', (
    tester,
  ) async {
    final dismissal = Completer<void>();
    final consent = _FakeConsentCoordinator(
      formRequirement: ConsentFormRequirement.required,
      formCompleter: dismissal,
    );
    final ads = _FakeAdsService();
    await tester.pumpWidget(
      BriskaApp(adsConsentCoordinator: consent, adsService: ads),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    expect(find.byType(HomeScreen), findsOneWidget);

    dismissal.complete();
    await tester.pumpAndSettle();
    expect(consent.canRequestChecks, 1);
    expect(ads.initializations, 1);
    expect(ads.bannerRequests, 0);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('consent update retains its bounded infrastructure timeout', (
    tester,
  ) async {
    final consent = _FakeConsentCoordinator(
      adsAllowed: true,
      updateCompleter: Completer<void>(),
    );
    final ads = _FakeAdsService();
    await tester.pumpWidget(
      BriskaApp(adsConsentCoordinator: consent, adsService: ads),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(consent.canRequestChecks, 0);
    expect(ads.initializations, 1);
    expect(ads.bannerRequests, 0);
    expect(find.textContaining('TimeoutException'), findsNothing);
  });

  testWidgets('genuine form failure remains non-blocking and user-safe', (
    tester,
  ) async {
    final consent = _FakeConsentCoordinator(
      formRequirement: ConsentFormRequirement.required,
      formFailure: Exception('RAW_FORM_ERROR'),
      adsAllowed: true,
    );
    final ads = _FakeAdsService();
    await tester.pumpWidget(
      BriskaApp(adsConsentCoordinator: consent, adsService: ads),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(consent.canRequestChecks, 0);
    expect(ads.initializations, 1);
    expect(find.textContaining('RAW_FORM_ERROR'), findsNothing);
  });

  testWidgets('a non-required form is not shown and ineligible ads stay off', (
    tester,
  ) async {
    final consent = _FakeConsentCoordinator();
    final ads = _FakeAdsService();
    await tester.pumpWidget(
      BriskaApp(adsConsentCoordinator: consent, adsService: ads),
    );
    await tester.pumpAndSettle();
    expect(consent.forms, 0);
    expect(ads.initializations, 1);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('consent and Mobile Ads failures never block core Home', (
    tester,
  ) async {
    final failedConsent = _FakeConsentCoordinator(
      updateFailure: Exception('RAW_CONSENT_ERROR'),
      adsAllowed: true,
    );
    final ads = _FakeAdsService();
    await tester.pumpWidget(
      BriskaApp(adsConsentCoordinator: failedConsent, adsService: ads),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(ads.initializations, 1);
    expect(find.textContaining('RAW_CONSENT_ERROR'), findsNothing);

    final eligibleConsent = _FakeConsentCoordinator(adsAllowed: true);
    await tester.pumpWidget(
      BriskaApp(
        key: UniqueKey(),
        adsConsentCoordinator: eligibleConsent,
        adsService: _FakeAdsService(
          failure: Exception('RAW_INITIALIZATION_ERROR'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('RAW_INITIALIZATION_ERROR'), findsNothing);
  });

  testWidgets('privacy action is conditional and safely handles failure', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      _settings(
        privacyRequired: false,
        showPrivacyOptions: () async => opens++,
      ),
    );
    expect(find.text('Advertising privacy choices'), findsNothing);

    await tester.pumpWidget(
      _settings(
        privacyRequired: true,
        showPrivacyOptions: () async {
          opens++;
          throw Exception('RAW_PRIVACY_ERROR');
        },
      ),
    );
    await tester.ensureVisible(find.text('Advertising privacy choices'));
    await tester.tap(find.text('Advertising privacy choices'));
    await tester.pump();
    expect(opens, 1);
    expect(
      find.text('Could not open advertising privacy choices.'),
      findsOneWidget,
    );
    expect(find.textContaining('RAW_PRIVACY_ERROR'), findsNothing);
  });

  testWidgets('privacy-options interaction has no user decision timeout', (
    tester,
  ) async {
    final dismissal = Completer<void>();
    await tester.pumpWidget(
      _settings(
        privacyRequired: true,
        showPrivacyOptions: () => dismissal.future,
      ),
    );
    await tester.ensureVisible(find.text('Advertising privacy choices'));
    await tester.tap(find.text('Advertising privacy choices'));
    await tester.pump(const Duration(seconds: 16));

    expect(
      find.text('Could not open advertising privacy choices.'),
      findsNothing,
    );
    dismissal.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('Could not open advertising privacy choices.'),
      findsNothing,
    );
  });

  testWidgets('pending consent keeps the main application responsive', (
    tester,
  ) async {
    final pending = Completer<void>();
    final cases = <({Size size, double scale})>[
      (size: const Size(320, 568), scale: 1.5),
      (size: const Size(568, 320), scale: 1.5),
      (size: const Size(320, 568), scale: 2),
      (size: const Size(568, 320), scale: 2),
    ];
    for (final testCase in cases) {
      tester.view.physicalSize = testCase.size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(testCase.scale)),
          child: BriskaApp(
            key: UniqueKey(),
            adsConsentCoordinator: _FakeConsentCoordinator(
              updateCompleter: pending,
            ),
            adsService: _FakeAdsService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    pending.complete();
    await tester.pumpAndSettle();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  test('production consent debug controls and reset are unavailable', () {
    const production = AdsConsentDebugConfiguration.production();
    expect(production.enabled, isFalse);
    expect(production.testDeviceIdentifiers, isEmpty);
    expect(production.geography, ConsentDebugGeography.disabled);
    expect(production.allowReset, isFalse);

    final coordinator = GoogleAdsConsentCoordinator(
      debugConfiguration: production,
    );
    expect(coordinator.resetForTesting, throwsStateError);
  });
}
