import 'dart:io';

import 'package:briska/main.dart';
import 'package:briska/src/ads/ads_configuration.dart';
import 'package:briska/src/ads/ads_consent_coordinator.dart';
import 'package:briska/src/ads/ads_service.dart';
import 'package:briska/src/app_lock_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

final class _FakeAdsService implements AdsService {
  _FakeAdsService(this.configuration);

  @override
  final AdsConfiguration configuration;

  var capabilityRequests = 0;
  var initializationRequests = 0;

  @override
  Future<AdsCapability> capability() async {
    capabilityRequests++;
    return AdsCapability.testConfigured;
  }

  @override
  Future<void> initialize() async {
    initializationRequests++;
  }

  @override
  Future<LoadedBannerAd?> loadAnchoredAdaptiveBanner(
    double width, {
    ValueChanged<double>? onSizeResolved,
  }) async => null;
}

final class _FakeConsentCoordinator implements AdsConsentCoordinator {
  var updateRequests = 0;

  @override
  Future<bool> canRequestAds() async => true;

  @override
  Future<ConsentFormRequirement> consentFormRequirement() async =>
      ConsentFormRequirement.required;

  @override
  Future<PrivacyOptionsRequirement> privacyOptionsRequirement() async =>
      PrivacyOptionsRequirement.required;

  @override
  Future<void> showPrivacyOptions() async {}

  @override
  Future<void> showRequiredConsentForm() async {}

  @override
  Future<void> updateConsentInformation() async {
    updateRequests++;
  }
}

void main() {
  test(
    'Android manifest contains the production app ID and safe permissions',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android.permission.INTERNET'));
      expect(manifest, contains('com.google.android.gms.ads.APPLICATION_ID'));
      expect(manifest, contains(AdsConfiguration.productionAdMobAppId));
      for (final permission in <String>[
        'READ_EXTERNAL_STORAGE',
        'READ_MEDIA_IMAGES',
        'READ_MEDIA_VIDEO',
        'READ_MEDIA_AUDIO',
      ]) {
        expect(
          manifest,
          contains(
            'android:name="android.permission.$permission"\n'
            '        tools:node="remove"',
          ),
        );
      }
    },
  );

  test('test and production banner configuration never cross-fallback', () {
    final testConfiguration = AdsConfiguration.forEnvironment(
      AdsEnvironment.test,
      productionBannerAdUnitId: AdsConfiguration.productionBannerAdUnitId,
    );
    final missingProductionConfiguration = AdsConfiguration.forEnvironment(
      AdsEnvironment.production,
      productionBannerAdUnitId: null,
    );
    final productionConfiguration = AdsConfiguration.forEnvironment(
      AdsEnvironment.production,
    );

    expect(
      testConfiguration.bannerAdUnitId,
      AdsConfiguration.officialAndroidTestBannerAdUnitId,
    );
    expect(
      testConfiguration.bannerAdUnitIdSource,
      BannerAdUnitIdSource.officialGoogleTest,
    );
    expect(
      testConfiguration.bannerAdUnitId,
      isNot(AdsConfiguration.productionBannerAdUnitId),
    );

    expect(missingProductionConfiguration.bannerAdUnitId, isNull);
    expect(
      missingProductionConfiguration.bannerAdUnitIdSource,
      BannerAdUnitIdSource.notConfigured,
    );
    expect(
      missingProductionConfiguration.isProductionConfigurationComplete,
      isFalse,
    );
    expect(
      missingProductionConfiguration.bannerAdUnitId,
      isNot(AdsConfiguration.officialAndroidTestBannerAdUnitId),
    );

    expect(
      productionConfiguration.bannerAdUnitId,
      AdsConfiguration.productionBannerAdUnitId,
    );
    expect(
      productionConfiguration.bannerAdUnitIdSource,
      BannerAdUnitIdSource.productionConfiguration,
    );
    expect(productionConfiguration.isProductionConfigurationComplete, isTrue);
    expect(
      productionConfiguration.bannerAdUnitId,
      isNot(AdsConfiguration.officialAndroidTestBannerAdUnitId),
    );
  });

  test('production identifiers are authoritative and type-safe', () {
    expect(
      AdsConfiguration.productionBannerAdUnitId,
      'ca-app-pub-2319013319823865/3350927924',
    );
    expect(
      AdsConfiguration.productionAdMobAppId,
      'ca-app-pub-2319013319823865~8187046543',
    );
    expect(
      AdsConfiguration.officialAndroidTestBannerAdUnitId,
      'ca-app-pub-3940256099942544/6300978111',
    );
    expect(
      AdsConfiguration.isValidAdMobAppId(AdsConfiguration.productionAdMobAppId),
      isTrue,
    );
    expect(
      AdsConfiguration.isValidBannerAdUnitId(
        AdsConfiguration.productionBannerAdUnitId,
      ),
      isTrue,
    );
    expect(
      AdsConfiguration.isValidBannerAdUnitId(
        AdsConfiguration.productionAdMobAppId,
      ),
      isFalse,
    );
    expect(
      AdsConfiguration.isValidAdMobAppId(
        AdsConfiguration.productionBannerAdUnitId,
      ),
      isFalse,
    );
  });

  test('invalid production banner identifiers fail safely', () {
    for (final invalidId in <String?>[
      null,
      '',
      'not-an-ad-unit',
      AdsConfiguration.productionAdMobAppId,
      AdsConfiguration.officialAndroidTestBannerAdUnitId,
    ]) {
      final configuration = AdsConfiguration.forEnvironment(
        AdsEnvironment.production,
        productionBannerAdUnitId: invalidId,
      );
      expect(configuration.bannerAdUnitId, isNull);
      expect(
        configuration.bannerAdUnitIdSource,
        BannerAdUnitIdSource.notConfigured,
      );
      expect(configuration.isProductionConfigurationComplete, isFalse);
    }
  });

  test(
    'release advertising capability is configured without contacting Google',
    () async {
      final production = GoogleMobileAdsService(
        AdsConfiguration.forEnvironment(AdsEnvironment.production),
      );
      final missing = GoogleMobileAdsService(
        AdsConfiguration.forEnvironment(
          AdsEnvironment.production,
          productionBannerAdUnitId: null,
        ),
      );

      expect(await production.capability(), AdsCapability.productionConfigured);
      expect(await missing.capability(), AdsCapability.unavailable);
    },
  );

  test(
    'advertising and consent boundaries are replaceable with fakes',
    () async {
      final ads = _FakeAdsService(
        AdsConfiguration.forEnvironment(AdsEnvironment.test),
      );
      final consent = _FakeConsentCoordinator();

      expect(await ads.capability(), AdsCapability.testConfigured);
      await consent.updateConsentInformation();
      expect(await consent.canRequestAds(), isTrue);
      expect(ads.capabilityRequests, 1);
      expect(consent.updateRequests, 1);
    },
  );

  testWidgets('startup prewarms ads without requesting one before unlock', (
    tester,
  ) async {
    final ads = _FakeAdsService(
      AdsConfiguration.forEnvironment(AdsEnvironment.test),
    );
    final consent = _FakeConsentCoordinator();

    await tester.pumpWidget(
      BriskaApp(
        adsConsentCoordinator: consent,
        adsService: ads,
        appLockConfigLoader: () async =>
            const AppLockConfig(enabled: true, hasPin: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdWidget), findsNothing);
    expect(ads.initializationRequests, 1);
    expect(ads.capabilityRequests, 0);
    expect(consent.updateRequests, 1);
  });
}
