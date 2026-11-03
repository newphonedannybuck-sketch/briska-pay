import 'package:flutter/foundation.dart';

enum AdsEnvironment { test, production }

enum BannerAdUnitIdSource {
  officialGoogleTest,
  productionConfiguration,
  notConfigured,
}

class AdsConfiguration {
  const AdsConfiguration._({
    required this.environment,
    required this.bannerAdUnitId,
    required this.bannerAdUnitIdSource,
  });

  static const productionAdMobAppId = 'ca-app-pub-2319013319823865~8187046543';
  static const productionBannerAdUnitId =
      'ca-app-pub-2319013319823865/3350927924';
  static const officialAndroidTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  static bool isValidAdMobAppId(String value) =>
      value.startsWith('ca-app-pub-') &&
      value.contains('~') &&
      !value.contains('/');

  static bool isValidBannerAdUnitId(String value) =>
      value.startsWith('ca-app-pub-') &&
      value.contains('/') &&
      !value.contains('~');

  final AdsEnvironment environment;
  final String? bannerAdUnitId;
  final BannerAdUnitIdSource bannerAdUnitIdSource;

  bool get isProductionConfigurationComplete =>
      environment == AdsEnvironment.production &&
      bannerAdUnitIdSource == BannerAdUnitIdSource.productionConfiguration &&
      bannerAdUnitId != null &&
      isValidAdMobAppId(productionAdMobAppId) &&
      isValidBannerAdUnitId(bannerAdUnitId!) &&
      bannerAdUnitId == productionBannerAdUnitId;

  /// [productionBannerAdUnitId] is injectable for configuration safety tests.
  /// Normal release builds use the authoritative constant above.
  factory AdsConfiguration.forEnvironment(
    AdsEnvironment environment, {
    String? productionBannerAdUnitId =
        AdsConfiguration.productionBannerAdUnitId,
  }) {
    if (environment == AdsEnvironment.test) {
      return const AdsConfiguration._(
        environment: AdsEnvironment.test,
        bannerAdUnitId: officialAndroidTestBannerAdUnitId,
        bannerAdUnitIdSource: BannerAdUnitIdSource.officialGoogleTest,
      );
    }

    final productionId = productionBannerAdUnitId?.trim();
    if (productionId == null ||
        !isValidAdMobAppId(productionAdMobAppId) ||
        !isValidBannerAdUnitId(productionId) ||
        productionId != AdsConfiguration.productionBannerAdUnitId) {
      return const AdsConfiguration._(
        environment: AdsEnvironment.production,
        bannerAdUnitId: null,
        bannerAdUnitIdSource: BannerAdUnitIdSource.notConfigured,
      );
    }
    return AdsConfiguration._(
      environment: AdsEnvironment.production,
      bannerAdUnitId: productionId,
      bannerAdUnitIdSource: BannerAdUnitIdSource.productionConfiguration,
    );
  }

  factory AdsConfiguration.current() => AdsConfiguration.forEnvironment(
    kReleaseMode ? AdsEnvironment.production : AdsEnvironment.test,
  );
}
