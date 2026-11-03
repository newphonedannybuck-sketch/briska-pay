import 'dart:async';

import 'package:briska/main.dart';
import 'package:briska/src/ads/ads_configuration.dart';
import 'package:briska/src/ads/ads_consent_coordinator.dart';
import 'package:briska/src/ads/ads_service.dart';
import 'package:briska/src/ads/briska_banner_ad.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/premium_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeLoadedBanner implements LoadedBannerAd {
  _FakeLoadedBanner({required this.width});

  @override
  final double width;
  @override
  double get height => 50;
  int disposals = 0;

  @override
  Widget buildWidget() =>
      const ColoredBox(key: ValueKey('fake-banner-content'), color: Colors.red);

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

final class _FakeBannerAdsService implements AdsService {
  _FakeBannerAdsService({
    this.adsCapability = AdsCapability.testConfigured,
    this.initializationFailure,
    AdsConfiguration? configuration,
  }) : configuration =
           configuration ??
           AdsConfiguration.forEnvironment(AdsEnvironment.test);

  final AdsCapability adsCapability;
  final Object? initializationFailure;
  @override
  final AdsConfiguration configuration;
  int initializations = 0;
  final List<double> requestedWidths = [];
  final List<Completer<LoadedBannerAd?>> requests = [];

  @override
  Future<AdsCapability> capability() async => adsCapability;

  @override
  Future<void> initialize() async {
    initializations++;
    if (initializationFailure != null) throw initializationFailure!;
  }

  @override
  Future<LoadedBannerAd?> loadAnchoredAdaptiveBanner(
    double width, {
    ValueChanged<double>? onSizeResolved,
  }) {
    requestedWidths.add(width);
    onSizeResolved?.call(50);
    final request = Completer<LoadedBannerAd?>();
    requests.add(request);
    return request.future;
  }
}

final class _FakeConsent implements AdsConsentCoordinator {
  _FakeConsent(this.adsAllowed);
  final bool adsAllowed;

  @override
  Future<bool> canRequestAds() async => adsAllowed;
  @override
  Future<ConsentFormRequirement> consentFormRequirement() async =>
      ConsentFormRequirement.notRequired;
  @override
  Future<PrivacyOptionsRequirement> privacyOptionsRequirement() async =>
      PrivacyOptionsRequirement.notRequired;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  Future<void> showRequiredConsentForm() async {}
  @override
  Future<void> updateConsentInformation() async {}
}

Widget _home(
  _FakeBannerAdsService ads, {
  bool eligible = true,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: Scaffold(
    body: Column(
      children: [
        Expanded(
          child: HomeScreen(
            entries: const [],
            settings: const AppSettings(onboardingCompleted: true),
            onViewEntries: () {},
            onAddEntry: () {},
            onOpenCalendar: () {},
            onOpenReports: () {},
            onOpenExport: () {},
            onConfigurePayday: () {},
          ),
        ),
        if (eligible) BriskaBannerAd(adsService: ads),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      key: const ValueKey('test-fab'),
      onPressed: () {},
    ),
    bottomNavigationBar: const SizedBox(
      key: ValueKey('test-bottom-navigation'),
      height: 64,
    ),
  ),
);

void main() {
  testWidgets(
    'ineligible consent and failed initialization request no banner',
    (tester) async {
      final disallowed = _FakeBannerAdsService();
      await tester.pumpWidget(
        BriskaApp(
          adsConsentCoordinator: _FakeConsent(false),
          adsService: disallowed,
        ),
      );
      await tester.pumpAndSettle();
      expect(disallowed.initializations, 1);
      expect(disallowed.requestedWidths, isEmpty);

      final failedInitialization = _FakeBannerAdsService(
        initializationFailure: Exception('offline'),
      );
      await tester.pumpWidget(
        BriskaApp(
          key: UniqueKey(),
          adsConsentCoordinator: _FakeConsent(true),
          adsService: failedInitialization,
        ),
      );
      await tester.pumpAndSettle();
      expect(failedInitialization.initializations, 1);
      expect(failedInitialization.requestedWidths, isEmpty);
    },
  );

  testWidgets('missing or invalid production configuration requests nothing', (
    tester,
  ) async {
    for (final configuration in [
      AdsConfiguration.forEnvironment(
        AdsEnvironment.production,
        productionBannerAdUnitId: null,
      ),
      AdsConfiguration.forEnvironment(
        AdsEnvironment.production,
        productionBannerAdUnitId: AdsConfiguration.productionAdMobAppId,
      ),
    ]) {
      final ads = _FakeBannerAdsService(
        adsCapability: AdsCapability.unavailable,
        configuration: configuration,
      );
      await tester.pumpWidget(
        BriskaApp(
          key: UniqueKey(),
          adsConsentCoordinator: _FakeConsent(true),
          adsService: ads,
        ),
      );
      await tester.pumpAndSettle();
      expect(ads.requestedWidths, isEmpty);
      expect(
        configuration.bannerAdUnitId,
        isNot(AdsConfiguration.officialAndroidTestBannerAdUnitId),
      );
    }
  });

  testWidgets('UMP gates configured production banner requests', (
    tester,
  ) async {
    final productionConfiguration = AdsConfiguration.forEnvironment(
      AdsEnvironment.production,
    );
    final disallowed = _FakeBannerAdsService(
      adsCapability: AdsCapability.productionConfigured,
      configuration: productionConfiguration,
    );
    await tester.pumpWidget(
      BriskaApp(
        adsConsentCoordinator: _FakeConsent(false),
        adsService: disallowed,
      ),
    );
    await tester.pumpAndSettle();
    expect(disallowed.initializations, 1);
    expect(disallowed.requestedWidths, isEmpty);

    final allowed = _FakeBannerAdsService(
      adsCapability: AdsCapability.productionConfigured,
      configuration: productionConfiguration,
    );
    await tester.pumpWidget(
      BriskaApp(
        key: UniqueKey(),
        adsConsentCoordinator: _FakeConsent(true),
        adsService: allowed,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(allowed.initializations, 1);
    expect(allowed.requestedWidths, hasLength(1));
    expect(
      allowed.configuration.bannerAdUnitId,
      AdsConfiguration.productionBannerAdUnitId,
    );
    expect(
      allowed.configuration.bannerAdUnitId,
      isNot(AdsConfiguration.officialAndroidTestBannerAdUnitId),
    );
  });

  testWidgets('eligible test banner loads once and reserves adaptive height', (
    tester,
  ) async {
    final ads = _FakeBannerAdsService();
    await tester.pumpWidget(_home(ads));
    await tester.pump();
    await tester.pump();

    expect(ads.requestedWidths, hasLength(1));
    expect(
      find.byKey(const ValueKey('loaded-briska-banner-slot')),
      findsNothing,
    );
    final loadingSlot = find.byKey(
      const ValueKey('loading-briska-banner-slot'),
    );
    expect(loadingSlot, findsOneWidget);
    expect(tester.getSize(loadingSlot).height, 50);
    expect(find.byKey(const ValueKey('fake-banner-content')), findsNothing);

    ads.requests.single.complete(
      _FakeLoadedBanner(width: ads.requestedWidths.single),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('loaded-briska-banner-slot')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('fake-banner-content')), findsOneWidget);
    await tester.pump();
    expect(ads.requestedWidths, hasLength(1));
  });

  testWidgets('failed load collapses and loaded placement follows activity', (
    tester,
  ) async {
    final failedAds = _FakeBannerAdsService();
    await tester.pumpWidget(_home(failedAds));
    await tester.pump();
    await tester.pump();
    failedAds.requests.single.complete(null);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('loaded-briska-banner-slot')),
      findsNothing,
    );

    final ads = _FakeBannerAdsService();
    await tester.pumpWidget(_home(ads));
    await tester.pump();
    await tester.pump();
    ads.requests.single.complete(
      _FakeLoadedBanner(width: ads.requestedWidths.single),
    );
    await tester.pump();

    final activity = find.text('Recent activity');
    final banner = find.byKey(const ValueKey('loaded-briska-banner-slot'));
    final clearance = find.byKey(const ValueKey('home-final-bottom-clearance'));
    expect(activity, findsOneWidget);
    expect(banner, findsOneWidget);
    expect(clearance, findsOneWidget);
    await tester.ensureVisible(clearance);
    await tester.pump();
    expect(
      tester.getTopLeft(activity).dy,
      lessThan(tester.getTopLeft(banner).dy),
    );
    expect(
      tester.getBottomLeft(clearance).dy,
      lessThanOrEqualTo(tester.getTopLeft(banner).dy),
    );
    expect(find.byKey(const ValueKey('test-fab')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('test-bottom-navigation')),
      findsOneWidget,
    );
  });

  testWidgets('width change replaces and disposes banner without duplicates', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    final ads = _FakeBannerAdsService();
    final first = _FakeLoadedBanner(width: 360);
    await tester.pumpWidget(_home(ads));
    await tester.pump();
    await tester.pump();
    ads.requests.single.complete(first);
    await tester.pump();
    await tester.pump();
    expect(ads.requests, hasLength(1));

    tester.view.physicalSize = const Size(568, 320);
    await tester.pump();
    await tester.pump();
    expect(ads.requests, hasLength(2));
    final second = _FakeLoadedBanner(width: ads.requestedWidths.last);
    ads.requests.last.complete(second);
    await tester.pump();
    expect(first.disposals, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(second.disposals, 1);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
    'banner layout is responsive at requested sizes and text scales',
    (tester) async {
      final cases = <({Size size, double scale})>[
        (size: const Size(320, 568), scale: 1.5),
        (size: const Size(360, 640), scale: 2),
        (size: const Size(400, 800), scale: 1.5),
        (size: const Size(568, 320), scale: 2),
      ];
      for (final testCase in cases) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = testCase.size;
        final ads = _FakeBannerAdsService();
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(testCase.scale)),
            child: _home(ads),
          ),
        );
        await tester.pump();
        await tester.pump();
        final requestedWidth = ads.requestedWidths.single;
        expect(requestedWidth, lessThanOrEqualTo(testCase.size.width));
        ads.requests.single.complete(_FakeLoadedBanner(width: requestedWidth));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('one shell banner survives every top-level destination change', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    final ads = _FakeBannerAdsService();
    await tester.pumpWidget(
      BriskaApp(adsConsentCoordinator: _FakeConsent(true), adsService: ads),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(ads.requests, hasLength(1));
    final loaded = _FakeLoadedBanner(width: ads.requestedWidths.single);
    ads.requests.single.complete(loaded);
    await tester.pump();

    final destinations = ['Home', 'Entries', 'Reports', 'Export', 'Settings'];
    for (var index = 0; index < destinations.length; index++) {
      if (index > 0) {
        await tester.tap(find.text(destinations[index]).last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(ads.requests, hasLength(1));
      expect(loaded.disposals, 0);

      final banner = find.byKey(const ValueKey('loaded-briska-banner-slot'));
      final navigation = find.byType(NavigationBar);
      expect(banner, findsOneWidget);
      expect(navigation, findsOneWidget);
      expect(
        tester.getBottomLeft(banner).dy,
        lessThanOrEqualTo(tester.getTopLeft(navigation).dy),
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(loaded.disposals, 1);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('shared banner renders in light and dark themes', (tester) async {
    for (final brightness in Brightness.values) {
      final ads = _FakeBannerAdsService();
      await tester.pumpWidget(_home(ads, brightness: brightness));
      await tester.pump();
      await tester.pump();
      final loaded = _FakeLoadedBanner(width: ads.requestedWidths.single);
      ads.requests.single.complete(loaded);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('loaded-briska-banner-slot')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(loaded.disposals, 1);
    }
  });
}
